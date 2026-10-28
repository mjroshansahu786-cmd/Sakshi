#!/bin/zsh
# =============================================================================
# SAKSHI build & install script
#
#   ./scripts/build_app.sh                  # build + install to /Applications
#   ./scripts/build_app.sh --no-restart     # build + install, don't restart
#   ./scripts/build_app.sh --bundle-backend # also copy the Python venv (~1.3 GB)
#                                           # into the .app so it is portable
#
# The script:
#   1. Builds the Swift app in release mode
#   2. Assembles /Applications/SAKSHI.app (binary, Info.plist, menu-bar icon,
#      optionally the bundled backend)
#   3. Ad-hoc codesigns it
#   4. Refreshes the LaunchAgent (adds app logging + crash restart)
#   5. Restarts SAKSHI via launchctl
#
# NOTE: ad-hoc signing means macOS may ask to re-grant Screen Recording and
#       Accessibility permissions after reinstalling. The app detects this and
#       shows a warning in the menu bar / companion orb.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
APP_SRC="$ROOT/SAKSHI-App"
APP_NAME="SAKSHI"
BUNDLE_ID="com.roshan.sakshi"
INSTALL_DIR="/Applications/${APP_NAME}.app"

BUNDLE_BACKEND=false
RESTART=true
for arg in "$@"; do
  case "$arg" in
    --bundle-backend) BUNDLE_BACKEND=true ;;
    --no-restart) RESTART=false ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

echo "==> Building ${APP_NAME}-App (release)"
cd "$APP_SRC"
swift build -c release
BIN="$APP_SRC/.build/release/${APP_NAME}-App"
[[ -x "$BIN" ]] || { echo "Build failed: binary not found"; exit 1; }

echo "==> Assembling app bundle"
STAGE="$ROOT/.stage/${APP_NAME}.app"
rm -rf "$ROOT/.stage"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

cp "$BIN" "$STAGE/Contents/MacOS/${APP_NAME}"
cp "$APP_SRC/Resources/MenuBarIconTemplate.png" "$STAGE/Contents/Resources/"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>SAKSHI</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>SAKSHI needs screen recording permissions to capture your visual memory timeline.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>SAKSHI reads the frontmost window title to label your activity.</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST

if [[ "$BUNDLE_BACKEND" == true ]]; then
  echo "==> Bundling Python backend into app resources (may take a minute)"
  rsync -a --delete \
    --exclude '__pycache__' --exclude '.DS_Store' --exclude 'uv.lock' \
    "$ROOT/mnemos-backend/" "$STAGE/Contents/Resources/mnemos-backend/"
fi

echo "==> Code signing (ad-hoc)"
codesign --force --sign - "$STAGE"

echo "==> Stopping running SAKSHI"
launchctl bootout "gui/$(id -u)/${BUNDLE_ID}" 2>/dev/null || true
pkill -f "SAKSHI.app/Contents/MacOS/SAKSHI" 2>/dev/null || true
sleep 1

echo "==> Installing to $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mv "$STAGE" "$INSTALL_DIR"
rm -rf "$ROOT/.stage"

if [[ "$RESTART" == true ]]; then
  echo "==> Refreshing LaunchAgent"
  LOGS_DIR="$HOME/.mnemos/logs"
  mkdir -p "$LOGS_DIR"
  touch "$LOGS_DIR/app.log"

  cat > "$HOME/Library/LaunchAgents/${BUNDLE_ID}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${BUNDLE_ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/Contents/MacOS/${APP_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOGS_DIR}/app.log</string>
    <key>StandardErrorPath</key>
    <string>${LOGS_DIR}/app.log</string>
</dict>
</plist>
PLIST

  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/${BUNDLE_ID}.plist"
  sleep 3
  if pgrep -f "SAKSHI.app/Contents/MacOS/SAKSHI" > /dev/null; then
    echo "==> SAKSHI is running ✓"
  else
    echo "!! SAKSHI did not start — check $LOGS_DIR/app.log"
    exit 1
  fi

  echo ""
  echo "If macOS asks for Screen Recording / Accessibility permission:"
  echo "  System Settings → Privacy & Security → Screen Recording  → enable SAKSHI"
  echo "  System Settings → Privacy & Security → Accessibility     → enable SAKSHI"
  echo "Then use the menu-bar icon → Resume Recording."
fi

echo "==> Done"
