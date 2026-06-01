#!/bin/bash
set -e

# Support for architecture selection
ARCH_TYPE=${1:-"amd64"} # default to amd64, options: amd64, arm64
VERSION="1.0.0"

WORKSPACE="build_workspace"
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"

FIREFOX_DIR="$WORKSPACE/firefox"
DIST_DIR="$FIREFOX_DIR/distribution"
EXT_DIR="$DIST_DIR/extensions"
ROOT_DIR=$(pwd)

# Determine download URLs based on architecture
if [ "$ARCH_TYPE" == "amd64" ]; then
    FF_URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US"
    DEB_ARCH="amd64"
    RPM_ARCH="x86_64"
    APPIMAGE_ARCH="x86_64"
    APPIMAGE_TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
elif [ "$ARCH_TYPE" == "arm64" ]; then
    # Note: Mozilla doesn't provide a direct "latest-ssl" redirect for Linux ARM64 in the same way.
    # We use the specific version or a known working URL structure.
    # For CI/Automated builds, we'll try to fetch the latest stable.
    FF_URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64-aarch64&lang=en-US"
    DEB_ARCH="arm64"
    RPM_ARCH="aarch64"
    APPIMAGE_ARCH="aarch64"
    APPIMAGE_TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-aarch64.AppImage"
else
    echo "Unsupported architecture: $ARCH_TYPE"
    exit 1
fi

echo "Downloading fresh Firefox ($ARCH_TYPE) and Extensions..."
wget -L -O "$WORKSPACE/firefox.tar.xz" "$FF_URL"
tar xf "$WORKSPACE/firefox.tar.xz" -C "$WORKSPACE"

# Rename extracted folder if it's not named 'firefox'
mv $WORKSPACE/firefox* $WORKSPACE/firefox 2>/dev/null || true

wget -O "$WORKSPACE/ublock_origin.xpi" "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
wget -O "$WORKSPACE/adaptive_tab_bar_colour.xpi" "https://addons.mozilla.org/firefox/downloads/file/4704834/adaptive_tab_bar_colour-3.3.2.xpi"

if [ ! -f "seafari.png" ]; then
    echo "ERROR: seafari.png not found in root directory!"
    exit 1
fi

echo "Configuring Distribution and Policies..."
mkdir -p "$EXT_DIR"
cp "$WORKSPACE/ublock_origin.xpi" "$EXT_DIR/uBlock0@raymondhill.net.xpi"
cp "$WORKSPACE/adaptive_tab_bar_colour.xpi" "$EXT_DIR/ATBC@EasonWong.xpi"

cat <<EOF > "$DIST_DIR/policies.json"
{
  "policies": {
    "AppUpdateURL": "https://apt.inled.es",
    "DisableAppUpdate": true,
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "file://$EXT_DIR/uBlock0@raymondhill.net.xpi"
      },
      "ATBC@EasonWong": {
        "installation_mode": "force_installed",
        "install_url": "file://$EXT_DIR/ATBC@EasonWong.xpi"
      }
    },
    "Preferences": {
      "toolkit.legacyUserProfileCustomizations.stylesheets": true,
      "browser.shell.checkDefaultBrowser": false,
      "browser.aboutConfig.showWarning": false,
      "browser.tabs.warnOnClose": false,
      "datareporting.healthreport.uploadEnabled": false,
      "datareporting.policy.dataSubmissionEnabled": false,
      "app.update.auto": false,
      "app.update.enabled": false,
      "browser.startup.homepage": "about:newtab",
      "browser.newtabpage.enabled": true,
      "browser.messaging-system.whatsNewPanel.enabled": false,
      "browser.newtabpage.activity-stream.showSearch": false,
      "browser.newtabpage.activity-stream.showTopSites": true,
      "browser.newtabpage.activity-stream.feeds.section.topstories": false,
      "browser.newtabpage.activity-stream.feeds.snippets": false,
      "browser.newtabpage.activity-stream.section.highlights.includeBookmarks": false,
      "browser.newtabpage.activity-stream.section.highlights.includeDownloads": false,
      "browser.newtabpage.activity-stream.section.highlights.includeVisited": false,
      "browser.newtabpage.activity-stream.section.highlights.includePocket": false
    }
  }
}
EOF

echo "Setting up Autoconfig..."
mkdir -p "$FIREFOX_DIR/defaults/pref"
cat <<EOF > "$FIREFOX_DIR/defaults/pref/autoconfig.js"
pref("general.config.filename", "seafari.cfg");
pref("general.config.obscure_value", 0);
pref("general.config.sandbox_enabled", false);
EOF

cat <<EOF > "$FIREFOX_DIR/seafari.cfg"
// seafari configuration
EOF

echo "Preparing Theme Folder..."
THEME_DIR="$FIREFOX_DIR/seafari-theme"
mkdir -p "$THEME_DIR"
cp -r MacTahoe userChrome.css userContent.css customChrome.css "$THEME_DIR/"
cp "seafari.png" "$THEME_DIR/seafari.png"

echo "Applying UI FIXES..."
cat <<EOF > "$THEME_DIR/customChrome.css"
@import "MacTahoe/theme.css";
.toolbarbutton-icon, .urlbar-icon, .identity-icon, #identity-icon, .button-icon, .menu-iconic-icon, image { fill: white !important; color: white !important; }
.toolbar-primary image, .urlbar-icon image, #nav-bar image { filter: invert(1) brightness(100) !important; }
:root { --theme-primary-color: #007aff !important; --theme-primary-hover-color: #0063cc !important; --theme-primary-active-color: #004da6 !important; --gnome-toolbar-icon-fill: #ffffff !important; --gnome-toolbar-color: #ffffff !important; }
#about-logo, .about-logo, #toolbar-delegate-logo, #about-logo-container, .brand-logo-container { background: url("seafari.png") no-repeat center !important; background-size: contain !important; }
#about-logo { width: 150px !important; height: 150px !important; display: block !important; }
EOF

cat <<EOF > "$THEME_DIR/userContent.css"
@-moz-document url-prefix("about:welcome") {
    .hero-image, .onboarding-hero-image, .page-header-image, .welcome-image, .fox-image, .illustration { display: none !important; }
    .main-content { max-width: 100% !important; margin: 0 !important; display: flex !important; flex-direction: column !important; align-items: center !important; justify-content: center !important; text-align: center !important; height: 100vh !important; background-color: #1a1a1a !important; }
    .page-content::before { content: ""; display: block; width: 200px; height: 200px; background: url("seafari.png") no-repeat center; background-size: contain; margin-bottom: 30px; }
    h1, p { color: white !important; }
}
@-moz-document url("about:home"), url("about:newtab") {
    body { background-color: #1a1a1a !important; background-image: url("seafari.png") !important; background-repeat: no-repeat !important; background-position: center 20% !important; background-size: 150px !important; }
    .activity-stream { background: transparent !important; }
    .search-wrapper, .logo-and-wordmark, .wordmark, .logo { display: none !important; }
    .top-site-outer .tile { background-color: rgba(255, 255, 255, 0.1) !important; border-radius: 12px !important; backdrop-filter: blur(10px) !important; width: 80px !important; height: 80px !important; }
    .top-site-outer .title { color: white !important; font-weight: 500 !important; }
}
@-moz-document url-prefix("about:") { .brand-logo, .logo { background: url("seafari.png") no-repeat center !important; background-size: contain !important; } }
EOF

echo "Binary Patching..."
patch_ja() {
    local ja_file=$1
    sed -i 's/Firefox/Seafari/g' "$ja_file"
    sed -i 's/firefox/seafari/g' "$ja_file"
}
patch_ja "$FIREFOX_DIR/omni.ja"
patch_ja "$FIREFOX_DIR/browser/omni.ja"

echo "Creating Wrapper Script..."
cat <<'EOF' > "$WORKSPACE/seafari.sh"
#!/bin/bash
HERE=$(dirname $(readlink -f $0))
if [ -d "$HERE/usr/lib/seafari" ]; then LIB_DIR="$HERE/usr/lib/seafari"; elif [ -d "/usr/lib/seafari" ]; then LIB_DIR="/usr/lib/seafari"; else LIB_DIR="$HERE/firefox"; fi
PROFILE_DIR="$HOME/.mozilla/seafari-profile"
mkdir -p "$PROFILE_DIR/chrome"
cp -r "$LIB_DIR/seafari-theme/"* "$PROFILE_DIR/chrome/"
PREFS_FILE="$PROFILE_DIR/prefs.js"
if [ ! -f "$PREFS_FILE" ]; then touch "$PREFS_FILE"; fi
sed -i '/toolkit.legacyUserProfileCustomizations.stylesheets/d' "$PREFS_FILE"
echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$PREFS_FILE"
exec "$LIB_DIR/firefox" --name "Seafari" --class "Seafari" --profile "$PROFILE_DIR" "$@"
EOF
chmod +x "$WORKSPACE/seafari.sh"

echo "Packaging .deb..."
DEB_ROOT="$WORKSPACE/deb"
mkdir -p "$DEB_ROOT/usr/bin" "$DEB_ROOT/usr/lib/seafari" "$DEB_ROOT/usr/share/applications" "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps" "$DEB_ROOT/DEBIAN"
cp -r "$FIREFOX_DIR/"* "$DEB_ROOT/usr/lib/seafari/"
cp "$WORKSPACE/seafari.sh" "$DEB_ROOT/usr/bin/seafari"
cp "seafari.png" "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps/seafari.png"
cat <<EOF > "$DEB_ROOT/usr/share/applications/seafari.desktop"
[Desktop Entry]
Name=Seafari
Exec=seafari %u
Icon=seafari
Terminal=false
Type=Application
Categories=Network;WebBrowser;
StartupWMClass=Seafari
EOF
cat <<EOF > "$DEB_ROOT/DEBIAN/control"
Package: seafari
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: Seafari Team
Description: Seafari - Safari styled browser.
EOF
dpkg-deb --build --root-owner-group "$DEB_ROOT" "seafari_${VERSION}_${DEB_ARCH}.deb"

echo "Packaging .rpm..."
# Using fpm for RPM if available, otherwise manual structure
if command -v fpm &> /dev/null; then
    fpm -s dir -t rpm -n seafari -v $VERSION -a $RPM_ARCH \
        --description "Seafari - Safari styled browser" \
        "$DEB_ROOT/usr/bin/seafari"=/usr/bin/seafari \
        "$DEB_ROOT/usr/lib/seafari/"=/usr/lib/seafari \
        "$DEB_ROOT/usr/share/applications/seafari.desktop"=/usr/share/applications/seafari.desktop \
        "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps/seafari.png"=/usr/share/icons/hicolor/scalable/apps/seafari.png
else
    echo "fpm not found, skipping RPM for now or use alien later."
    # We will install fpm in the CI
fi

# We ALWAYS use the x86_64 appimagetool because the GitHub Actions runner is x86_64.
# It can still package ARM64 AppDirs if the ARCH environment variable is set.
APPIMAGE_TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"

echo "Packaging AppImage..."
wget -O appimagetool "$APPIMAGE_TOOL_URL"
chmod +x appimagetool
APPDIR="$WORKSPACE/Seafari.AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib/seafari"
cp -r "$FIREFOX_DIR/"* "$APPDIR/usr/lib/seafari/"
cp "$WORKSPACE/seafari.sh" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
cp "seafari.png" "$APPDIR/seafari.png"
cp "$DEB_ROOT/usr/share/applications/seafari.desktop" "$APPDIR/"
ln -sf seafari.png "$APPDIR/.DirIcon"
echo "Packaging AppImage for $APPIMAGE_ARCH..."
export ARCH="$APPIMAGE_ARCH"
./appimagetool --appimage-extract-and-run "$APPDIR" "Seafari-${ARCH}.AppImage"

echo "Build complete for $ARCH_TYPE."
