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
# English: Package version (automatically incremented by CI for automated builds)
# Español: Versión del paquete (incrementada automáticamente por el CI para compilaciones automáticas)
VERSION="1.5.2"

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

# English: Cache the downloaded Seafari base tarball and extensions to speed up repeated builds
# Español: Cachear el tarball de Seafari base descargado y las extensiones para acelerar compilaciones repetidas
CACHE_DIR="$ROOT_DIR/build_cache_$ARCH_TYPE"
mkdir -p "$CACHE_DIR"

if [ ! -f "$CACHE_DIR/firefox.tar.xz" ]; then
    echo "Downloading fresh Seafari base ($ARCH_TYPE)..."
    wget -L -O "$CACHE_DIR/firefox.tar.xz" "$FF_URL"
else
    echo "Using cached Seafari base tarball from $CACHE_DIR/firefox.tar.xz"
fi

if [ ! -f "$CACHE_DIR/ublock_origin.xpi" ]; then
    echo "Downloading uBlock Origin..."
    wget -O "$CACHE_DIR/ublock_origin.xpi" "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
fi

if [ ! -f "$CACHE_DIR/adaptive_tab_bar_colour.xpi" ]; then
    echo "Downloading Adaptive Tab Bar Colour..."
    wget -O "$CACHE_DIR/adaptive_tab_bar_colour.xpi" "https://addons.mozilla.org/firefox/downloads/file/4704834/adaptive_tab_bar_colour-3.3.2.xpi"
fi

cp "$CACHE_DIR/firefox.tar.xz" "$WORKSPACE/firefox.tar.xz"
cp "$CACHE_DIR/ublock_origin.xpi" "$WORKSPACE/ublock_origin.xpi"
cp "$CACHE_DIR/adaptive_tab_bar_colour.xpi" "$WORKSPACE/adaptive_tab_bar_colour.xpi"

echo "Extracting Seafari base..."
tar xf "$WORKSPACE/firefox.tar.xz" -C "$WORKSPACE"

# Rename extracted folder if it's not named 'firefox'
mv $WORKSPACE/firefox* $WORKSPACE/firefox 2>/dev/null || true

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
    "SearchEngines": {
      "Default": "Google"
    },
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "file://$EXT_DIR/uBlock0@raymondhill.net.xpi"
      },
      "ATBC@EasonWong": {
        "installation_mode": "blocked"
      }
    },
    "Preferences": {
      "toolkit.legacyUserProfileCustomizations.stylesheets": true,
      "keyword.enabled": true,
      "browser.search.suggest.enabled": true,
      "browser.urlbar.suggest.searches": true,
      "browser.urlbar.showSearchSuggestionsFirst": true,
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
// seafari configuration
try {
  // English: Set default preferences to ensure search engine and suggestions work properly
  // Español: Establecer preferencias predeterminadas para asegurar que el motor de búsqueda y sugerencias funcionen bien
  pref("keyword.enabled", true);
  pref("browser.search.suggest.enabled", true);
  pref("browser.urlbar.suggest.searches", true);
  pref("browser.urlbar.showSearchSuggestionsFirst", true);
  pref("browser.search.defaultEngine.US", "Google");
  pref("browser.search.order.1", "Google");
  pref("browser.fixup.alternate.enabled", false);
  pref("browser.urlbar.dnsResolveSingleWordsAfterSearch", 0);
} catch (e) {
  // Silently ignore if preference engine is not fully loaded
}

try {
  function setupUI(window) {
    let document = window.document;
    let navBar = document.getElementById("nav-bar-customization-target");
    if (!navBar) return;

    // English: Ensure the new-tab-button is placed in the navigation toolbar
    // Español: Asegurar que el botón de nueva pestaña esté colocado en la barra de navegación
    let newTabBtn = document.getElementById("new-tab-button");
    if (newTabBtn && newTabBtn.parentNode !== navBar) {
      navBar.appendChild(newTabBtn);
    }

    // English: Hide unwanted elements in JS for maximum reliability
    // Español: Ocultar elementos no deseados en JS para máxima confiabilidad
    let idsToHide = [
      "fxa-toolbar-button",
      "unified-extensions-button",
      "tracking-protection-icon-container",
      "sidebar-button",
      "developer-button"
    ];
    idsToHide.forEach(id => {
      let el = document.getElementById(id);
      if (el) {
        el.style.display = "none";
        el.style.visibility = "collapse";
      }
    });

    let leftIds = [
      "back-button",
      "forward-button"
    ];
    let rightIds = [
      "new-tab-button",
      "tab-overview-button",
      "PanelUI-menu-button"
    ];

    // English: Get all current children
    // Español: Obtener todos los hijos actuales
    let children = Array.from(navBar.children);

    // English: Separate elements
    // Español: Separar elementos
    let leftNodes = [];
    let urlbarNode = null;
    let reloadNode = null;
    let rightNodes = [];
    let otherNodes = [];

    children.forEach(node => {
      let id = node.id;
      if (leftIds.includes(id)) {
        leftNodes.push(node);
      } else if (id === "urlbar-container") {
        urlbarNode = node;
      } else if (id === "stop-reload-button") {
        reloadNode = node;
      } else if (rightIds.includes(id)) {
        rightNodes.push(node);
      } else {
        if (!idsToHide.includes(id)) {
          otherNodes.push(node);
        }
      }
    });

    // English: Sort to match desired layouts
    // Español: Ordenar para que coincida con los diseños deseados
    leftNodes.sort((a, b) => leftIds.indexOf(a.id) - leftIds.indexOf(b.id));
    rightNodes.sort((a, b) => rightIds.indexOf(a.id) - rightIds.indexOf(b.id));

    // English: Re-append in precise order: [Left Group] [UrlBar] [Stop/Reload] [Other/Extensions] [Right Group]
    // Español: Volver a añadir en orden preciso: [Grupo Izquierdo] [UrlBar] [Parar/Recargar] [Otros/Extensiones] [Grupo Derecho]
    leftNodes.forEach(node => navBar.appendChild(node));
    if (urlbarNode) navBar.appendChild(urlbarNode);
    if (reloadNode) navBar.appendChild(reloadNode);
    otherNodes.forEach(node => navBar.appendChild(node));
    rightNodes.forEach(node => navBar.appendChild(node));
  }

  // English: Register observer to setup UI on new windows via sandbox-safe XPCOM
  // Español: Registrar observador para configurar la interfaz en nuevas ventanas vía XPCOM (seguro en sandbox)
  var observerService = Components.classes["@mozilla.org/observer-service;1"]
                                  .getService(Components.interfaces.nsIObserverService);

  var observer = {
    observe: function(aSubject, aTopic, aData) {
      var window = aSubject;
      window.addEventListener("load", function() {
        if (window.location.href === "chrome://browser/content/browser.xhtml") {
          setupUI(window);
        }
      }, { once: true });
    }
  };

  observerService.addObserver(observer, "domwindowopened", false);

  // English: Apply setup to already existing windows on startup via XPCOM Mediator
  // Español: Aplicar la configuración a ventanas ya existentes al arrancar vía XPCOM Mediator
  var windowMediator = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                                 .getService(Components.interfaces.nsIWindowMediator);
  var windows = windowMediator.getEnumerator("navigator:browser");
  while (windows.hasMoreElements()) {
    var window = windows.getNext();
    if (window.location.href === "chrome://browser/content/browser.xhtml") {
      setupUI(window);
    }
  }
} catch (e) {
  // Silently handle startup exceptions in sandbox
}
EOF


echo "Preparing Theme Folder..."
THEME_DIR="$FIREFOX_DIR/seafari-theme"
mkdir -p "$THEME_DIR"
cp -r MacTahoe userChrome.css userContent.css customChrome.css "$THEME_DIR/"
cp "seafari.png" "$THEME_DIR/seafari.png"

echo "Applying UI FIXES..."
cat <<'EOF' > "$THEME_DIR/customChrome.css"
@import "MacTahoe/theme.css";

:root {
    --theme-primary-color: #0071e3 !important;
    --theme-primary-hover-color: #005dc2 !important;
    --theme-primary-active-color: #004da6 !important;
    --gnome-toolbar-icon-fill: var(--toolbar-color, #2e2e2e) !important;
    --gnome-toolbar-color: var(--toolbar-color, #2e2e2e) !important;
}

@media (prefers-color-scheme: dark) {
    :root {
        --gnome-toolbar-icon-fill: var(--toolbar-color, #ffffff) !important;
        --gnome-toolbar-color: var(--toolbar-color, #ffffff) !important;
    }
}

:root[brighttext] {
    --gnome-toolbar-icon-fill: var(--toolbar-color, #ffffff) !important;
    --gnome-toolbar-color: var(--toolbar-color, #ffffff) !important;
}

.toolbarbutton-icon:not(.webextension-action), 
.urlbar-icon, 
.identity-icon, 
#identity-icon, 
.button-icon:not(.webextension-action), 
.menu-iconic-icon { 
    fill: var(--gnome-toolbar-icon-fill) !important; 
    color: var(--gnome-toolbar-color) !important; 
}

@media (prefers-color-scheme: dark) {
    .toolbar-primary image, 
    .urlbar-icon image, 
    #nav-bar toolbarbutton:not(.webextension-action) image { 
        filter: invert(1) brightness(100) !important; 
    }
}

:root[brighttext] .toolbar-primary image, 
:root[brighttext] .urlbar-icon image, 
:root[brighttext] #nav-bar toolbarbutton:not(.webextension-action) image { 
    filter: invert(1) brightness(100) !important; 
}

/* Hide unwanted icons (user profile, extensions, tracking protection shield, and sidebar) */
/* Ocultar iconos no deseados (perfil de usuario, extensiones, escudo de protección de rastreo y barra lateral) */
#fxa-toolbar-button,
#unified-extensions-button,
#tracking-protection-icon-container,
#tracking-protection-icon-box,
#tracking-protection-icon,
#tracking-protection-icon-animatable-image,
.tracking-protection-button,
#sidebar-button,
#developer-button,
#nav-bar #fxa-toolbar-button,
#nav-bar #unified-extensions-button,
#nav-bar #tracking-protection-icon-container,
#nav-bar #sidebar-button,
#nav-bar #developer-button {
    display: none !important;
    visibility: collapse !important;
    width: 0 !important;
    margin: 0 !important;
    padding: 0 !important;
}

/* Hide new tab button on tab strip to prevent duplication */
/* Ocultar botón de nueva pestaña en la barra de pestañas para evitar duplicación */
#tabs-newtab-button,
.tabs-newtab-button {
    display: none !important;
    visibility: hidden !important;
}

#about-logo, .about-logo, #toolbar-delegate-logo, #about-logo-container, .brand-logo-container { background: url("seafari.png") no-repeat center !important; background-size: contain !important; }
#about-logo { width: 150px !important; height: 150px !important; display: block !important; }

/* Ensure New Tab and Overview buttons are visible */
#new-tab-button, #tab-overview-button {
    visibility: visible !important;
    opacity: 1 !important;
    display: flex !important;
}

@media (prefers-color-scheme: dark) {
    #new-tab-button, #tab-overview-button {
        fill: var(--gnome-toolbar-icon-fill) !important;
        color: var(--gnome-toolbar-color) !important;
    }
    #new-tab-button image, #tab-overview-button image {
        fill: var(--gnome-toolbar-icon-fill) !important;
        color: var(--gnome-toolbar-color) !important;
        filter: invert(1) brightness(100) !important;
    }
}

:root[brighttext] #new-tab-button image, :root[brighttext] #tab-overview-button image {
    fill: var(--gnome-toolbar-icon-fill) !important;
    color: var(--gnome-toolbar-color) !important;
    filter: invert(1) brightness(100) !important;
}

#tab-overview-button {
    list-style-image: url("MacTahoe/icons/view-more-horizontal-symbolic.svg") !important;
}

/* Reload button style (next to URL bar, matching other buttons) */
/* Estilo del botón de recarga (al lado de la barra de URL, a juego con el resto) */
#nav-bar #stop-reload-button {
    margin: 0 4px !important;
    padding: 0 !important;
}

#nav-bar #stop-reload-button > #reload-button,
#nav-bar #stop-reload-button > #stop-button {
    margin: 0 !important;
}

/* Ensure only one icon is visible (reload OR stop) depending on loading state */
/* Asegurar que solo un icono sea visible (recarga O parada) según el estado de carga */
#nav-bar #stop-reload-button > #reload-button[hidden],
#nav-bar #stop-reload-button > #stop-button[hidden] {
    display: none !important;
}

/* --- Unified Left Button Group (Capsule/Bubble) --- */
/* English: Style the entire left button group (Back, Forward) as a single unified capsule */
/* Español: Estilizar todo el grupo de botones de la izquierda (Atrás, Adelante) como una única cápsula unificada */
#nav-bar #back-button,
#nav-bar #forward-button {
    background: rgba(0, 0, 0, 0.05) !important;
    border-radius: 0 !important;
    margin: 0 !important;
    padding: 0 8px !important;
    min-width: 36px !important;
    min-height: 34px !important;
    height: 34px !important;
    box-shadow: none !important;
    border: none !important;
    border-left: 1px solid rgba(0, 0, 0, 0.05) !important;
    display: inline-flex !important;
    align-items: center !important;
    justify-content: center !important;
}

/* Hover/Active states for Left Group */
#nav-bar #back-button:hover,
#nav-bar #forward-button:hover {
    background: rgba(0, 0, 0, 0.1) !important;
}
#nav-bar #back-button:active,
#nav-bar #forward-button:active {
    background: rgba(0, 0, 0, 0.15) !important;
}

@media (prefers-color-scheme: dark) {
    #nav-bar #back-button,
    #nav-bar #forward-button {
        background: rgba(255, 255, 255, 0.08) !important;
        border-left: 1px solid rgba(255, 255, 255, 0.08) !important;
    }
    #nav-bar #back-button:hover,
    #nav-bar #forward-button:hover {
        background: rgba(255, 255, 255, 0.16) !important;
    }
    #nav-bar #back-button:active,
    #nav-bar #forward-button:active {
        background: rgba(255, 255, 255, 0.24) !important;
    }
}

:root[brighttext] #nav-bar #back-button,
:root[brighttext] #nav-bar #forward-button {
    background: rgba(255, 255, 255, 0.08) !important;
    border-left: 1px solid rgba(255, 255, 255, 0.08) !important;
}
:root[brighttext] #nav-bar #back-button:hover,
:root[brighttext] #nav-bar #forward-button:hover {
    background: rgba(255, 255, 255, 0.16) !important;
}
:root[brighttext] #nav-bar #back-button:active,
:root[brighttext] #nav-bar #forward-button:active {
    background: rgba(255, 255, 255, 0.24) !important;
}

/* Dynamic Left Corner Rounding for Left Group */
#nav-bar #back-button:not([hidden]) {
    border-top-left-radius: 999px !important;
    border-bottom-left-radius: 999px !important;
    border-left: none !important;
    padding-left: 12px !important;
}

/* Dynamic Right Corner Rounding for Left Group */
#nav-bar #forward-button:not([hidden]) {
    border-top-right-radius: 999px !important;
    border-bottom-right-radius: 999px !important;
    padding-right: 12px !important;
}
#nav-bar #forward-button[hidden] ~ #back-button:not([hidden]) {
    border-top-right-radius: 999px !important;
    border-bottom-right-radius: 999px !important;
    padding-right: 12px !important;
}

/* --- Unified Right Button Group (Capsule/Bubble) --- */
/* English: Style the entire right button group (New Tab, Overview, Menu) as a single unified capsule */
/* Español: Estilizar todo el grupo de botones de la derecha (Nueva pestaña, Overview, Menú) como una única cápsula unificada */
#nav-bar #new-tab-button,
#nav-bar #tab-overview-button,
#nav-bar #PanelUI-menu-button {
    background: rgba(0, 0, 0, 0.05) !important;
    border-radius: 0 !important;
    margin: 0 !important;
    padding: 0 8px !important;
    min-width: 36px !important;
    min-height: 34px !important;
    height: 34px !important;
    box-shadow: none !important;
    border: none !important;
    border-left: 1px solid rgba(0, 0, 0, 0.05) !important;
    display: inline-flex !important;
    align-items: center !important;
    justify-content: center !important;
}

/* Hover/Active states for Right Group */
#nav-bar #new-tab-button:hover,
#nav-bar #tab-overview-button:hover,
#nav-bar #PanelUI-menu-button:hover {
    background: rgba(0, 0, 0, 0.1) !important;
}
#nav-bar #new-tab-button:active,
#nav-bar #tab-overview-button:active,
#nav-bar #PanelUI-menu-button:active {
    background: rgba(0, 0, 0, 0.15) !important;
}

@media (prefers-color-scheme: dark) {
    #nav-bar #new-tab-button,
    #nav-bar #tab-overview-button,
    #nav-bar #PanelUI-menu-button {
        background: rgba(255, 255, 255, 0.08) !important;
        border-left: 1px solid rgba(255, 255, 255, 0.08) !important;
    }
    #nav-bar #new-tab-button:hover,
    #nav-bar #tab-overview-button:hover,
    #nav-bar #PanelUI-menu-button:hover {
        background: rgba(255, 255, 255, 0.16) !important;
    }
    #nav-bar #new-tab-button:active,
    #nav-bar #tab-overview-button:active,
    #nav-bar #PanelUI-menu-button:active {
        background: rgba(255, 255, 255, 0.24) !important;
    }
}

:root[brighttext] #nav-bar #new-tab-button,
:root[brighttext] #nav-bar #tab-overview-button,
:root[brighttext] #nav-bar #PanelUI-menu-button {
    background: rgba(255, 255, 255, 0.08) !important;
    border-left: 1px solid rgba(255, 255, 255, 0.08) !important;
}
:root[brighttext] #nav-bar #new-tab-button:hover,
:root[brighttext] #nav-bar #tab-overview-button:hover,
:root[brighttext] #nav-bar #PanelUI-menu-button:hover {
    background: rgba(255, 255, 255, 0.16) !important;
}
:root[brighttext] #nav-bar #new-tab-button:active,
:root[brighttext] #nav-bar #tab-overview-button:active,
:root[brighttext] #nav-bar #PanelUI-menu-button:active {
    background: rgba(255, 255, 255, 0.24) !important;
}

/* Dynamic Left Corner Rounding for Right Group */
#nav-bar #new-tab-button:not([hidden]) {
    border-top-left-radius: 999px !important;
    border-bottom-left-radius: 999px !important;
    border-left: none !important;
    padding-left: 12px !important;
}
#nav-bar #new-tab-button[hidden] ~ #tab-overview-button:not([hidden]) {
    border-top-left-radius: 999px !important;
    border-bottom-left-radius: 999px !important;
    border-left: none !important;
    padding-left: 12px !important;
}

/* Dynamic Right Corner Rounding for Right Group */
#nav-bar #PanelUI-menu-button:not([hidden]) {
    border-top-right-radius: 999px !important;
    border-bottom-right-radius: 999px !important;
    padding-right: 12px !important;
}

/* Ensure the URL Bar has a small spacing and default right padding */
#urlbar-input-container,
.urlbar-input-container {
    padding-right: 8px !important;
}

/* Tab close button white in dark mode */
@media (prefers-color-scheme: dark) {
    .tab-close-button {
        fill: var(--gnome-toolbar-icon-fill) !important;
        color: var(--gnome-toolbar-color) !important;
        filter: invert(1) brightness(100) !important;
    }
}

:root[brighttext] .tab-close-button {
    filter: invert(1) brightness(100) !important;
}

/* Replace Seafari tab icon for New Tab */
.tab-icon-image[src="chrome://branding/content/icon32.png"],
.tab-icon-image[src="chrome://browser/skin/newtab/favicon.png"],
.tab-icon-image[src="page-icon:about:newtab"],
.tab-icon-image[src="page-icon:about:home"] {
    content: url("seafari.png") !important;
}

/* English: Flat blue style with rounded corners for chrome primary/dialog buttons */
/* Español: Estilo azul plano con bordes redondeados para botones primarios/diálogos de chrome */
button,
.button,
moz-button {
    border-radius: 999px !important;
    --button-border-radius: 999px !important;
    --button-border-radius-hover: 999px !important;
    --button-border-radius-active: 999px !important;
    --button-border-radius-large: 999px !important;
    --button-border-radius-medium: 999px !important;
    --button-border-radius-small: 999px !important;
    --button-background-color-primary: #0071e3 !important;
    --button-background-color-primary-hover: #005dc2 !important;
    --button-background-color-primary-active: #004da6 !important;
    --button-text-color-primary: white !important;
}

button.main-button,
button[type="submit"],
.button-primary,
button.button-primary,
button.primary,
button.dialog-button[default="true"],
.dialog-button-box button[default="true"],
#updateSettingsContainer button:not(moz-button),
#aboutwelcome-onboarding button:not(moz-button) {
    background-color: #0071e3 !important;
    background-image: none !important;
    border: none !important;
    color: white !important;
    box-shadow: none !important;
    text-shadow: none !important;
    cursor: pointer !important;
}

button.main-button:hover,
button[type="submit"]:hover,
.button-primary:hover,
button.button-primary:hover,
button.primary:hover,
button.dialog-button[default="true"]:hover,
.dialog-button-box button[default="true"]:hover,
#updateSettingsContainer button:hover:not(moz-button),
#aboutwelcome-onboarding button:hover:not(moz-button) {
    background-color: #005dc2 !important;
    background-image: none !important;
    box-shadow: none !important;
}

button.main-button:active,
button[type="submit"]:active,
.button-primary:active,
button.button-primary:active,
button.primary:active,
button.dialog-button[default="true"]:active,
.dialog-button-box button[default="true"]:active,
#updateSettingsContainer button:active:not(moz-button),
#aboutwelcome-onboarding button:active:not(moz-button) {
    background-color: #004da6 !important;
    background-image: none !important;
    box-shadow: none !important;
}
EOF

cat <<EOF >> "$THEME_DIR/userContent.css"
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

/* English: Hide enterprise policy / managed warnings and organization updates notice in preferences */
/* Español: Ocultar advertencias de directiva empresarial / administración y aviso de actualizaciones de la organización en preferencias */
@-moz-document url-prefix("about:preferences") {
    #policies-container,
    #policies-container-content,
    .enterprise-controlled,
    .managed-box,
    #managed-box,
    #updateSettingsContainer .box-container,
    #updateApp .box-container,
    .box-container:has(span[id="label"]),
    .box-container:has(slot[name="actions-start"]) {
        display: none !important;
    }
}

/* Apple Safari layout variables and overrides */
@-moz-document url-prefix("about:"), url-prefix("chrome://"), url-prefix("resource://") {
    :root {
        --color-violet-90: #0071e3 !important;
        --color-violet-80: #005dc2 !important;
        --color-violet-70: #004da6 !important;
        --color-violet-60: #0071e3 !important;
        --button-background-color-primary: #0071e3 !important;
        --button-background-color-primary-hover: #005dc2 !important;
        --button-background-color-primary-active: #004da6 !important;
        --in-content-primary-button-background: #0071e3 !important;
        --in-content-primary-button-background-hover: #005dc2 !important;
        --in-content-primary-button-background-active: #004da6 !important;
        --newtab-primary-action-background: #0071e3 !important;
        --theme-primary-color: #0071e3 !important;
        --theme-primary-hover-color: #005dc2 !important;
        --theme-primary-active-color: #004da6 !important;
        --button-border-radius: 999px !important;
    }

    /* Style main-buttons globally to look like macOS Tahoe (Flat Blue) */
    button,
    .button,
    moz-button {
        border-radius: 999px !important;
        --button-border-radius: 999px !important;
        --button-border-radius-hover: 999px !important;
        --button-border-radius-active: 999px !important;
        --button-border-radius-large: 999px !important;
        --button-border-radius-medium: 999px !important;
        --button-border-radius-small: 999px !important;
        --button-background-color-primary: #0071e3 !important;
        --button-background-color-primary-hover: #005dc2 !important;
        --button-background-color-primary-active: #004da6 !important;
        --button-text-color-primary: white !important;
    }

    button.main-button,
    button[type="submit"],
    .button-primary,
    button.button-primary,
    button.primary,
    button.dialog-button[default="true"],
    .dialog-button-box button[default="true"],
    #updateSettingsContainer button:not(moz-button),
    #aboutwelcome-onboarding button:not(moz-button) {
        background-color: #0071e3 !important;
        background-image: none !important;
        border: none !important;
        color: white !important;
        box-shadow: none !important;
        text-shadow: none !important;
        cursor: pointer !important;
    }

    button.main-button:hover,
    button[type="submit"]:hover,
    .button-primary:hover,
    button.button-primary:hover,
    button.primary:hover,
    button.dialog-button[default="true"]:hover,
    .dialog-button-box button[default="true"]:hover,
    #updateSettingsContainer button:hover:not(moz-button),
    #aboutwelcome-onboarding button:hover:not(moz-button) {
        background-color: #005dc2 !important;
        background-image: none !important;
        box-shadow: none !important;
    }

    button.main-button:active,
    button[type="submit"]:active,
    .button-primary:active,
    button.button-primary:active,
    button.primary:active,
    button.dialog-button[default="true"]:active,
    .dialog-button-box button[default="true"]:active,
    #updateSettingsContainer button:active:not(moz-button),
    #aboutwelcome-onboarding button:active:not(moz-button) {
        background-color: #004da6 !important;
        background-image: none !important;
        box-shadow: none !important;
    }

    #category-more-from-mozilla,
    .category[name="more-from-mozilla"] {
        display: none !important;
    }
}
EOF

echo "Binary Patching (Safe Zip Method)..."
# English: We patch omni.ja safely by unzipping, updating branding files, sed'ing only text files, and re-zipping
# Español: Parcheamos omni.ja de forma segura descomprimiendo, actualizando los archivos de branding, aplicando sed solo a archivos de texto y volviendo a comprimir
patch_ja() {
    local ja_file=$1
    echo "Patching $ja_file safely..."
    if [ ! -f "$ja_file" ]; then
        echo "Warning: $ja_file not found, skipping."
        return
    fi

    local temp_dir
    temp_dir=$(mktemp -d)

    # English: Extract the omni.ja file to a temporary directory using unzip. Ignore warnings (unzip exits with 1 or 2 for extra bytes) but verify files were actually extracted.
    # Español: Extraer el archivo omni.ja a un directorio temporal usando unzip. Ignorar advertencias (unzip sale con 1 o 2 por bytes extra) pero verificar que los archivos realmente se hayan extraído.
    unzip -q "$ja_file" -d "$temp_dir" || true
    if [ -z "$(ls -A "$temp_dir")" ]; then
        echo "Error: Extraction of $ja_file failed, temporary directory is empty."
        exit 1
    fi

    # English: Replace specific brand configurations to match Seafari and Inled Group in brand.properties (all locales)
    # Español: Reemplazar configuraciones de marca específicas para coincidir con Seafari e Inled Group en brand.properties (todos los idiomas)
    find "$temp_dir" -name "brand.properties" -exec sed -i -E '
        s/^brandShortName[[:space:]]*=[[:space:]]*.*/brandShortName=Seafari/g;
        s/^brandFullName[[:space:]]*=[[:space:]]*.*/brandFullName=Seafari Browser/g;
        s/^vendorShortName[[:space:]]*=[[:space:]]*.*/vendorShortName=Inled Group/g
    ' {} + 2>/dev/null || true

    # English: Replace specific brand entity declarations to match Seafari and Inled Group in brand.dtd (all locales)
    # Español: Reemplazar declaraciones de entidad de marca específicas para coincidir con Seafari e Inled Group en brand.dtd (todos los idiomas)
    find "$temp_dir" -name "brand.dtd" -exec sed -i -E '
        s/<!ENTITY[[:space:]]+brandShortName[[:space:]]+"[^"]*"[[:space:]]*>/<!ENTITY brandShortName        "Seafari">/g;
        s/<!ENTITY[[:space:]]+brandFullName[[:space:]]+"[^"]*"[[:space:]]*>/<!ENTITY brandFullName         "Seafari Browser">/g;
        s/<!ENTITY[[:space:]]+vendorShortName[[:space:]]+"[^"]*"[[:space:]]*>/<!ENTITY vendorShortName       "Inled Group">/g
    ' {} + 2>/dev/null || true

    # English: Replace specific brand configurations to match Seafari and Inled Group in brand.ftl (all locales)
    # Español: Reemplazar configuraciones de marca específicas para coincidir con Seafari e Inled Group en brand.ftl (todos los idiomas)
    find "$temp_dir" -name "brand.ftl" -exec sed -i -E '
        s/^-brand-shorter-name[[:space:]]*=[[:space:]]*.*/-brand-shorter-name = Seafari/g;
        s/^-brand-short-name[[:space:]]*=[[:space:]]*.*/-brand-short-name = Seafari/g;
        s/^-brand-shortcut-name[[:space:]]*=[[:space:]]*.*/-brand-shortcut-name = Seafari/g;
        s/^-brand-full-name[[:space:]]*=[[:space:]]*.*/-brand-full-name = Seafari Browser/g;
        s/^-brand-product-name[[:space:]]*=[[:space:]]*.*/-brand-product-name = Seafari/g;
        s/^-vendor-short-name[[:space:]]*=[[:space:]]*.*/-vendor-short-name = Inled Group/g
    ' {} + 2>/dev/null || true

    # English: Overwrite Firefox branding images and wordmarks with Seafari versions if branding directory exists
    # Español: Sobrescribir las imágenes y marcas de texto de Firefox con las versiones de Seafari si existe el directorio de branding
    local branding_dir="$temp_dir/chrome/browser/content/branding"
    if [ -d "$branding_dir" ]; then
        echo "Replacing Firefox branding images with Seafari..."
        for icon in icon16.png icon32.png icon48.png icon64.png icon128.png about.png about-logo.png about-logo@2x.png about-logo-private.png about-logo-private@2x.png; do
            if [ -f "$branding_dir/$icon" ]; then
                cp "$ROOT_DIR/seafari.png" "$branding_dir/$icon"
            fi
        done
        if [ -f "$branding_dir/about-logo.svg" ]; then
            cat <<EOF > "$branding_dir/about-logo.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <image href="icon128.png" x="0" y="0" width="128" height="128"/>
</svg>
EOF
        fi
        if [ -f "$branding_dir/firefox-wordmark.svg" ]; then
            cat <<EOF > "$branding_dir/firefox-wordmark.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 30" width="120" height="30">
  <text x="0" y="22" font-family="system-ui, sans-serif" font-size="20" font-weight="bold" fill="white">Seafari</text>
</svg>
EOF
        fi
        if [ -f "$branding_dir/about-wordmark.svg" ]; then
            cat <<EOF > "$branding_dir/about-wordmark.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 30" width="120" height="30">
  <text x="0" y="22" font-family="system-ui, sans-serif" font-size="20" font-weight="bold" fill="white">Seafari</text>
</svg>
EOF
        fi
    fi

    # English: Make the fox-ai.svg preference icon transparent
    # Español: Hacer transparente el icono de preferencias fox-ai.svg
    local fox_ai_svg="$temp_dir/chrome/browser/skin/classic/browser/preferences/fox-ai.svg"
    if [ -f "$fox_ai_svg" ]; then
        echo "Making fox-ai.svg transparent..."
        cat <<EOF > "$fox_ai_svg"
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"/>
EOF
    fi

    # English: Make all illustrations transparent in any folder named 'illustrations'
    # Español: Hacer transparentes todas las ilustraciones en cualquier carpeta llamada 'illustrations'
    find "$temp_dir" -type d -name "illustrations" | while read -r ill_dir; do
        echo "Found illustrations directory at: $ill_dir. Making all images transparent..."
        find "$ill_dir" -type f | while read -r file; do
            case "$file" in
                *.svg)
                    cat <<EOF > "$file"
<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1" viewBox="0 0 1 1"/>
EOF
                    ;;
                *.png)
                    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" | base64 -d > "$file"
                    ;;
                *)
                    echo -n "" > "$file"
                    ;;
            esac
        done
    done

    # English: Append Safari layout styles to global.css
    # Español: Adjuntar estilos de diseño de Safari a global.css
    local global_css="$temp_dir/chrome/toolkit/skin/classic/global/global.css"
    if [ -f "$global_css" ]; then
        echo "Appending Safari layout variables and styles to global.css..."
        cat <<'EOF' >> "$global_css"

/* Apple Safari layout variables and overrides */
:root {
    --color-violet-90: #0071e3 !important;
    --color-violet-80: #005dc2 !important;
    --color-violet-70: #004da6 !important;
    --color-violet-60: #0071e3 !important;
    --button-background-color-primary: #0071e3 !important;
    --button-background-color-primary-hover: #005dc2 !important;
    --button-background-color-primary-active: #004da6 !important;
    --in-content-primary-button-background: #0071e3 !important;
    --in-content-primary-button-background-hover: #005dc2 !important;
    --in-content-primary-button-background-active: #004da6 !important;
    --newtab-primary-action-background: #0071e3 !important;
    --theme-primary-color: #0071e3 !important;
    --theme-primary-hover-color: #005dc2 !important;
    --theme-primary-active-color: #004da6 !important;
    --button-border-radius: 999px !important;
}

/* Style main-buttons globally in global.css to look like macOS Tahoe (Flat Blue) */
button,
.button,
moz-button {
    border-radius: 999px !important;
    --button-border-radius: 999px !important;
    --button-border-radius-hover: 999px !important;
    --button-border-radius-active: 999px !important;
    --button-border-radius-large: 999px !important;
    --button-border-radius-medium: 999px !important;
    --button-border-radius-small: 999px !important;
    --button-background-color-primary: #0071e3 !important;
    --button-background-color-primary-hover: #005dc2 !important;
    --button-background-color-primary-active: #004da6 !important;
    --button-text-color-primary: white !important;
}

button.main-button,
button[type="submit"],
.button-primary,
button.button-primary,
button.primary,
button.dialog-button[default="true"],
.dialog-button-box button[default="true"],
#updateSettingsContainer button:not(moz-button),
#aboutwelcome-onboarding button:not(moz-button) {
    background-color: #0071e3 !important;
    background-image: none !important;
    border: none !important;
    color: white !important;
    box-shadow: none !important;
    text-shadow: none !important;
    cursor: pointer !important;
}

button.main-button:hover,
button[type="submit"]:hover,
.button-primary:hover,
button.button-primary:hover,
button.primary:hover,
button.dialog-button[default="true"]:hover,
.dialog-button-box button[default="true"]:hover,
#updateSettingsContainer button:hover:not(moz-button),
#aboutwelcome-onboarding button:hover:not(moz-button) {
    background-color: #005dc2 !important;
    background-image: none !important;
    box-shadow: none !important;
}

button.main-button:active,
button[type="submit"]:active,
.button-primary:active,
button.button-primary:active,
button.primary:active,
button.dialog-button[default="true"]:active,
.dialog-button-box button[default="true"]:active,
#updateSettingsContainer button:active:not(moz-button),
#aboutwelcome-onboarding button:active:not(moz-button) {
    background-color: #004da6 !important;
    background-image: none !important;
    box-shadow: none !important;
}

#category-more-from-mozilla,
.category[name="more-from-mozilla"] {
    display: none !important;
}
EOF
    fi

    # English: Append Safari layout styles to aboutNetError.css
    # Español: Adjuntar estilos de diseño de Safari a aboutNetError.css
    local net_error_css="$temp_dir/chrome/toolkit/skin/classic/global/aboutNetError.css"
    if [ -f "$net_error_css" ]; then
        echo "Appending Safari connection styles to aboutNetError.css..."
        cat <<'EOF' >> "$net_error_css"

/* Safari style for about:neterror */
body {
    background-color: #1a1a1a !important;
    color: #e0e0e0 !important;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
    display: flex !important;
    flex-direction: column !important;
    justify-content: center !important;
    align-items: center !important;
    height: 100vh !important;
    margin: 0 !important;
    padding: 20px !important;
    box-sizing: border-box !important;
    text-align: center !important;
}

#errorPageContainer {
    max-width: 600px !important;
    margin: 0 auto !important;
    display: flex !important;
    flex-direction: column !important;
    align-items: center !important;
    justify-content: center !important;
}

.illustration,
.error-illustration,
#errorPageContainer::before,
.title-icon {
    display: none !important;
}

h1,
.title {
    font-size: 22px !important;
    font-weight: 600 !important;
    color: #ffffff !important;
    margin-bottom: 12px !important;
    text-align: center !important;
}

@media (prefers-color-scheme: light) {
    body {  <span class="warning-highlight">Important:</span> Currently, Seafari requires your operating system to be in <strong>Dark Mode</strong> (it does not render correctly in Light Mode).
        background-color: #f5f5f7 !important;
        color: #1d1d1f !important;
    }
    h1, .title {
        color: #1d1d1f !important;
    }
    .description, p, #errorDescriptionContainer {
        color: #86868b !important;
    }
}

.description,
p,
#errorDescriptionContainer,
#errorShortDescText {
    font-size: 14px !important;
    line-height: 1.5 !important;
    color: #a1a1a6 !important;
    text-align: center !important;
    margin-bottom: 24px !important;
    max-width: 480px !important;
}

#netErrorButtonContainer {
    margin-top: 10px !important;
}

button,
.button,
#tryAgainButton {
    background-color: rgba(255, 255, 255, 0.1) !important;
    border: 1px solid rgba(255, 255, 255, 0.2) !important;
    color: white !important;
    border-radius: 6px !important;
    padding: 6px 16px !important;
    font-size: 13px !important;
    font-weight: 500 !important;
    cursor: pointer !important;
}

@media (prefers-color-scheme: light) {
    button, .button, #tryAgainButton {
        background-color: rgba(0, 0, 0, 0.05) !important;
        border: 1px solid rgba(0, 0, 0, 0.1) !important;
        color: #1d1d1f !important;
    }
}
EOF
    fi

    # English: Replace standalone original branding with Seafari in text files (including .ftl Fluent files) only to prevent binary/path corruption
    # Español: Reemplazar la marca original por Seafari solo como palabra independiente en archivos de texto (incluyendo archivos .ftl de Fluent) para evitar corrupción de binarios/rutas
    find "$temp_dir" -type f \( -name "*.properties" -o -name "*.dtd" -o -name "*.ftl" -o -name "*.json" -o -name "*.js" -o -name "*.sys.mjs" -o -name "*.xhtml" -o -name "*.xml" -o -name "*.html" -o -name "*.css" \) -exec perl -pi -e 's|(?<!/)\bFirefox\b|Seafari|g' {} + 2>/dev/null || true

    # English: Re-compress the files back into the original omni.ja location
    # Español: Volver a comprimir los archivos en la ubicación del omni.ja original
    rm -f "$ja_file"
    (cd "$temp_dir" && zip -q -r "$ROOT_DIR/$ja_file" .)

    rm -rf "$temp_dir"
}

patch_ja "$FIREFOX_DIR/omni.ja"
patch_ja "$FIREFOX_DIR/browser/omni.ja"

echo "Patching application.ini..."
# English: Patch application.ini to configure the name, vendor, remoting name and ID for GNOME/Wayland desktop integration
# Español: Parchear application.ini para configurar el nombre, proveedor, nombre de remoting e ID para la integración de escritorio con GNOME/Wayland
patch_application_ini() {
    local ini_path=$1
    if [ -f "$ini_path" ]; then
        echo "Patching $ini_path..."
        sed -i 's/^Vendor=.*/Vendor=Inled Group/' "$ini_path"
        sed -i 's/^Name=.*/Name=Seafari/' "$ini_path"
        sed -i 's/^RemotingName=.*/RemotingName=seafari/' "$ini_path"
        sed -i 's/^ID=.*/ID=seafari@inledgroup/' "$ini_path"
        if ! grep -q "CodeName=" "$ini_path"; then
            sed -i '/^\[App\]/a CodeName=Seafari' "$ini_path"
        fi
    fi
}
patch_application_ini "$FIREFOX_DIR/application.ini"
patch_application_ini "$FIREFOX_DIR/browser/application.ini"

echo "Creating Wrapper Script..."
cat <<'EOF' > "$WORKSPACE/seafari.sh"
#!/bin/bash
HERE=$(dirname $(readlink -f $0))
if [ -d "$HERE/firefox" ]; then LIB_DIR="$HERE/firefox"; elif [ -d "$HERE/usr/lib/seafari" ]; then LIB_DIR="$HERE/usr/lib/seafari"; elif [ -d "/usr/lib/seafari" ]; then LIB_DIR="/usr/lib/seafari"; else LIB_DIR="$HERE/firefox"; fi
PROFILE_DIR="$HOME/.mozilla/seafari-profile"
mkdir -p "$PROFILE_DIR/chrome"
cp -r "$LIB_DIR/seafari-theme/"* "$PROFILE_DIR/chrome/"
USER_JS="$PROFILE_DIR/user.js"
if [ ! -f "$USER_JS" ]; then touch "$USER_JS"; fi
# Clean and add stylesheet and search preference defaults to prevent system overriding
sed -i '/toolkit.legacyUserProfileCustomizations.stylesheets/d' "$USER_JS"
echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$USER_JS"
sed -i '/keyword.enabled/d' "$USER_JS"
echo 'user_pref("keyword.enabled", true);' >> "$USER_JS"
sed -i '/browser.search.suggest.enabled/d' "$USER_JS"
echo 'user_pref("browser.search.suggest.enabled", true);' >> "$USER_JS"
sed -i '/browser.urlbar.suggest.searches/d' "$USER_JS"
echo 'user_pref("browser.urlbar.suggest.searches", true);' >> "$USER_JS"
sed -i '/browser.urlbar.showSearchSuggestionsFirst/d' "$USER_JS"
echo 'user_pref("browser.urlbar.showSearchSuggestionsFirst", true);' >> "$USER_JS"
sed -i '/browser.search.defaultEngine.US/d' "$USER_JS"
echo 'user_pref("browser.search.defaultEngine.US", "Google");' >> "$USER_JS"
sed -i '/browser.search.order.1/d' "$USER_JS"
echo 'user_pref("browser.search.order.1", "Google");' >> "$USER_JS"
sed -i '/browser.fixup.alternate.enabled/d' "$USER_JS"
echo 'user_pref("browser.fixup.alternate.enabled", false);' >> "$USER_JS"
sed -i '/browser.urlbar.dnsResolveSingleWordsAfterSearch/d' "$USER_JS"
echo 'user_pref("browser.urlbar.dnsResolveSingleWordsAfterSearch", 0);' >> "$USER_JS"
exec "$LIB_DIR/firefox" --name "seafari" --class "seafari" --profile "$PROFILE_DIR" -no-remote "$@"
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
StartupWMClass=seafari
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
        -p "seafari-${VERSION}-1.${RPM_ARCH}.rpm" \
        --description "Seafari - Safari styled browser" \
        --category "Network" \
        --license "MPL 2.0" \
        "$DEB_ROOT/usr/bin/seafari"=/usr/bin/seafari \
        "$DEB_ROOT/usr/lib/seafari/"=/usr/lib/seafari \
        "$DEB_ROOT/usr/share/applications/seafari.desktop"=/usr/share/applications/seafari.desktop \
        "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps/seafari.png"=/usr/share/icons/hicolor/scalable/apps/seafari.png || true

    # Arch Linux (pacman) Packaging
    fpm -s dir -t pacman -n seafari -v $VERSION -a $RPM_ARCH \
        -p "seafari-${VERSION}-1-${RPM_ARCH}.pkg.tar.zst" \
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
