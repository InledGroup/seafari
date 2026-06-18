#!/bin/bash
set -e

# Support for architecture selection and build options
ARCH_TYPE="amd64"
SKIP_RPM="false"

# Parse arguments
if [[ "$#" -gt 0 && ! "$1" =~ ^-- ]]; then
    ARCH_TYPE="$1"
    shift
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --arch) ARCH_TYPE="$2"; shift ;;
        --skip-rpm) SKIP_RPM="true" ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done
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
      "browser.newtabpage.activity-stream.section.highlights.includeVisited": true,
      "browser.newtabpage.activity-stream.section.highlights.includePocket": false,
      "browser.newtabpage.activity-stream.feeds.section.highlights": true,
      "browser.newtabpage.activity-stream.topSitesRows": 1,
      "browser.newtabpage.activity-stream.highlights.rows": 1
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
# seafari configuration
try {
  let { Services } = ChromeUtils.import("resource://gre/modules/Services.jsm");

  function setupUI(window) {
    let document = window.document;
    let navBar = document.getElementById("nav-bar-customization-target");
    let reloadBtn = document.getElementById("reload-button");

    if (!navBar || !reloadBtn) return;

    // Move New Tab button
    let newTabBtn = document.getElementById("new-tab-button") || document.getElementById("tabs-newtab-button");
    if (newTabBtn) {
      navBar.insertBefore(newTabBtn, reloadBtn.nextSibling);
    }

    // Add Tab Overview button
    if (!document.getElementById("tab-overview-button")) {
      let overviewBtn = document.createXULElement("toolbarbutton");
      overviewBtn.setAttribute("id", "tab-overview-button");
      overviewBtn.setAttribute("class", "toolbarbutton-1 chrome64-button");
      overviewBtn.setAttribute("label", "Tab Overview");
      overviewBtn.setAttribute("tooltiptext", "Tab Overview");
      overviewBtn.setAttribute("oncommand", "FirefoxViewHandler.openTab();");
      navBar.insertBefore(overviewBtn, reloadBtn.nextSibling);
    }
  }

  // Monitor for new windows
  Services.obs.addObserver(function(aSubject, aTopic, aData) {
    let window = aSubject;
    window.addEventListener("load", function() {
      if (window.location.href === "chrome://browser/content/browser.xhtml") {
        setupUI(window);
      }
    }, { once: true });
  }, "domwindowopened", false);

  // Apply to existing windows
  let windows = Services.wm.getEnumerator("navigator:browser");
  while (windows.hasMoreElements()) {
    let window = windows.getNext();
    if (window.location.href === "chrome://browser/content/browser.xhtml") {
      setupUI(window);
    }
  }
} catch (e) {
  Components.utils.reportError(e);
}
EOF

mkdir -p "$FIREFOX_DIR/defaults/pref"
cat <<EOF > "$FIREFOX_DIR/defaults/pref/autoconfig.js"
pref("general.config.filename", "seafari.cfg");
pref("general.config.obscure_value", 0);
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

/* Ensure New Tab button is visible and white */
#new-tab-button, #tabs-newtab-button, #tab-overview-button {
    visibility: visible !important;
    opacity: 1 !important;
    display: flex !important;
    fill: white !important;
    color: white !important;
}

#new-tab-button image, #tabs-newtab-button image, #tab-overview-button image {
    fill: white !important;
    color: white !important;
    filter: invert(1) brightness(100) !important;
}

#tab-overview-button {
    list-style-image: url("MacTahoe/icons/view-more-horizontal-symbolic.svg") !important;
}

/* Unify toolbar buttons into a single bubble */
#nav-bar #reload-button,
#nav-bar #tracking-protection-icon-container,
#nav-bar #new-tab-button,
#nav-bar #tabs-newtab-button,
#nav-bar #tab-overview-button,
#nav-bar #unified-extensions-button,
#nav-bar #PanelUI-menu-button {
    background: var(--gnome-headerbar-button-background) !important;
    border-radius: 0 !important;
    margin: 0 !important;
    padding: 0 4px !important;
    box-shadow: none !important;
    min-width: 38px !important;
    min-height: 38px !important;
    border-left: 1px solid rgba(255, 255, 255, 0.05) !important;
}

#nav-bar #reload-button {
    border-top-left-radius: 999px !important;
    border-bottom-left-radius: 999px !important;
    padding-left: 8px !important;
    border-left: none !important;
}

#nav-bar #PanelUI-menu-button {
    border-top-right-radius: 999px !important;
    border-bottom-right-radius: 999px !important;
    padding-right: 8px !important;
}

#nav-bar #reload-button:hover,
#nav-bar #tracking-protection-icon-container:hover,
#nav-bar #new-tab-button:hover,
#nav-bar #tabs-newtab-button:hover,
#nav-bar #tab-overview-button:hover,
#nav-bar #unified-extensions-button:hover,
#nav-bar #PanelUI-menu-button:hover {
    background: var(--gnome-headerbar-button-hover-background) !important;
}

#nav-bar #reload-button:active,
#nav-bar #tracking-protection-icon-container:active,
#nav-bar #new-tab-button:active,
#nav-bar #tabs-newtab-button:active,
#nav-bar #tab-overview-button:active,
#nav-bar #unified-extensions-button:active,
#nav-bar #PanelUI-menu-button:active {
    background: var(--gnome-headerbar-button-active-background) !important;
}

/* Tab close button white */

/* Tab close button white */
.tab-close-button {
    fill: white !important;
    color: white !important;
    filter: invert(1) brightness(100) !important;
}

/* Replace Firefox tab icon for New Tab */
.tab-icon-image[src="chrome://branding/content/icon32.png"],
.tab-icon-image[src="chrome://browser/skin/newtab/favicon.png"],
.tab-icon-image[src="page-icon:about:newtab"],
.tab-icon-image[src="page-icon:about:home"] {
    content: url("seafari.png") !important;
}
EOF

cat <<EOF > "$THEME_DIR/userContent.css"
@-moz-document url-prefix("about:welcome") {
    .section-secondary, .hero-image, .onboarding-hero-image, .page-header-image, .welcome-image, .fox-image, .illustration, .brand-logo, .logo-container { 
        display: none !important; 
    }
    .onboardingContainer {
        background: #1a1a1a !important;
        background-image: none !important;
    }
    .screen {
        display: flex !important;
        justify-content: center !important;
        align-items: center !important;
        background: transparent !important;
    }
    .section-main {
        width: 100% !important;
        max-width: 800px !important;
        margin: 0 auto !important;
        background: transparent !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: center !important;
    }
    .main-content {
        max-width: 100% !important;
        margin: 0 !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: center !important;
        justify-content: center !important;
        text-align: center !important;
        background-color: transparent !important;
    }
    h1, h2, p, span, label { color: white !important; }
}
@-moz-document url("about:home"), url("about:newtab") {
    body { background-color: #1a1a1a !important; }
    .activity-stream { background: transparent !important; }
    .search-wrapper, .wordmark { display: none !important; }
    
    .logo-and-wordmark {
        display: flex !important;
        justify-content: center !important;
        margin-top: 60px !important;
        margin-bottom: 20px !important;
    }
    .logo {
        background: url("seafari.png") no-repeat center !important;
        background-size: contain !important;
        width: 120px !important;
        height: 120px !important;
        display: block !important;
    }

    /* Titles */
    .section-title span { visibility: hidden !important; }
    .section-title span::before { visibility: visible !important; font-weight: 600 !important; font-size: 24px !important; color: white !important; }
    
    .top-sites .section-title span::before { content: "Favorites" !important; }
    .highlights .section-title span::before { content: "Frequently Visited" !important; }

    /* Top Sites (Favorites) */
    .top-site-outer .tile { 
        background-color: rgba(255, 255, 255, 0.1) !important; 
        border-radius: 12px !important; 
        backdrop-filter: blur(10px) !important; 
        width: 70px !important; 
        height: 70px !important; 
        box-shadow: 0 4px 15px rgba(0,0,0,0.2) !important;
    }
    .top-site-outer .title { color: white !important; font-weight: 500 !important; margin-top: 8px !important; }

    /* Highlights (Frequently Visited) */
    .highlights .card-outer {
        background: rgba(255, 255, 255, 0.05) !important;
        border-radius: 16px !important;
        overflow: hidden !important;
        border: 1px solid rgba(255, 255, 255, 0.1) !important;
        transition: transform 0.2s !important;
    }
    .highlights .card-outer:hover { transform: scale(1.02) !important; background: rgba(255, 255, 255, 0.08) !important; }
    .highlights .card-preview-image-outer { height: 120px !important; }
    .highlights .card-title { color: white !important; padding: 10px !important; }
    .highlights .card-context { display: none !important; }
}
@-moz-document url-prefix("about:") { .brand-logo, .logo { background: url("seafari.png") no-repeat center !important; background-size: contain !important; } }
EOF

echo "Binary Patching..."
patch_ja() {
    local ja_file=$1
    echo "Patching $ja_file..."
    # Safe name replacement (same length strings)
    sed -i 's/Firefox/Seafari/g; s/firefox/seafari/g' "$ja_file"
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

echo "Packaging .deb for $ARCH_TYPE..."
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

echo "Packaging .rpm and .pacman using fpm..."
# Ensure fpm is available or notify
if command -v fpm &> /dev/null; then
    # RPM Packaging
    fpm -s dir -t rpm -n seafari -v $VERSION -a $RPM_ARCH \
        --description "Seafari - Safari styled browser" \
        --category "Network" \
        --license "MPL 2.0" \
        "$DEB_ROOT/usr/bin/seafari"=/usr/bin/seafari \
        "$DEB_ROOT/usr/lib/seafari/"=/usr/lib/seafari \
        "$DEB_ROOT/usr/share/applications/seafari.desktop"=/usr/share/applications/seafari.desktop \
        "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps/seafari.png"=/usr/share/icons/hicolor/scalable/apps/seafari.png || true
    
    # Arch Linux (pacman) Packaging
    fpm -s dir -t pacman -n seafari -v $VERSION -a $RPM_ARCH \
        --description "Seafari - Safari styled browser" \
        --category "Network" \
        --license "MPL 2.0" \
        "$DEB_ROOT/usr/bin/seafari"=/usr/bin/seafari \
        "$DEB_ROOT/usr/lib/seafari/"=/usr/lib/seafari \
        "$DEB_ROOT/usr/share/applications/seafari.desktop"=/usr/share/applications/seafari.desktop \
        "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps/seafari.png"=/usr/share/icons/hicolor/scalable/apps/seafari.png || true
else
    echo "WARNING: fpm not found. Skipping RPM and Arch Linux packaging."
    echo "To install fpm: gem install fpm"
fi

if [ "$ARCH_TYPE" == "amd64" ]; then
    echo "Packaging AppImage (AMD64 only)..."
    APPIMAGE_TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
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
    
    ARCH="x86_64" ./appimagetool --appimage-extract-and-run "$APPDIR" "Seafari-x86_64.AppImage"
else
    echo "Skipping AppImage for $ARCH_TYPE (AMD64 only)."
fi

echo "Build complete for $ARCH_TYPE."
