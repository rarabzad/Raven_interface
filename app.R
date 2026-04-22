# ═══════════════════════════════════════════════════════════════════════════════
# Raven Model Interface — Shiny App
# Hosts the Raven HTML editor in an iframe with bidirectional communication
# for model validation, execution, and output browsing.
# ═══════════════════════════════════════════════════════════════════════════════

library(shiny)
library(jsonlite)

# ═══════════════════════════════════════════════════════════════════════════════
# UI
# ═══════════════════════════════════════════════════════════════════════════════
ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      html, body { margin:0; padding:0; height:100%; overflow:hidden; background:#0d1117; }
      #builder-frame { position:fixed; inset:0; width:100%; height:100%; border:none; }
      .shiny-output-error { display:none !important; }
      #raven-disconnected-overlay {
        display:none; position:fixed; inset:0; z-index:99999;
        background:rgba(0,0,0,0.85); color:#fff;
        flex-direction:column; align-items:center; justify-content:center;
        font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
      }
      #raven-disconnected-overlay.show { display:flex; }
      #raven-disconnected-overlay h2 { margin:0 0 8px; font-size:18px; font-weight:600; }
      #raven-disconnected-overlay p { margin:0 0 18px; font-size:13px; opacity:0.7; }
      #raven-disconnected-overlay button {
        padding:10px 28px; font-size:13px; font-weight:600;
        background:#58a6ff; color:#fff; border:none; border-radius:6px; cursor:pointer;
      }
      #raven-disconnected-overlay button:hover { background:#79b8ff; }
    ")),
    tags$script(HTML("
      window.addEventListener('message', function(e) {
        if (!e.data || e.data.source !== 'raven_interface') return;
        Shiny.setInputValue('iframe_msg',
          { raw: JSON.stringify(e.data.payload), ts: Date.now() },
          { priority: 'event' });
      });
      Shiny.addCustomMessageHandler('to_interface', function(msg) {
        var frame = document.getElementById('builder-frame');
        if (frame && frame.contentWindow)
          frame.contentWindow.postMessage(msg, '*');
      });
      $(document).on('shiny:disconnected', function() {
        document.getElementById('raven-disconnected-overlay').classList.add('show');
      });
      window.addEventListener('beforeunload', function() {
        Shiny.setInputValue('window_closing', true, {priority: 'event'});
      });
    "))
  ),
  tags$div(id = "raven-disconnected-overlay",
    tags$h2("Session Disconnected"),
    tags$p("The Shiny server has stopped. Click below to restart."),
    tags$button(onclick = "location.reload();", "Reload App")
  ),
  tags$iframe(id = "builder-frame", src = "builder.html")
)

# ═══════════════════════════════════════════════════════════════════════════════
# SERVER — sourced from server.R (single source of truth, no duplication)
# ═══════════════════════════════════════════════════════════════════════════════
source("server.R", local = TRUE)

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════
shinyApp(
  ui = ui,
  server = server,
  options = list(launch.browser = TRUE),
  onStart = function() {
    onStop(function() {
      cat("[RAVEN] App stopped.\n")
    })
  }
)
