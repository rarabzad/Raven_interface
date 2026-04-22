#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Raven Model Interface — Posit Cloud Setup Script
# ═══════════════════════════════════════════════════════════════════════════════
# Run this once to install R packages and download Raven executables + libraries.
# Usage:  chmod +x setup.sh && ./setup.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  EDIT THIS: set to your GitHub Release URL for raven-binaries.zip          │
# │  Example: https://github.com/youruser/yourrepo/releases/download/v1.0/... │
# └─────────────────────────────────────────────────────────────────────────────┘
BUNDLE_URL="https://github.com/rarabzad/Raven_interface/releases/download/v1.0/raven-binaries.zip"

echo "══════════════════════════════════════════════════════════════"
echo " Raven Model Interface — Setup"
echo "══════════════════════════════════════════════════════════════"

# 1. Install R packages
echo "[1/3] Installing R packages..."
Rscript -e '
  pkgs <- c("shiny", "jsonlite", "base64enc", "processx", "later")
  for (p in pkgs) {
    if (!requireNamespace(p, quietly = TRUE)) {
      cat("  Installing", p, "...\n")
      install.packages(p, repos = "https://cran.r-project.org", quiet = TRUE)
    } else {
      cat("  ✓", p, "already installed\n")
    }
  }
  cat("[OK] All R packages ready.\n")
'

# 2. Download Raven binaries if not already present
echo ""
echo "[2/3] Checking Raven executables..."

if [ -f "$APP_DIR/www/Raven_linux.exe" ] && [ -d "$APP_DIR/www/libs" ]; then
  echo "  ✓ Raven executables already present — skipping download."
else
  echo "  Downloading Raven binary bundle..."
  echo "  URL: $BUNDLE_URL"

  TMPZIP=$(mktemp /tmp/raven-binaries-XXXX.zip)

  if command -v curl &> /dev/null; then
    curl -L -o "$TMPZIP" "$BUNDLE_URL"
  elif command -v wget &> /dev/null; then
    wget -q -O "$TMPZIP" "$BUNDLE_URL"
  else
    echo "  ✗ Neither curl nor wget found. Please install one and re-run."
    exit 1
  fi

  if [ ! -s "$TMPZIP" ]; then
    echo "  ✗ Download failed or file is empty."
    echo "  Please download raven-binaries.zip manually from your GitHub Release"
    echo "  and extract it into $APP_DIR/www/"
    rm -f "$TMPZIP"
    exit 1
  fi

  echo "  Extracting to www/..."
  unzip -o "$TMPZIP" -d "$APP_DIR/www/"
  rm -f "$TMPZIP"

  echo "  ✓ Raven binaries extracted."
fi

# Set permissions
chmod +x "$APP_DIR/www/Raven_linux.exe" 2>/dev/null || true
chmod +x "$APP_DIR/www/run_raven.sh" 2>/dev/null || true

# 3. Verify
echo ""
echo "[3/3] Verifying setup..."
ERRORS=0

for f in "app.R" "server.R" "www/builder.html"; do
  if [ -f "$APP_DIR/$f" ]; then
    echo "  ✓ $f"
  else
    echo "  ✗ $f MISSING"
    ERRORS=$((ERRORS+1))
  fi
done

if [ -f "$APP_DIR/www/Raven_linux.exe" ]; then
  echo "  ✓ Raven_linux.exe ($(du -h "$APP_DIR/www/Raven_linux.exe" | cut -f1))"
else
  echo "  ✗ Raven_linux.exe MISSING"
  ERRORS=$((ERRORS+1))
fi

if [ -f "$APP_DIR/www/Raven_windows.exe" ]; then
  echo "  ✓ Raven_windows.exe ($(du -h "$APP_DIR/www/Raven_windows.exe" | cut -f1))"
fi

if [ -d "$APP_DIR/www/libs" ]; then
  LIB_COUNT=$(ls "$APP_DIR/www/libs/" | wc -l)
  echo "  ✓ libs/ ($LIB_COUNT files)"
else
  echo "  ✗ libs/ MISSING"
  ERRORS=$((ERRORS+1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
  echo "══════════════════════════════════════════════════════════════"
  echo " ✓ Setup complete!"
  echo ""
  echo " To run: click 'Run App' in RStudio"
  echo "   or:   Rscript -e \"shiny::runApp('$APP_DIR', port=3838)\""
  echo "══════════════════════════════════════════════════════════════"
else
  echo " ⚠ Setup completed with $ERRORS issue(s). Check above."
fi
