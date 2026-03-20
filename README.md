# Raven_interface
[Open Raven interface Live](https://rarabzad.github.io/Raven_interface/)

# ⬡ Raven Model Editor
 
A browser-based graphical interface for building, editing, inspecting, and visualizing [Raven](https://raven.uwaterloo.ca) hydrological model input files. Everything runs locally in your browser — no server, no installation, no dependencies.
 
> **Developed by [Rezgar Arabzadeh](https://github.com/rarabzad)**
> Department of Civil and Environmental Engineering, University of Waterloo
 
---
 
## Overview
 
Raven Model Editor provides a complete GUI workflow for the [Raven Hydrological Modelling Framework](https://raven.uwaterloo.ca) — from constructing a new model from scratch, to importing existing configurations, editing parameters, visualizing spatial data on interactive maps, analyzing model outputs, and exporting ready-to-run file sets.
 
The editor is a **single self-contained HTML file** (~15,000 lines) with zero external dependencies beyond Leaflet (maps) and JSZip (export), both loaded from CDN. All parsing, editing, validation, and visualization logic runs entirely client-side.
 
---
 
## Key Capabilities
 
### 📁 Full File Suite Editor
 
Edit all six Raven input file types through structured, form-based panels:
 
| File | Contents | Editor Features |
|------|----------|-----------------|
| `.rvi` | Simulation options | Processes chain builder, method selectors, hydrologic process drag-and-drop ordering, state variable dependency graph, custom output config, evaluation metrics/periods, alias editor |
| `.rvh` | Basin & HRU definitions | SubBasin table, HRU table with filtering, HRU Groups, SB Groups, SB Properties, Reservoir config, Network DAG visualization, Hypsometry/Aspect/Slope distribution charts |
| `.rvp` | Model parameters | Soil/Vegetation/LandUse class editors, soil profile builder with visual cross-section, channel profile editor with survey point visualization, global parameter table, parameter distribution dot-charts |
| `.rvt` | Forcing data & gauges | Gauge station manager, observation data linker, gridded/station forcing config, per-gauge meteorological time series viewer with 6 chart types |
| `.rvc` | Initial conditions | Basin initial flows, reservoir stages, uniform ICs, HRU state variable table, basin state variables, nudge editor |
| `.rvm` | Water management | Demands, decision variables, workflow variables, lookup tables, management goals/constraints with operating regimes, named constants |
 
### 🗺 Interactive Map Visualization
 
- **HRU Scatter** — colored dots per HRU, sized by area, colored by land-use class with auto-detected palette
- **Gauge Stations** — diamond markers with popup details; click to open meteorological time series panel
- **Subbasin Polygons** — import GeoJSON with field mapper for SubId/DowSubId; click to open hydrograph panel
- **River Network** — import river GeoJSON overlay
- **HRU Polygons** — import HRU GeoJSON colored by land-use
- **Performance Choropleth** — recolor polygons by NSE score (requires output CSV)
- **Demand Markers** — water demand locations sized by penalty/priority
- **Layer Style Panel** — adjust opacity, radius, border width, colors for each layer type
- **Basin Connectivity Inspector** — click a subbasin to highlight its full upstream (teal) and downstream (amber) network with drainage statistics
 
Map backgrounds include satellite imagery, topographic, terrain, OpenStreetMap, and Voyager tile sets — each with a matching UI color theme.
 
### 📈 Model Output Analysis
 
Import Raven output CSVs (Hydrograph or Custom Output format) and explore results with **10 interactive chart types**:
 
| Chart | Description |
|-------|-------------|
| **Time Series** | Sim vs Obs hydrograph with precipitation bars; scroll-zoom, drag-pan, crosshair tooltip |
| **Flow Duration Curve** | Log-scale FDC with Q5/Q50/Q95 reference lines |
| **FDC Bias** | Simulated minus observed FDC — highlights flow regime biases |
| **Annual Climatology** | Median/mean daily flow by day-of-year or monthly; optional percentile envelope |
| **Sim vs Obs Scatter** | With 1:1 line, OLS regression, NSE/PBIAS/R² annotations |
| **Calendar Heatmap** | Daily residuals as colored grid by year × day |
| **Diagnostics** | Sortable scorecard (NSE, KGE, RMSE, PBIAS per basin) from imported Diagnostics.csv |
| **Cumulative Departure** | Double-mass curve for detecting regime shifts |
| **Residuals** | Time series or climatological residuals with optional distribution panel |
| **Water Balance** | Annual sim vs obs bar chart with cumulative difference line |
 
All charts support multi-basin comparison, series mute/unmute via legend chips, and PNG export.
 
### 📡 Meteorological Time Series Viewer
 
Load gauge forcing files (`:MultiData` format) and explore with **6 specialized views**:
 
- **Time Series** — multi-parameter overlay with independent Y-axes
- **Monthly Climatology** — box-and-whisker by month per variable
- **P–T Distribution** — 2D hex-bin density of precipitation vs temperature
- **Calendar Heatmap** — daily values as color grid
- **Correlation Matrix** — inter-parameter Pearson correlation heatmap
- **Data Completeness** — missing data pattern visualization
 
### ▶ Spatial Animation Player
 
For Custom Output CSVs (e.g., snow depth, soil moisture across subbasins), the spatial player animates values over time on the map using a color-scale choropleth with playback controls and speed adjustment.
 
### ✓ Model Validation
 
One-click comprehensive validation covering:
 
- Missing required fields (StartDate, EndDate, TimeStep, SoilModel)
- Basin topology checks (orphan basins, missing outlets, duplicate IDs, circular references)
- HRU–SubBasin linkage verification
- Soil profile layer count vs SoilModel declaration
- Channel profile existence checks
- Process chain completeness (Precipitation, Baseflow, etc.)
- Gauge coordinate validation
- Observation ID matching
- Initial condition consistency (HRU table vs model HRUs)
- RVM management checks (demand SubBasin references, decision variable bounds, goal/constraint expression references)
- Evaluation period date range vs simulation period
 
Results are shown with error/warning/info classification and one-click "Fix" buttons where applicable.
 
### ⚙ Calibration Template Generator
 
Generate ready-to-use calibration configuration files for:
 
- **Ostrich** — parameter bounds, algorithm selection, objective function
- **SPOTPY** — Python-based calibration framework templates
- **DDS** (Dynamically Dimensioned Search) — parameter perturbation config
 
Auto-detects calibratable parameters from loaded `.rvp` with min/max/initial value editors.
 
---
 
## Themes
 
13 built-in color themes across three categories:
 
**Dark UI** — Ocean Dark (default), Midnight, Solarized, Dracula, Forest, High Contrast
**Map-Focused** — Satellite, Topographic, Terrain Light, OSM Standard, Voyager
**Light UI** — Slate, Paper
 
Each theme includes matched map tiles, consistent UI variables, and proper canvas chart colors for both light and dark backgrounds.
 
---
 
## Keyboard Shortcuts
 
| Shortcut | Action |
|----------|--------|
| `1` – `6` | Jump to .rvi / .rvh / .rvp / .rvt / .rvc / .rvm panel |
| `V` | Validate model |
| `P` | Preview current file |
| `[` / `]` | Toggle sidebar / right panel |
| `Ctrl+S` | Export ZIP |
| `Ctrl+O` | Open file import dialog |
| `Escape` | Close any open modal |
| Scroll over chart | Zoom time axis (centered on cursor) |
| Drag chart | Pan time axis |
| Click legend chip | Mute/unmute series |
| Click subbasin polygon | Add/remove from hydrograph panel |
 
---
 
## Getting Started
 
### Quick Start
 
1. **Open** `Raven_interface.html` in any modern browser (Chrome, Firefox, Edge, Safari)
2. Click **✦ New Model** to build from scratch — *or* — **📂 Import** / drag-and-drop your existing `.rv*` files
3. Edit parameters, processes, and basin definitions in the right-hand panel
4. Import GeoJSON files to visualize your watershed on the map
5. Import Raven output CSV to analyze hydrographs and diagnostics
6. Click **⬇ Export ZIP** to download all files ready to run
 
### File Import
 
Drag and drop any combination of `.rvi`, `.rvh`, `.rvp`, `.rvt`, `.rvc`, `.rvm` files onto the page. File type is auto-detected from content — the extension is only used as a fallback hint. Files containing `:MultiData` blocks are automatically recognized as gauge forcing data and matched to gauge stations by filename.
 
### Spatial Data
 
- **Subbasin polygons** → Import GeoJSON via sidebar or map toolbar; a field mapper dialog lets you select which property holds the SubId
- **River network** → Import as GeoJSON; rendered as styled polylines
- **HRU polygons** → Import as GeoJSON; colored by land-use class
 
### Auto-Save
 
Changes are automatically drafted to browser localStorage every 5 seconds. If you accidentally close the tab, use **↩ Restore Draft** in the sidebar Tools section to recover your work.
 
---
 
## Architecture
 
```
┌─────────────────────────────────────────────────────────────────┐
│                    Single HTML File (~15k lines)                 │
├─────────────────────────────────────────────────────────────────┤
│  CSS (~900 lines)        │  HTML Structure (~500 lines)         │
│  • 13 theme definitions  │  • Topbar, Sidebar, Map, Panel       │
│  • Component styles      │  • Hydro panel + 10 chart canvases   │
│  • Light/dark overrides  │  • Met panel + 6 chart views         │
│  • Responsive layout     │  • Modals (validation, help, cal)    │
├─────────────────────────────────────────────────────────────────┤
│  JavaScript (~14k lines)                                        │
│  ├─ Parser Engine     — tokenizer, block reader, type detector  │
│  ├─ File Parsers      — parseRVI/RVH/RVP/RVT/RVC/RVM           │
│  ├─ File Writers      — writeRVI/RVH/RVP/RVT/RVC/RVM           │
│  ├─ Map Engine        — Leaflet integration, 6 layer types      │
│  ├─ Chart Engine      — Canvas-based, 10 hydro + 6 met charts  │
│  ├─ Panel Renderers   — Form builders per file type             │
│  ├─ Validation        — 30+ check categories                   │
│  ├─ Theme System      — 13 themes, dynamic tile swap            │
│  ├─ Spatial Player    — Choropleth animation engine             │
│  └─ UX Layer          — Shortcuts, auto-save, dirty tracking    │
├─────────────────────────────────────────────────────────────────┤
│  External (CDN)                                                 │
│  • Leaflet 1.9.4  — interactive maps                            │
│  • JSZip 3.10.1   — ZIP export                                  │
│  • IBM Plex Mono/Sans — typography                              │
└─────────────────────────────────────────────────────────────────┘
```
 
---
 
## Browser Compatibility
 
| Browser | Support |
|---------|---------|
| Chrome / Edge | ✅ Full support |
| Firefox | ✅ Full support |
| Safari | ✅ Full support |
| Mobile browsers | ⚠️ Functional but optimized for desktop |
 
Requires JavaScript enabled. No server or backend needed.
 
---
 
## Citing Raven
 
If you use this tool in your research, please cite the Raven framework:
 
> Craig, J.R., et al. (2020). Flexible watershed simulation with the Raven hydrological modelling framework. *Environmental Modelling & Software*, 129, 104728.
 
---
 
## License & Contact
 
**Developer:** Rezgar Arabzadeh — [rarabzad@uwaterloo.ca](mailto:rarabzad@uwaterloo.ca)
**GitHub:** [github.com/rarabzad](https://github.com/rarabzad)
**Raven:** [raven.uwaterloo.ca](https://raven.uwaterloo.ca)
