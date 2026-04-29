library(shiny)
library(jsonlite)

# ── Helpers ────────────────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (is.null(a) || identical(a, NA) || identical(a, "")) b else a

# Base working directory for Raven models
WORK_BASE <- file.path(tempdir(), "raven_work")

server <- function(input, output, session) {

  # ── Run history: server-side storage for multi-run comparison ────────────────
  # Stores up to 8 previous runs in R session memory (survives across browser
  # interactions within the same R session, lost on app restart)
  run_history <- reactiveVal(list())   # list of {run_id, label, timestamp, files, contents}
  run_counter <- reactiveVal(0L)
  MAX_RUN_HISTORY <- 8L

  # ── Clean up when browser session ends ──────────────────────────────────────
  # Note: stopApp() is NOT called — on hosted platforms (Connect Cloud) it would
  # kill the app for all users. The platform manages app lifecycle automatically.
  session$onSessionEnded(function() {
    cat("[RAVEN] Session ended.\n")
  })

  # ── Send message back to iframe ──────────────────────────────────────────────
  send_to_iframe <- function(obj) {
    session$sendCustomMessage("to_interface", obj)
  }

  # ── On connect: ping back readiness ──────────────────────────────────────────
  session$onFlushed(function() {
    send_to_iframe(list(type = "shiny_ready"))
  })

  # ── Receive messages from iframe ─────────────────────────────────────────────
  observeEvent(input$iframe_msg, {
    raw <- input$iframe_msg$raw
    if (is.null(raw) || !nzchar(raw)) return()

    msg <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = FALSE),
                    error = function(e) NULL)
    if (is.null(msg) || is.null(msg$type)) return()

    # ── PING: health check ─────────────────────────────────────────────────────
    if (msg$type == "ping") {
      send_to_iframe(list(type = "pong", raven_available = check_raven_available()))
      return()
    }

    # ── VALIDATE: check all required files are present ─────────────────────────
    if (msg$type == "validate_model") {
      tryCatch({
        result <- validate_model(msg)
        send_to_iframe(list(type = "validation_result",
                            status = result$status,
                            messages = result$messages,
                            files = result$files))
      }, error = function(e) {
        send_to_iframe(list(type = "validation_result",
                            status = "error",
                            messages = list(paste("Validation error:", conditionMessage(e))),
                            files = list()))
      })
      return()
    }

    # ── EXECUTE: run the Raven model ───────────────────────────────────────────
    if (msg$type == "execute_model") {
      tryCatch({
        execute_raven(msg, send_to_iframe)
      }, error = function(e) {
        send_to_iframe(list(type = "run_status", status = "error",
                            message = paste("Execution error:", conditionMessage(e))))
      })
      return()
    }

    # ── UPLOAD_FILE: receive binary file data (base64 encoded) ─────────────────
    if (msg$type == "upload_file") {
      tryCatch({
        receive_file(msg)
        send_to_iframe(list(type = "file_received",
                            filename = msg$filename,
                            status = "ok"))
      }, error = function(e) {
        send_to_iframe(list(type = "file_received",
                            filename = msg$filename %||% "unknown",
                            status = "error",
                            message = conditionMessage(e)))
      })
      return()
    }

    # ── LIST_OUTPUTS: return list of output files ──────────────────────────────
    if (msg$type == "list_outputs") {
      tryCatch({
        outputs <- list_output_files(msg$model_name %||% "model")
        send_to_iframe(list(type = "output_list", files = outputs))
      }, error = function(e) {
        send_to_iframe(list(type = "output_list", files = list(),
                            error = conditionMessage(e)))
      })
      return()
    }

    # ── READ_OUTPUT: read a specific output file ───────────────────────────────
    if (msg$type == "read_output") {
      tryCatch({
        content <- read_output_file(msg$model_name %||% "model", msg$filename)
        send_to_iframe(list(type = "output_content",
                            filename = msg$filename,
                            content = content$text,
                            is_binary = content$is_binary))
      }, error = function(e) {
        send_to_iframe(list(type = "output_content",
                            filename = msg$filename %||% "unknown",
                            content = paste("Error reading file:", conditionMessage(e)),
                            is_binary = FALSE))
      })
      return()
    }

    # ── LIST_RUNS: return list of archived runs for multi-run comparison ──────
    if (msg$type == "list_runs") {
      hist <- run_history()
      runs <- lapply(hist, function(r) list(
        run_id = r$run_id, label = r$label, timestamp = r$timestamp,
        file_count = length(r$files)
      ))
      send_to_iframe(list(type = "run_history_list", runs = runs))
      return()
    }

    # ── GET_RUN_OUTPUTS: return all output contents for a historical run ──────
    if (msg$type == "get_run_outputs") {
      run_id <- msg$run_id
      hist <- run_history()
      entry <- Find(function(r) r$run_id == run_id, hist)
      if (is.null(entry)) {
        send_to_iframe(list(type = "run_history_outputs", run_id = run_id,
                            output_contents = list(), error = "Run not found"))
      } else {
        send_to_iframe(list(type = "run_history_outputs", run_id = run_id,
                            label = entry$label, output_contents = entry$contents))
      }
      return()
    }
  })

  # ════════════════════════════════════════════════════════════════════════════
  # HELPER FUNCTIONS
  # ════════════════════════════════════════════════════════════════════════════

  # OS detection helper
  is_linux <- function() .Platform$OS.type == "unix"

  # Check glibc compatibility — returns list(compatible, sys_ver, build_ver, message)
  check_glibc_compat <- function() {
    if (!is_linux()) return(list(compatible = TRUE))

    # Get system glibc version
    sys_glibc <- tryCatch({
      out <- system("ldd --version 2>&1", intern = TRUE)[1]
      m <- regmatches(out, regexpr("[0-9]+\\.[0-9]+$", out))
      if (length(m) > 0) as.numeric(m) else NA
    }, error = function(e) NA)

    # Get build glibc version from build_info.txt
    www_dir <- file.path(getwd(), "www")
    info_file <- file.path(www_dir, "build_info.txt")
    build_glibc <- tryCatch({
      if (file.exists(info_file)) {
        lines <- readLines(info_file)
        gline <- grep("^glibc=", lines, value = TRUE)
        if (length(gline) > 0) as.numeric(sub("^glibc=", "", gline[1])) else NA
      } else NA
    }, error = function(e) NA)

    if (is.na(sys_glibc) || is.na(build_glibc)) {
      return(list(compatible = TRUE, sys_ver = sys_glibc, build_ver = build_glibc,
                  message = "Could not determine glibc versions — assuming compatible."))
    }

    if (sys_glibc >= build_glibc) {
      return(list(compatible = TRUE, sys_ver = sys_glibc, build_ver = build_glibc,
                  message = paste0("glibc OK: system ", sys_glibc, " >= build ", build_glibc)))
    }

    list(compatible = FALSE, sys_ver = sys_glibc, build_ver = build_glibc,
         message = paste0("glibc MISMATCH: system has ", sys_glibc,
                          " but binary needs >= ", build_glibc,
                          ". Will recompile from source."))
  }

  # Check if Raven executable is available
  check_raven_available <- function() {
    raven_path <- find_raven_exe()
    !is.null(raven_path) && file.exists(raven_path)
  }

  # Find the Raven executable — checks bundled www/ folder first, then common locations
  find_raven_exe <- function() {
    www_dir <- file.path(getwd(), "www")

    if (is_linux()) {
      # Linux: prefer bundle (run_raven.sh), then platform-named exe
      candidates <- c(
        file.path(www_dir, "run_raven.sh"),
        file.path(www_dir, "Raven_linux.exe"),
        file.path(www_dir, "Raven.exe"),
        file.path(WORK_BASE, "run_raven.sh"),
        file.path(WORK_BASE, "Raven_linux.exe"),
        "/usr/local/bin/Raven",
        file.path(Sys.getenv("HOME"), "Raven")
      )
    } else {
      # Windows: prefer platform-named exe, then generic
      candidates <- c(
        file.path(www_dir, "Raven_windows.exe"),
        file.path(www_dir, "Raven.exe"),
        file.path(WORK_BASE, "Raven_windows.exe"),
        file.path(WORK_BASE, "Raven.exe"),
        file.path(Sys.getenv("HOME"), "Raven.exe")
      )
    }
    for (p in candidates) {
      if (file.exists(p)) return(p)
    }
    NULL
  }

  # Ensure Raven executable is available and executable
  ensure_raven_exe <- function(send_status) {
    raven_path <- find_raven_exe()
    if (!is.null(raven_path) && file.exists(raven_path)) {
      www_dir <- file.path(getwd(), "www")
      is_www <- startsWith(normalizePath(raven_path, mustWork = FALSE),
                           normalizePath(www_dir, mustWork = FALSE))

      if (is_www) {
        # Copy entire bundle to WORK_BASE
        dir.create(WORK_BASE, recursive = TRUE, showWarnings = FALSE)

        # Check if this is a Linux bundle (run_raven.sh + libs/) — only use on Linux
        www_sh   <- file.path(www_dir, "run_raven.sh")
        www_libs <- file.path(www_dir, "libs")

        if (is_linux() && file.exists(www_sh) && dir.exists(www_libs)) {
          # Linux bundle: copy run_raven.sh + Raven_linux.exe + libs/
          dest_sh  <- file.path(WORK_BASE, "run_raven.sh")
          dest_exe <- file.path(WORK_BASE, "Raven_linux.exe")
          dest_libs <- file.path(WORK_BASE, "libs")

          if (!file.exists(dest_sh) || !file.exists(dest_exe)) {
            file.copy(www_sh, dest_sh, overwrite = TRUE)
            Sys.chmod(dest_sh, mode = "0755")
            src_exe <- file.path(www_dir, "Raven_linux.exe")
            if (file.exists(src_exe)) {
              file.copy(src_exe, dest_exe, overwrite = TRUE)
              Sys.chmod(dest_exe, mode = "0755")
            }
            # Copy libs directory
            if (!dir.exists(dest_libs)) dir.create(dest_libs, recursive = TRUE)
            lib_files <- list.files(www_libs, full.names = TRUE)
            for (lf in lib_files) {
              file.copy(lf, file.path(dest_libs, basename(lf)), overwrite = TRUE)
            }
            send_status("Using bundled Linux Raven + libs from www/")
          }
          return(dest_sh)
        } else {
          # Single exe (Windows or simple Linux)
          dest <- file.path(WORK_BASE, basename(raven_path))
          if (!file.exists(dest)) {
            file.copy(raven_path, dest, overwrite = TRUE)
            Sys.chmod(dest, mode = "0755")
            send_status("Using bundled Raven executable from www/")
          }
          # Copy all Windows DLLs from libs/ (NetCDF, HDF5, lp_solve, VC runtime, etc.)
          if (!is_linux()) {
            dll_files <- list.files(file.path(www_dir, "libs"), pattern = "\\.dll$",
                                   full.names = TRUE, ignore.case = TRUE)
            for (dll in dll_files) {
              dll_dest <- file.path(WORK_BASE, basename(dll))
              if (!file.exists(dll_dest)) file.copy(dll, dll_dest)
            }
            if (length(dll_files) > 0)
              cat("[RAVEN-EXEC] Copied", length(dll_files), "Windows DLLs to", WORK_BASE, "\n")
          }
          return(dest)
        }
      }
      Sys.chmod(raven_path, mode = "0755")
      return(raven_path)
    }

    # Fallback: download the binary bundle from GitHub Release
    send_status("Downloading Raven binary bundle from GitHub Release...")
    www_dir <- file.path(getwd(), "www")
    dir.create(www_dir, recursive = TRUE, showWarnings = FALSE)
    dir.create(WORK_BASE, recursive = TRUE, showWarnings = FALSE)

    bundle_url <- "https://github.com/rarabzad/Raven_interface/releases/download/v1.0/raven-binaries.zip"
    tmp_zip <- file.path(tempdir(), "raven-binaries.zip")
    cat("[RAVEN-EXEC] Downloading bundle from:", bundle_url, "\n")

    tryCatch({
      # Use libcurl method to follow GitHub's 302 redirect
      download.file(bundle_url, tmp_zip, mode = "wb", quiet = FALSE, method = "libcurl")
      cat("[RAVEN-EXEC] Download complete, size:", file.size(tmp_zip), "bytes\n")

      if (!file.exists(tmp_zip) || file.size(tmp_zip) < 1000) {
        stop("Downloaded file is too small or missing — check the Release URL.")
      }

      send_status("Extracting Raven bundle...")
      unzip(tmp_zip, exdir = www_dir, overwrite = TRUE)
      unlink(tmp_zip)

      # Set permissions
      exe_path <- file.path(www_dir, "Raven_linux.exe")
      sh_path  <- file.path(www_dir, "run_raven.sh")
      if (file.exists(exe_path)) Sys.chmod(exe_path, mode = "0755")
      if (file.exists(sh_path))  Sys.chmod(sh_path, mode = "0755")

      send_status("Raven bundle downloaded and ready.")
      cat("[RAVEN-EXEC] Bundle extracted to", www_dir, "\n")
      cat("[RAVEN-EXEC] Files:", paste(list.files(www_dir), collapse = ", "), "\n")

      # Now find the exe again
      raven_path <- find_raven_exe()
      if (!is.null(raven_path) && file.exists(raven_path)) {
        return(raven_path)
      }
      stop("Bundle extracted but executable not found.")
    }, error = function(e) {
      # Try system curl as fallback (more reliable for redirects)
      cat("[RAVEN-EXEC] download.file failed, trying system curl...\n")
      curl_result <- tryCatch({
        system2("curl", args = c("-L", "-o", tmp_zip, bundle_url),
                stdout = TRUE, stderr = TRUE)
        if (file.exists(tmp_zip) && file.size(tmp_zip) > 1000) {
          unzip(tmp_zip, exdir = www_dir, overwrite = TRUE)
          unlink(tmp_zip)
          exe_path <- file.path(www_dir, "Raven_linux.exe")
          sh_path  <- file.path(www_dir, "run_raven.sh")
          if (file.exists(exe_path)) Sys.chmod(exe_path, mode = "0755")
          if (file.exists(sh_path))  Sys.chmod(sh_path, mode = "0755")
          cat("[RAVEN-EXEC] curl download + extract succeeded\n")
          raven_path <- find_raven_exe()
          if (!is.null(raven_path)) return(raven_path)
        }
        NULL
      }, error = function(e2) NULL)

      if (!is.null(curl_result)) return(curl_result)

      stop(paste("Could not download Raven bundle:", conditionMessage(e),
                 "\nRun setup.sh or download raven-binaries.zip manually from GitHub Releases."))
    })
  }

  # ── Create the required folder structure ─────────────────────────────────────
  create_folder_structure <- function(model_name) {
    base <- file.path(WORK_BASE, model_name)
    dirs <- c(
      file.path(base, "main"),
      file.path(base, "main", "timeseries", "forcings"),
      file.path(base, "main", "timeseries", "observations"),
      file.path(base, "output")
    )
    for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
    return(list(base = base,
                main = file.path(base, "main"),
                forcings = file.path(base, "main", "timeseries", "forcings"),
                observations = file.path(base, "main", "timeseries", "observations"),
                output = file.path(base, "output")))
  }

  # ── Receive a file from the interface (base64 encoded) ──────────────────────
  receive_file <- function(msg) {
    filename <- msg$filename
    data_b64 <- msg$data
    model_name <- msg$model_name %||% "model"
    file_category <- msg$category %||% "main"  # main, forcing, observation, nc

    if (is.null(filename) || is.null(data_b64))
      stop("Missing filename or data")

    dirs <- create_folder_structure(model_name)

    # Determine destination based on category
    dest_dir <- switch(file_category,
      "forcing"     = dirs$forcings,
      "observation" = dirs$observations,
      "nc"          = dirs$forcings,  # .nc files go to forcings
      dirs$main  # default: main rv* files
    )

    dest_path <- file.path(dest_dir, filename)

    # Decode base64 and write
    raw_bytes <- base64enc::base64decode(data_b64)
    writeBin(raw_bytes, dest_path)

    invisible(dest_path)
  }

  # ── Validate model: check that all required files are present ────────────────
  validate_model <- function(msg) {
    model_name <- msg$model_name %||% "model"
    files_info <- msg$files  # list of {name, extension, category, content_b64}
    rv_contents <- msg$rv_contents  # {rvi, rvh, rvp, rvt, rvc, rvm} raw text

    messages <- list()
    file_list <- list()
    status <- "valid"

    # Check required rv* files
    required_exts <- c("rvi", "rvh", "rvp", "rvt", "rvc")
    present_exts <- character(0)

    if (!is.null(rv_contents)) {
      for (ext in names(rv_contents)) {
        content <- rv_contents[[ext]]
        if (!is.null(content) && nzchar(as.character(content))) {
          present_exts <- c(present_exts, ext)
          file_list <- c(file_list, list(list(
            name = paste0(model_name, ".", ext),
            extension = ext,
            category = "main",
            size = nchar(as.character(content)),
            status = "ok"
          )))
        }
      }
    }

    missing <- setdiff(required_exts, present_exts)
    if (length(missing) > 0) {
      status <- "warning"
      for (m in missing) {
        messages <- c(messages, list(paste0("WARNING: Missing .", m, " file — model may not run correctly")))
      }
    }

    # Check for referenced files (RedirectToFile, FileNameNC etc.)
    referenced_files <- msg$referenced_files  # list of filenames referenced in rv* files
    if (!is.null(referenced_files) && length(referenced_files) > 0) {
      uploaded_files <- msg$uploaded_files  # list of filenames the user has uploaded
      for (ref in referenced_files) {
        ref_name <- basename(as.character(ref))
        found <- FALSE
        if (!is.null(uploaded_files)) {
          for (uf in uploaded_files) {
            if (basename(as.character(uf)) == ref_name) {
              found <- TRUE
              break
            }
          }
        }
        if (!found) {
          status <- if (status == "error") "error" else "warning"
          messages <- c(messages, list(paste0("WARNING: Referenced file '", ref_name,
                                              "' not found in uploads. Ensure it is provided.")))
        }
        file_list <- c(file_list, list(list(
          name = ref_name,
          extension = tools::file_ext(ref_name),
          category = if (grepl("\\.nc$", ref_name, ignore.case = TRUE)) "nc" else "data",
          status = if (found) "ok" else "missing"
        )))
      }
    }

    # Validate key content checks
    if ("rvi" %in% present_exts && !is.null(rv_contents$rvi)) {
      rvi_text <- as.character(rv_contents$rvi)
      if (!grepl(":StartDate", rvi_text))
        messages <- c(messages, list("WARNING: :StartDate not found in .rvi"))
      if (!grepl(":EndDate|:Duration", rvi_text))
        messages <- c(messages, list("WARNING: :EndDate or :Duration not found in .rvi"))
      if (!grepl(":HydrologicProcesses", rvi_text))
        messages <- c(messages, list("WARNING: :HydrologicProcesses block not found in .rvi"))
    }

    if (length(messages) == 0) {
      messages <- list("All validation checks passed.")
      status <- "valid"
    }

    list(status = status, messages = messages, files = file_list)
  }

  # ── Archive previous run outputs to server-side history ─────────────────────
  # Called before each new execution to preserve the previous run's outputs
  # in R session memory. The browser can request these later via list_runs /
  # get_run_outputs messages.
  archive_previous_run <- function(dirs, model_name) {
    prev_output_dir <- dirs$output
    if (!dir.exists(prev_output_dir) || length(list.files(prev_output_dir)) == 0) return(invisible(NULL))
    tryCatch({
      prev_contents <- list()
      prev_files <- list.files(prev_output_dir, full.names = TRUE, recursive = TRUE)
      for (f in prev_files) {
        fname <- basename(f)
        ext <- tolower(tools::file_ext(fname))
        if (ext %in% c("nc", "nc4", "hdf5", "bin")) next   # skip large binary files
        if (file.size(f) > 5 * 1024 * 1024) next            # skip files > 5MB
        prev_contents[[fname]] <- paste(readLines(f, warn = FALSE), collapse = "\n")
      }
      # Also grab RavenErrors.txt from main/ (Raven writes it there, not output/)
      for (ef in c(file.path(dirs$main, paste0(model_name, "_Raven_errors.txt")),
                   file.path(dirs$main, "RavenErrors.txt"))) {
        if (file.exists(ef) && file.size(ef) > 0) {
          prev_contents[["RavenErrors.txt"]] <- paste(readLines(ef, warn = FALSE), collapse = "\n")
          break
        }
      }
      if (length(prev_contents) > 0) {
        rid <- isolate(run_counter()) + 1L
        run_counter(rid)
        label <- paste0("Run ", rid, " (", format(Sys.time(), "%H:%M:%S"), ")")
        hist <- isolate(run_history())
        hist <- c(hist, list(list(
          run_id = rid, label = label, timestamp = as.numeric(Sys.time()),
          files = names(prev_contents), contents = prev_contents
        )))
        if (length(hist) > MAX_RUN_HISTORY) hist <- tail(hist, MAX_RUN_HISTORY)
        run_history(hist)
        cat("[RAVEN-HIST] Archived previous run as '", label, "' (",
            length(prev_contents), " files)\n")
        send_to_iframe(list(type = "run_archived", run_id = rid, label = label,
                            file_count = length(prev_contents)))
      }
    }, error = function(e) {
      cat("[RAVEN-HIST] Warning: could not archive previous run:", conditionMessage(e), "\n")
    })
  }

  # ── Execute the Raven model ──────────────────────────────────────────────────
  execute_raven <- function(msg, send_to_iframe) {
    model_name <- msg$model_name %||% "model"
    rv_contents <- msg$rv_contents  # {rvi, rvh, rvp, rvt, rvc, rvm} raw text
    data_files <- msg$data_files    # [{name, data_b64, category}]

    send_status <- function(txt) {
      send_to_iframe(list(type = "run_status", status = "running", message = txt))
    }
    send_error <- function(txt) {
      send_to_iframe(list(type = "run_status", status = "error", message = txt))
    }
    send_success <- function(txt) {
      send_to_iframe(list(type = "run_status", status = "success", message = txt))
    }

    # 1. Create folder structure
    send_status("Creating folder structure...")
    dirs <- create_folder_structure(model_name)

    # 1b. Archive previous run outputs before they get overwritten
    archive_previous_run(dirs, model_name)

    # 2. Write rv* files to main directory — EXACTLY as provided, no modification
    send_status("Writing model files...")
    rv_extensions <- c("rvi", "rvh", "rvp", "rvt", "rvc", "rvm", "rvl", "rve")
    for (ext in rv_extensions) {
      content <- rv_contents[[ext]]
      if (!is.null(content) && nzchar(as.character(content))) {
        fpath <- file.path(dirs$main, paste0(model_name, ".", ext))
        text <- as.character(content)
        # Convert Windows backslash paths to forward slashes on Linux
        if (is_linux()) text <- gsub("\\\\", "/", text)
        writeLines(text, fpath, useBytes = TRUE)
      }
    }

    # 3. Write data files (forcing, observation, .nc) to appropriate directories
    #    ALSO copy/symlink to main/ so Raven can find files regardless of path
    #    format in the rv* files (relative, basename-only, or with subdirs)
    if (!is.null(data_files) && length(data_files) > 0) {
      send_status(paste0("Writing ", length(data_files), " data file(s)..."))
      for (df in data_files) {
        fname <- as.character(df$name)
        category <- as.character(df$category %||% "forcing")
        data_b64 <- if (!is.null(df$data_b64)) as.character(df$data_b64) else ""
        text_content <- if (!is.null(df$text_content)) as.character(df$text_content) else NULL

        dest_dir <- switch(category,
          "forcing"     = dirs$forcings,
          "observation" = dirs$observations,
          "nc"          = dirs$forcings,
          dirs$main
        )

        dest_path <- file.path(dest_dir, fname)
        # Create subdirectories if filename contains a path
        dir.create(dirname(dest_path), recursive = TRUE, showWarnings = FALSE)

        if (nzchar(data_b64)) {
          raw_bytes <- base64enc::base64decode(data_b64)
          writeBin(raw_bytes, dest_path)
        } else if (!is.null(text_content) && nzchar(text_content)) {
          writeLines(text_content, dest_path, useBytes = TRUE)
        }

        # Also place in main/ so Raven finds it via basename or relative path references
        main_copy <- file.path(dirs$main, fname)
        dir.create(dirname(main_copy), recursive = TRUE, showWarnings = FALSE)
        if (!file.exists(main_copy) && file.exists(dest_path)) {
          tryCatch(file.symlink(dest_path, main_copy),
                   error = function(e) file.copy(dest_path, main_copy))
        }
        cat("[RAVEN-EXEC] Data file:", fname, "→", dest_path,
            "(category:", category, ", size:", file.size(dest_path), "bytes)\n")
      }
    }

    # 3b. Handle paths in .rvt content — create subdirectories for :RedirectToFile references
    rvt_content <- rv_contents[["rvt"]]
    if (!is.null(rvt_content) && nzchar(as.character(rvt_content))) {
      rvt_text <- as.character(rvt_content)

      # Convert Windows-style backslash paths to forward slashes for Linux
      rvt_text <- gsub("\\\\", "/", rvt_text)

      # Extract all :RedirectToFile paths — robust extraction without lookbehind
      redirect_matches <- character(0)
      redir_raw <- regmatches(rvt_text, gregexpr(":RedirectToFile\\s+\\S+", rvt_text, perl = TRUE))[[1]]
      cat("[RAVEN-EXEC] Raw RedirectToFile matches:", length(redir_raw), "\n")
      if (length(redir_raw) > 0) {
        redirect_matches <- sub("^:RedirectToFile\\s+", "", redir_raw, perl = TRUE)
        cat("[RAVEN-EXEC] Extracted paths:", paste(head(redirect_matches, 5), collapse=", "),
            if(length(redirect_matches)>5) paste("... +", length(redirect_matches)-5, "more") else "", "\n")
      }
      if (length(redirect_matches) > 0) {
        for (rpath in redirect_matches) {
          rdir <- dirname(rpath)
          if (rdir != "." && nzchar(rdir)) {
            dir.create(file.path(dirs$main, rdir), recursive = TRUE, showWarnings = FALSE)
            cat("[RAVEN-EXEC] Created subdirectory:", rdir, "\n")
          }
        }
        cat("[RAVEN-EXEC] Found", length(redirect_matches), "RedirectToFile references in .rvt\n")
      }

      # Extract all :FileNameNC paths — same robust approach
      nc_matches <- character(0)
      nc_raw <- regmatches(rvt_text, gregexpr(":FileNameNC\\s+\\S+", rvt_text, perl = TRUE))[[1]]
      if (length(nc_raw) > 0) {
        nc_matches <- sub("^:FileNameNC\\s+", "", nc_raw, perl = TRUE)
      }
      if (length(nc_matches) > 0) {
        for (ncpath in nc_matches) {
          ncdir <- dirname(ncpath)
          if (ncdir != "." && nzchar(ncdir)) {
            dir.create(file.path(dirs$main, ncdir), recursive = TRUE, showWarnings = FALSE)
            cat("[RAVEN-EXEC] Created subdirectory for NC:", ncdir, "\n")
          }
        }
        cat("[RAVEN-EXEC] Found", length(nc_matches), "FileNameNC references in .rvt\n")
      }
      fpath <- file.path(dirs$main, paste0(model_name, ".rvt"))
      writeLines(rvt_text, fpath, useBytes = TRUE)
      send_status("Adjusted file paths in .rvt for local execution.")

      # Match imported data files to :RedirectToFile AND :FileNameNC subdirectory paths
      all_ref_paths <- c(redirect_matches,
        if (exists("nc_matches") && length(nc_matches) > 0) nc_matches else character(0))
      cat("[RAVEN-EXEC] Total ref paths to resolve:", length(all_ref_paths), "\n")
      if (length(all_ref_paths) > 0) {
        for (rpath in all_ref_paths) {
          rbase <- basename(rpath)
          dest <- file.path(dirs$main, rpath)
          cat("[RAVEN-EXEC]   Checking:", rpath, "→ dest:", dest, "exists:", file.exists(dest), "\n")
          if (!file.exists(dest)) {
            candidates <- c(
              file.path(dirs$main, rbase),
              file.path(dirs$forcings, rbase),
              file.path(dirs$observations, rbase)
            )
            found <- FALSE
            for (cand in candidates) {
              if (file.exists(cand)) {
                dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
                file.copy(cand, dest, overwrite = TRUE)
                cat("[RAVEN-EXEC]   ✓ Copied", cand, "→", dest, "\n")
                found <- TRUE
                break
              }
            }
            if (!found) {
              cat("[RAVEN-EXEC]   ✗ NOT FOUND:", rbase, "— checked:", paste(candidates, collapse=", "), "\n")
            }
          }
        }
      }
    }

    # 4. Ensure Raven executable
    send_status("Checking Raven executable...")
    raven_exe <- tryCatch(
      ensure_raven_exe(send_status),
      error = function(e) {
        send_error(paste("Raven executable not available:", conditionMessage(e)))
        return(NULL)
      }
    )
    if (is.null(raven_exe)) return()

    # Check glibc compatibility on Linux
    if (is_linux()) {
      compat <- check_glibc_compat()
      cat("[RAVEN-EXEC] glibc check:", compat$message, "\n")
      send_to_iframe(list(type = "run_console_line", line = paste("[glibc]", compat$message)))

      if (!compat$compatible) {
        send_error(paste0("Binary incompatible: system glibc ", compat$sys_ver,
                          " < required ", compat$build_ver,
                          ". Recompile Raven using the Builder app on this system."))
        return()
      }
    }

    # Copy Raven to the main directory — handle both single exe and Linux bundle
    is_bundle <- grepl("run_raven\\.sh$", raven_exe)
    if (is_bundle) {
      # Linux bundle: symlink run_raven.sh + Raven_linux.exe + libs/ to main dir
      bundle_dir <- dirname(raven_exe)
      local_sh   <- file.path(dirs$main, "run_raven.sh")
      local_raven_exe <- file.path(dirs$main, "Raven_linux.exe")
      local_libs <- file.path(dirs$main, "libs")

      if (!file.exists(local_sh)) {
        tryCatch(file.symlink(file.path(bundle_dir, "run_raven.sh"), local_sh),
                 error = function(e) {
                   file.copy(file.path(bundle_dir, "run_raven.sh"), local_sh, overwrite = TRUE)
                 })
        Sys.chmod(local_sh, mode = "0755")
      }
      if (!file.exists(local_raven_exe) && file.exists(file.path(bundle_dir, "Raven_linux.exe"))) {
        tryCatch(file.symlink(file.path(bundle_dir, "Raven_linux.exe"), local_raven_exe),
                 error = function(e) {
                   file.copy(file.path(bundle_dir, "Raven_linux.exe"), local_raven_exe, overwrite = TRUE)
                 })
        Sys.chmod(local_raven_exe, mode = "0755")
      }
      if (!file.exists(local_libs) && dir.exists(file.path(bundle_dir, "libs"))) {
        tryCatch(file.symlink(file.path(bundle_dir, "libs"), local_libs),
                 error = function(e) {
                   dir.create(local_libs, recursive = TRUE, showWarnings = FALSE)
                   lib_files <- list.files(file.path(bundle_dir, "libs"), full.names = TRUE)
                   for (lf in lib_files) file.copy(lf, file.path(local_libs, basename(lf)), overwrite = TRUE)
                 })
      }
      local_raven <- local_sh
    } else {
      # Single executable (Windows or simple Linux)
      local_raven <- file.path(dirs$main, basename(raven_exe))
      if (!file.exists(local_raven)) {
        file.copy(raven_exe, local_raven, overwrite = TRUE)
        Sys.chmod(local_raven, mode = "0755")
      }
      # Copy all Windows DLLs to model main dir (NetCDF, HDF5, lp_solve, VC runtime)
      if (!is_linux()) {
        for (dll_dir in c(dirname(raven_exe), file.path(getwd(), "www", "libs"))) {
          if (!dir.exists(dll_dir)) next
          dll_files <- list.files(dll_dir, pattern = "\\.dll$", full.names = TRUE, ignore.case = TRUE)
          for (dll in dll_files) {
            dll_dest <- file.path(dirs$main, basename(dll))
            if (!file.exists(dll_dest)) file.copy(dll, dll_dest)
          }
        }
      }
    }

    # 5. Run Raven — cross-platform via processx
    send_status("Starting Raven model...")

    # Diagnostics: log everything to R console
    cat("\n[RAVEN-EXEC] ═══════════════════════════════════════════\n")
    cat("[RAVEN-EXEC] OS:", .Platform$OS.type, Sys.info()["sysname"], "\n")

    # Log system info to both R console and interface console
    sys_info <- tryCatch({
      glibc <- system("ldd --version 2>&1", intern = TRUE)[1]
      os_pretty <- system("cat /etc/os-release 2>&1", intern = TRUE)
      os_name <- grep("^PRETTY_NAME=", os_pretty, value = TRUE)
      os_name <- sub("^PRETTY_NAME=", "", gsub('"', '', os_name))
      list(glibc = glibc, os = os_name)
    }, error = function(e) list(glibc = "unknown", os = "unknown"))
    cat("[RAVEN-EXEC] System:", sys_info$os, "\n")
    cat("[RAVEN-EXEC] glibc:", sys_info$glibc, "\n")
    send_to_iframe(list(type = "run_console_line",
                        line = paste("[System]", sys_info$os, "|", sys_info$glibc)))
    cat("[RAVEN-EXEC] Working dir:", dirs$main, "\n")
    cat("[RAVEN-EXEC] Raven launcher:", local_raven, "\n")
    cat("[RAVEN-EXEC] Is bundle:", is_bundle, "\n")
    cat("[RAVEN-EXEC] Exe exists:", file.exists(local_raven), "\n")
    if (is_bundle) {
      cat("[RAVEN-EXEC] Raven_linux.exe exists:", file.exists(file.path(dirs$main, "Raven_linux.exe")), "\n")
      cat("[RAVEN-EXEC] libs/ exists:", dir.exists(file.path(dirs$main, "libs")), "\n")
      cat("[RAVEN-EXEC] lib count:", length(list.files(file.path(dirs$main, "libs"))), "\n")
    }
    cat("[RAVEN-EXEC] Exe size:", file.size(local_raven), "bytes\n")
    cat("[RAVEN-EXEC] Model name:", model_name, "\n")
    cat("[RAVEN-EXEC] Output dir:", dirs$output, "\n")

    # List files in main dir for debugging
    main_files <- list.files(dirs$main, recursive = FALSE)
    cat("[RAVEN-EXEC] Files in main/:", paste(main_files, collapse = ", "), "\n")

    # Ensure output directory exists
    dir.create(dirs$output, recursive = TRUE, showWarnings = FALSE)

    # Build args: Raven expects "modelname -o output_path/"
    raven_args <- c(model_name, "-o", paste0(dirs$output, "/"))

    # For Linux bundle, use bash to run the shell script
    if (is_bundle) {
      raven_cmd  <- "/bin/bash"
      raven_args <- c(local_raven, raven_args)
    } else {
      raven_cmd <- local_raven
    }
    cat("[RAVEN-EXEC] Command:", raven_cmd, paste(raven_args, collapse = " "), "\n")

    # Use processx for cross-platform background process with stdout/stderr pipes
    proc <- tryCatch({
      processx::process$new(
        command = raven_cmd,
        args = raven_args,
        wd = dirs$main,
        stdout = "|",
        stderr = "|",
        cleanup = TRUE
      )
    }, error = function(e) {
      cat("[RAVEN-EXEC] ERROR launching process:", conditionMessage(e), "\n")
      send_error(paste("Failed to start Raven:", conditionMessage(e)))
      NULL
    })

    if (is.null(proc)) return()

    cat("[RAVEN-EXEC] Process started, PID:", proc$get_pid(), "\n")
    send_status("Raven is running — streaming output...")
    send_to_iframe(list(type = "run_console_line",
                        line = paste("[PID", proc$get_pid(), "] Raven process launched in", dirs$main)))

    # ── Non-blocking polling via later::later() ─────────────────────────────
    stdout_lines <- character(0)
    stderr_lines <- character(0)
    start_time <- Sys.time()
    timeout_secs <- 600

    progress_re <- "([0-9.]+)%\\s*done"
    phase_patterns <- list(
      list(pat = "Reading input",       pct = 5,  msg = "Reading input data..."),
      list(pat = "Checking data",       pct = 8,  msg = "Checking input data..."),
      list(pat = "initializing",        pct = 10, msg = "Initializing model..."),
      list(pat = "Running model",       pct = 12, msg = "Running simulation..."),
      list(pat = "simulation complete",  pct = 95, msg = "Simulation complete."),
      list(pat = "Generating output",   pct = 96, msg = "Generating output files..."),
      list(pat = "Done",                pct = 98, msg = "Done.")
    )

    # Extract start/end dates from .rvi for date-based progress
    sim_start <- NULL
    sim_end   <- NULL
    rvi_text  <- rv_contents[["rvi"]]
    if (!is.null(rvi_text) && nzchar(rvi_text)) {
      # Match :StartDate which may have time component like "1985-10-01 00:00:00"
      sd_match <- regmatches(rvi_text, regexpr(":StartDate\\s+(\\d{4}-\\d{2}-\\d{2})", rvi_text, perl = TRUE))
      ed_match <- regmatches(rvi_text, regexpr(":EndDate\\s+(\\d{4}-\\d{2}-\\d{2})", rvi_text, perl = TRUE))
      dur_match <- regmatches(rvi_text, regexpr(":Duration\\s+([0-9.]+)", rvi_text, perl = TRUE))
      if (length(sd_match) > 0 && nzchar(sd_match)) {
        sim_start <- tryCatch(as.Date(sub("^:StartDate\\s+", "", sd_match)), error = function(e) NULL)
      }
      if (length(ed_match) > 0 && nzchar(ed_match)) {
        sim_end <- tryCatch(as.Date(sub("^:EndDate\\s+", "", ed_match)), error = function(e) NULL)
      }
      # If no EndDate but Duration exists, compute end date
      if (is.null(sim_end) && !is.null(sim_start) && length(dur_match) > 0 && nzchar(dur_match)) {
        dur_days <- suppressWarnings(as.numeric(sub("^:Duration\\s+", "", dur_match)))
        if (!is.na(dur_days) && dur_days > 0) {
          sim_end <- sim_start + dur_days
        }
      }
    }
    sim_total_days <- if (!is.null(sim_start) && !is.null(sim_end)) as.numeric(sim_end - sim_start) else 0
    last_progress_pct <- 0
    simulation_started <- FALSE
    cat("[RAVEN-EXEC] Progress tracking: start=", format(sim_start), " end=", format(sim_end),
        " total_days=", sim_total_days, "\n")

    poll_raven <- function() {
      # Read any new stdout
      new_out <- tryCatch(proc$read_output_lines(n = 100), error = function(e) character(0))
      if (length(new_out) > 0) {
        stdout_lines <<- c(stdout_lines, new_out)
        for (line in new_out) {
          cat("[RAVEN-OUT]", line, "\n")
          send_to_iframe(list(type = "run_console_line", line = line))

          m <- regmatches(line, regexpr(progress_re, line, perl = TRUE))
          if (length(m) > 0 && nzchar(m)) {
            pct_str <- sub("%.*$", "", sub("^.*?(\\d+\\.?\\d*)%.*$", "\\1", line))
            pct <- suppressWarnings(as.numeric(pct_str))
            if (!is.na(pct)) {
              bar_pct <- round(15 + pct * 0.75, 1)
              send_to_iframe(list(type = "run_progress",
                                  percent = bar_pct,
                                  message = paste0("Simulating... ", round(pct, 1), "% done")))
            }
          }

          for (pp in phase_patterns) {
            if (grepl(pp$pat, line, ignore.case = TRUE)) {
              send_to_iframe(list(type = "run_progress",
                                  percent = pp$pct, message = pp$msg))
              break
            }
          }

          # Date-based progress: parse dates from Raven's simulation output
          # Only after "Simulation Start..." line is seen
          if (grepl("Simulation Start", line, ignore.case = TRUE)) {
            simulation_started <<- TRUE
          }
          if (simulation_started && sim_total_days > 0) {
            # Match lines that are just a date (Raven outputs "YYYY-MM-DD" on its own line)
            date_match <- regmatches(line, regexpr("^\\s*(\\d{4}-\\d{2}-\\d{2})\\s*$", line, perl = TRUE))
            if (length(date_match) > 0 && nzchar(date_match)) {
              cur_date <- tryCatch(as.Date(trimws(date_match)), error = function(e) NULL)
              if (!is.null(cur_date) && cur_date >= sim_start && cur_date <= sim_end) {
                elapsed_days <- as.numeric(cur_date - sim_start)
                # Map to 15-90% range
                new_pct <- round(15 + (elapsed_days / sim_total_days) * 75, 1)
                # Only send if changed by at least 1%
                if (new_pct > last_progress_pct + 0.5) {
                  last_progress_pct <<- new_pct
                  yr <- format(cur_date, "%Y-%m-%d")
                  send_to_iframe(list(type = "run_progress",
                                      percent = new_pct,
                                      message = paste0("Simulating ", yr, "...")))
                }
              }
            }
          }
        }
      }

      # Read any new stderr
      new_err <- tryCatch(proc$read_error_lines(n = 100), error = function(e) character(0))
      if (length(new_err) > 0) {
        stderr_lines <<- c(stderr_lines, new_err)
        for (line in new_err) {
          cat("[RAVEN-ERR]", line, "\n")
          send_to_iframe(list(type = "run_console_line", line = paste("[stderr]", line)))
        }
      }

      # Check if process has finished
      if (!proc$is_alive()) {
        remaining_out <- tryCatch(proc$read_all_output_lines(), error = function(e) character(0))
        remaining_err <- tryCatch(proc$read_all_error_lines(), error = function(e) character(0))
        stdout_lines <<- c(stdout_lines, remaining_out)
        stderr_lines <<- c(stderr_lines, remaining_err)
        for (line in remaining_out) {
          send_to_iframe(list(type = "run_console_line", line = line))
          cat("[RAVEN-OUT]", line, "\n")
        }

        exit_code <- tryCatch(proc$get_exit_status(), error = function(e) -1)
        elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
        cat("[RAVEN-EXEC] Process finished, exit code:", exit_code, "after", elapsed, "sec\n")
        cat("[RAVEN-EXEC] Total stdout lines:", length(stdout_lines), "\n")
        cat("[RAVEN-EXEC] Total stderr lines:", length(stderr_lines), "\n")
        send_to_iframe(list(type = "run_console_line",
                            line = paste("--- Raven finished (exit", exit_code, ") in", elapsed, "seconds ---")))

        finish_raven_run_px(dirs, model_name, exit_code,
                            paste(stdout_lines, collapse = "\n"),
                            paste(stderr_lines, collapse = "\n"),
                            send_to_iframe, send_status, send_error)
        return()
      }

      # Check timeout
      elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      if (elapsed > timeout_secs) {
        cat("[RAVEN-EXEC] TIMEOUT after", timeout_secs, "seconds\n")
        tryCatch(proc$kill(), error = function(e) NULL)
        send_error(paste0("Raven timed out after ", timeout_secs, " seconds"))
        return()
      }

      later::later(poll_raven, 0.3)
    }

    later::later(poll_raven, 0.5)
  }

  # ── Completion handler ──────────────────────────────────────────────────────
  finish_raven_run_px <- function(dirs, model_name, exit_code, all_stdout, all_stderr,
                                   send_to_iframe, send_status, send_error) {
    console_output <- all_stdout
    if (nzchar(all_stderr))
      console_output <- paste0(console_output, "\n\n--- STDERR ---\n", all_stderr)

    if (exit_code != 0) {
      send_status(paste0("Model finished with exit code ", exit_code, ". Reading outputs..."))
    } else {
      send_status("Model completed successfully. Reading outputs...")
    }

    output_files <- list_output_files(model_name)
    cat("[RAVEN-EXEC] Output files found:", length(output_files), "\n")
    for (of in output_files) cat("[RAVEN-EXEC]   -", of$name, "\n")

    output_contents <- list()
    for (of in output_files) {
      fname <- as.character(of$name)
      tryCatch({
        content <- read_output_file(model_name, fname)
        output_contents[[fname]] <- content$text
      }, error = function(e) {
        output_contents[[fname]] <<- paste("Error reading:", conditionMessage(e))
      })
    }

    # Include RavenErrors.txt from working directory (Raven writes it to main/, not output/)
    for (ef in c(file.path(dirs$main, paste0(model_name, "_Raven_errors.txt")),
                 file.path(dirs$main, "RavenErrors.txt"))) {
      if (file.exists(ef) && file.size(ef) > 0) {
        output_contents[["RavenErrors.txt"]] <- paste(readLines(ef, warn = FALSE), collapse = "\n")
        cat("[RAVEN-EXEC] Included RavenErrors.txt (", file.size(ef), "bytes)\n")
        break
      }
    }

    # Include generated .rvp template from CreateRVPTemplate (Raven writes to main/, not output/)
    rvp_candidates <- list.files(dirs$main, pattern = "\\.rvp$", full.names = TRUE)
    for (rf in rvp_candidates) {
      rf_name <- basename(rf)
      # Skip the input .rvp file we wrote (model_name.rvp) — only include generated templates
      if (rf_name == paste0(model_name, ".rvp")) next
      if (file.exists(rf) && file.size(rf) > 0) {
        output_contents[[rf_name]] <- paste(readLines(rf, warn = FALSE), collapse = "\n")
        cat("[RAVEN-EXEC] Included generated .rvp template:", rf_name, "(", file.size(rf), "bytes)\n")
      }
    }

    send_to_iframe(list(
      type = "run_result",
      status = if (exit_code == 0) "success" else "warning",
      message = if (exit_code == 0) "Raven model executed successfully."
                else paste("Raven finished with exit code:", exit_code),
      console = console_output,
      output_files = output_files,
      output_contents = output_contents,
      run_history_count = length(isolate(run_history()))
    ))
    cat("[RAVEN-EXEC] Results sent to client. Done.\n")
    cat("[RAVEN-EXEC] ═══════════════════════════════════════════\n\n")
  }

  # ── List files in the output directory ───────────────────────────────────────
  list_output_files <- function(model_name) {
    output_dir <- file.path(WORK_BASE, model_name, "output")
    if (!dir.exists(output_dir)) return(list())

    files <- list.files(output_dir, recursive = TRUE, full.names = TRUE)
    lapply(files, function(f) {
      list(
        name = basename(f),
        path = f,
        size = file.size(f),
        extension = tools::file_ext(f),
        modified = format(file.mtime(f), "%Y-%m-%d %H:%M:%S")
      )
    })
  }

  # ── Read a specific output file ──────────────────────────────────────────────
  read_output_file <- function(model_name, filename) {
    fpath <- file.path(WORK_BASE, model_name, "output", filename)
    if (!file.exists(fpath))
      stop(paste("File not found:", filename))

    ext <- tolower(tools::file_ext(filename))
    is_binary <- ext %in% c("nc", "nc4", "hdf5", "bin", "dat")

    if (is_binary) {
      # Return base64 for binary files
      raw_data <- readBin(fpath, "raw", file.size(fpath))
      return(list(
        text = base64enc::base64encode(raw_data),
        is_binary = TRUE
      ))
    }

    # Read text files — limit to 5MB to avoid memory issues
    fsize <- file.size(fpath)
    if (fsize > 5 * 1024 * 1024) {
      # Read first 5MB only
      con <- file(fpath, "r")
      on.exit(close(con))
      text <- readChar(con, 5 * 1024 * 1024)
      text <- paste0(text, "\n\n[... file truncated at 5MB ...]")
    } else {
      text <- paste(readLines(fpath, warn = FALSE), collapse = "\n")
    }

    list(text = text, is_binary = FALSE)
  }
}
