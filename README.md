# Raven Model Interface — Shiny Deployment

A web-based Raven hydrological model editor and executor, hosted as a Shiny app.
Works on both **Windows** (local RStudio) and **Linux** (Posit Cloud).

## Repository Structure

```
raven-shiny/          ← this repo (code only, <1 MB)
├── app.R             # Shiny app entry point (sources server.R)
├── ui.R              # Shiny UI (split-file alternative)
├── server.R          # Shiny server — all execution logic
├── setup.sh          # One-time setup: installs R packages + downloads Raven
├── .gitignore        # Excludes binaries (downloaded by setup.sh)
├── README.md         # This file
└── www/
    └── builder.html  # Full Raven Model Editor interface
```

After running `setup.sh`, the `www/` folder will also contain:

```
www/                  ← downloaded by setup.sh from GitHub Release
├── Raven_linux.exe   # Linux Raven v4.1
├── Raven_windows.exe # Windows Raven v4.1
├── run_raven.sh      # Linux launcher (sets LD_LIBRARY_PATH)
├── README.txt        # Bundle docs
└── libs/             # 55 shared libraries (39 Linux .so + 16 Windows .dll)
```

## Quick Start — Posit Cloud

1. Clone or upload this repo to a Posit Cloud project
2. Open the terminal and run:
   ```bash
   chmod +x setup.sh && ./setup.sh
   ```
   This installs R packages and downloads the Raven executables automatically.
3. Click **Run App** in RStudio

## Quick Start — Local Windows

1. Clone this repo
2. Download `raven-binaries.zip` from the [Releases page](../../releases) and extract into `www/`
3. Open `app.R` in RStudio, install packages if prompted, click **Run App**

## Creating a GitHub Release (one-time setup)

The Raven executables and libraries (~38 MB zipped) are too large for the Git repo,
so they're hosted as a GitHub Release attachment:

1. Push the code to GitHub (binaries are excluded by `.gitignore`)
2. Go to your repo → **Releases** → **Create a new release**
3. Tag: `v1.0`, Title: `Raven v4.1 Binaries`
4. Drag and drop `raven-binaries.zip` into the attachment area
5. Click **Publish release**
6. Update the `BUNDLE_URL` in `setup.sh` if your repo name differs from the default

## Features

### Model Editing
- Full rv* file editor: .rvi, .rvh, .rvp, .rvt, .rvc, .rvm, .rve
- Drag-and-drop import with automatic parsing
- Interactive Leaflet map with subbasin polygons, HRU scatter, gauge stations
- Land use legend with dominant-LU coloring
- Multiple NetCDF layer support
- 103-check model validator
- Spatial subsetting tool
- Export as ZIP

### Model Execution
- Green **▶ Execute Model** button (enabled after validation)
- Real-time console output streaming
- Date-based progress bar (handles both `:EndDate` and `:Duration`)
- Auto-detects OS: Windows uses `Raven_windows.exe`, Linux uses `run_raven.sh` bundle
- Output auto-import into viewer
- 10-minute timeout

### Output Visualization
- **Hydrographs**: time series, FDC, scatter, calendar heatmap, climatology, residuals
- **Diagnostics**: metric-colored map, sortable table
- **WatershedStorage**: multi-column variable picker, deaccumulate toggle
- **Bias adjustment** (μ=): shifts simulated to match observed mean for pattern comparison
- Output file switcher dropdown on the map

## Requirements

- R ≥ 4.0
- R packages: `shiny`, `jsonlite`, `base64enc`, `processx`, `later`
- Raven executables downloaded via `setup.sh` (no manual install needed)

## Raven Executable

| | Windows | Linux |
|--|---------|-------|
| Executable | `Raven_windows.exe` | `Raven_linux.exe` |
| Dependencies | `libs/*.dll` (16 files) | `libs/*.so` (39 files) |
| Launcher | direct | `run_raven.sh` (sets LD_LIBRARY_PATH) |
| Build | — | Ubuntu 24.04, g++ 13.3, glibc 2.39 |

Both are Raven v4.1 with NetCDF and lp_solve support.
