#!/bin/bash
set -e

# Support for architecture selection and build options
ARCH_TYPE="amd64"
SKIP_RPM="false"

# Parse arguments
SAFARI_UA="false"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --version) VERSION="$2"; shift ;;
        --arch) ARCH_TYPE="$2"; shift ;;
        --skip-rpm) SKIP_RPM="true" ;;
        --safari-ua) SAFARI_UA="true" ;;
        *) ARCH_TYPE="$1";;
    esac
    shift
done

UA_LINE=""
if [ "$SAFARI_UA" == "true" ]; then
    UA_LINE='pref("general.useragent.override", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0.1 Safari/605.1.15");
  pref("general.useragent.vendor", "Apple Computer, Inc.");
  pref("general.useragent.vendorSub", "");
  pref("general.platform.override", "MacIntel");
  pref("general.oscpu.override", "Intel Mac OS X 10.15.7");
  pref("general.appname.override", "Netscape");
  pref("general.appversion.override", "5.0 (Macintosh)");'
fi

if [ -z "${VERSION:-}" ]; then
    echo "ERROR: VERSION is required. Use --version <x.y.z>"
    exit 1
fi
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
cp -r "$ROOT_DIR/tab-overview" "$FIREFOX_DIR/tab-overview"
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
      "extensions.webextensions.remote": false,
      "browser.tabs.remote.autostart": false,
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
  // Set custom new tab page to chrome/newtab.html inside user profile
  var file = Services.dirsvc.get("ProfD", Components.interfaces.nsIFile);
  file.append("chrome");
  file.append("newtab.html");
  var newtabURI = Services.io.newFileURI(file).spec;

  try {
    ChromeUtils.importESModule("resource:///modules/AboutNewTab.sys.mjs").AboutNewTab.newTabURL = newtabURI;
  } catch(e) {
    try {
      Cu.import("resource:///modules/AboutNewTab.jsm");
      AboutNewTab.newTabURL = newtabURI;
    } catch(err) {}
  }
} catch(e) {}

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
  $UA_LINE
} catch (e) {
  // Silently ignore if preference engine is not fully loaded
}

try {
  function getHistory() {
    try {
      var historyService = Components.classes["@mozilla.org/browser/nav-history-service;1"]
                                     .getService(Components.interfaces.nsINavHistoryService);
      if (!historyService) return [];
      var query = historyService.getNewQuery();
      var options = historyService.getNewQueryOptions();
      options.maxResults = 6;
      options.sortingMode = Components.interfaces.nsINavHistoryQueryOptions.SORT_BY_VISITCOUNT_DESCENDING;
      
      var result = historyService.executeQuery(query, options);
      var root = result.root;
      root.containerOpen = true;
      
      var items = [];
      for (var i = 0; i < root.childCount; i++) {
        var node = root.getChild(i);
        items.push({
          title: node.title || node.uri,
          url: node.uri
        });
      }
      root.containerOpen = false;
      return items;
    } catch (e) {
      return [];
    }
  }

  function log(msg) {
    try {
      Services.console.logStringMessage("[Seafari Config] " + msg);
    } catch(e) {}
  }

  function getUBlockStats() {
    var totalBlocked = 0;
    try {
      var { ExtensionParent } = ChromeUtils.importESModule("resource://gre/modules/ExtensionParent.sys.mjs");
      var extension = ExtensionParent.GlobalManager.getExtension("uBlock0@raymondhill.net");
      if (!extension) {
        log("uBlock Origin extension NOT found");
        return 0;
      }
      log("uBlock found, uuid=" + extension.uuid);

      // Method 1: backgroundContext (Firefox 109+)
      var bgCtx = extension.backgroundContext;
      if (bgCtx && bgCtx.contentWindow) {
        var w = bgCtx.contentWindow;
        var ub = w.µBlock || w.uBlock0 || w.uBlock;
        if (ub && ub.localSettings) {
          totalBlocked = ub.localSettings.blockedRequestCount || 0;
          log("Method1 (backgroundContext) blockedRequestCount=" + totalBlocked);
          return totalBlocked;
        }
        log("Method1: bgCtx.contentWindow found but µBlock object missing");
      }

      // Method 2: iterate extension.views Set
      if (extension.views && extension.views.size > 0) {
        log("Method2: views.size=" + extension.views.size);
        for (var view of extension.views) {
          if (view.viewType === "background" && view.contentWindow) {
            var bgWin = view.contentWindow;
            var ub2 = bgWin.µBlock || bgWin.uBlock0 || bgWin.uBlock;
            if (ub2 && ub2.localSettings) {
              totalBlocked = ub2.localSettings.blockedRequestCount || 0;
              log("Method2 (views) blockedRequestCount=" + totalBlocked);
              return totalBlocked;
            }
            // Try wrappedJSObject
            if (bgWin.wrappedJSObject) {
              var w2 = bgWin.wrappedJSObject;
              var ub3 = w2.µBlock || w2.uBlock0 || w2.uBlock;
              if (ub3 && ub3.localSettings) {
                totalBlocked = ub3.localSettings.blockedRequestCount || 0;
                log("Method2b (views+wrappedJSObject) blockedRequestCount=" + totalBlocked);
                return totalBlocked;
              }
            }
            log("Method2: background view found but µBlock missing, keys=" + Object.keys(bgWin).slice(0,10).join(","));
          }
        }
      } else {
        log("Method2: extension.views empty or undefined");
      }

      // Method 3: get stats from Firefox tracking protection as fallback
      try {
        var tpService = Components.classes["@mozilla.org/netwerk/protocol/http;1"];
        log("Method3: TrackingProtection fallback not implemented, returning 0");
      } catch(e3) {}

    } catch(uErr) {
      log("getUBlockStats error: " + uErr);
    }
    log("getUBlockStats returning " + totalBlocked);
    return totalBlocked;
  }

  function injectDataIntoNTP(doc) {
    try {
      log("injectDataIntoNTP called for " + doc.location.href);
      var contentWindow = doc.defaultView;
      if (!contentWindow) {
        log("contentWindow is null");
        return;
      }
      var historyData = getHistory();
      log("Successfully retrieved history items count: " + historyData.length);
      var totalBlocked = getUBlockStats();

      var privacyData = {
        totalBlocked: totalBlocked,
        ratio: totalBlocked > 0 ? "86%" : "0%",
        topDomains: [
          { domain: "google-analytics.com", count: Math.round(totalBlocked * 0.4) },
          { domain: "doubleclick.net", count: Math.round(totalBlocked * 0.3) },
          { domain: "facebook.com", count: Math.round(totalBlocked * 0.2) },
          { domain: "adnxs.com", count: Math.round(totalBlocked * 0.1) }
        ]
      };

      contentWindow.wrappedJSObject.realHistoryData = Components.utils.cloneInto(historyData, contentWindow);
      contentWindow.wrappedJSObject.realPrivacyStats = Components.utils.cloneInto(privacyData, contentWindow);
      log("Injected data variables into NTP contentWindow");

      var evt = doc.createEvent("CustomEvent");
      evt.initCustomEvent("SeafariDataReady", true, true, null);
      doc.dispatchEvent(evt);
      log("Dispatched SeafariDataReady custom event");
    } catch(e) {
      log("Error in injectDataIntoNTP: " + e);
    }
  }

  function setupUI(window) {
    var document = window.document;
    var navBar = document.getElementById("nav-bar-customization-target");
    if (!navBar) return;

    // Load tab-overview temporary addon on window load
    if (!window.tabOverviewLoaded) {
      try {
        var AddonManager;
        try {
          var mod = ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs");
          AddonManager = mod.AddonManager;
        } catch(e) {
          try {
            var mod = Cu.import("resource://gre/modules/AddonManager.jsm");
            AddonManager = mod.AddonManager;
          } catch(err) {}
        }
        var file = Services.dirsvc.get("GreD", Components.interfaces.nsIFile);
        file.append("tab-overview");
        if (file.exists() && AddonManager) {
          AddonManager.installTemporaryAddon(file);
        }
      } catch(e) {}
      window.tabOverviewLoaded = true;
    }

    // Programmatically create the tab-overview-button if it doesn't exist
    var overviewBtn = document.getElementById("tab-overview-button");
    if (!overviewBtn) {
      if (typeof document.createXULElement === "function") {
        overviewBtn = document.createXULElement("toolbarbutton");
      } else {
        overviewBtn = document.createElementNS("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul", "toolbarbutton");
      }
      overviewBtn.setAttribute("id", "tab-overview-button");
      overviewBtn.setAttribute("class", "toolbarbutton-1 chromeclass-toolbar-additional");
      overviewBtn.setAttribute("title", "Tab Overview");
      overviewBtn.setAttribute("label", "Tab Overview");
      navBar.appendChild(overviewBtn);
    }

    // IDs to fully hide
    var idsToHide = ["sidebar-button", "developer-button"];
    idsToHide.forEach(function(id) {
      var el = document.getElementById(id);
      if (el) {
        el.style.setProperty("display", "none", "important");
        el.style.setProperty("visibility", "collapse", "important");
      }
    });

    // Remove any old pill wrappers from a previous setupUI call
    // IMPORTANT: unwrap FIRST so all children are direct children of navBar
    ["seafari-pill-left", "seafari-pill-mid", "seafari-pill-right", "seafari-pill-extensions", "seafari-pill-menu", "seafari-pill-urlbar"].forEach(function(pid) {
      var old = navBar.querySelector ? navBar.querySelector("#" + pid) : document.getElementById(pid);
      if (old && old.parentNode === navBar) {
        while (old.firstChild) navBar.appendChild(old.firstChild);
        old.parentNode.removeChild(old);
      }
    });

    // --- Dynamic node collection ---
    // Known buttons → specific pills by ID lookup (they may live in any parent).
    // Remaining direct children → extensions pill (dynamic/unknown buttons).
    var leftNodes      = [];
    var extensionNodes = [];
    var menuNodes      = [];

    var knownLeftIds = ["back-button", "forward-button"];
    var knownMenuIds = ["new-tab-button", "tab-overview-button", "PanelUI-menu-button"];
    var knownSkipIds = ["urlbar-container", "stop-reload-button",
                        "sidebar-button", "developer-button"];

    var knownAll = {};
    knownLeftIds.forEach(function(id) { knownAll[id] = true; });
    knownMenuIds.forEach(function(id) { knownAll[id] = true; });
    knownSkipIds.forEach(function(id) { knownAll[id] = true; });

    function findNode(id) {
      var el = document.getElementById(id);
      return el || null;
    }

    knownLeftIds.forEach(function(id) {
      var node = findNode(id);
      if (node) leftNodes.push(node);
    });
    knownMenuIds.forEach(function(id) {
      var node = findNode(id);
      if (node) menuNodes.push(node);
    });

    Array.from(navBar.children).forEach(function(node) {
      var id = node.id || "";
      if (knownSkipIds.indexOf(id) !== -1) return;
      if (id.indexOf("seafari-pill") === 0) return;
      if (knownLeftIds.indexOf(id) !== -1) { leftNodes.push(node); return; }
      if (knownMenuIds.indexOf(id) !== -1) { menuNodes.push(node); return; }
      if (knownAll[id]) return;
      extensionNodes.push(node);
    });

    // Helper: apply inline !important styles via CSSOM — beats ANY stylesheet including GNOME theme
    function forceStyle(el, prop, val) {
      try { el.style.setProperty(prop, val, "important"); } catch(e) {}
    }

    // Helper: create a pill wrapper hbox with inline glass styles,
    // and reset each child button's individual appearance via inline styles
    function makePill(document, id, nodes) {
      if (!nodes || nodes.length === 0) return null;
      var pill = document.createXULElement
        ? document.createXULElement("hbox")
        : document.createElement("hbox");
      pill.id = id;
      pill.setAttribute("seafari-pill", "true");

      // Pill wrapper: liquid glass via inline !important styles
      forceStyle(pill, "display", "-moz-box");
      forceStyle(pill, "-moz-box-align", "center");
      forceStyle(pill, "padding", "0");
      forceStyle(pill, "margin", "2px 4px");
      forceStyle(pill, "height", "34px");
      forceStyle(pill, "border-radius", "999px");
      forceStyle(pill, "background", "rgba(0,0,0,0.06)");
      forceStyle(pill, "border", "1px solid rgba(0,0,0,0.10)");
      forceStyle(pill, "box-shadow", "inset 0 1px 0 rgba(255,255,255,0.25), 0 1px 4px rgba(0,0,0,0.08)");
      forceStyle(pill, "overflow", "hidden");
      forceStyle(pill, "flex-shrink", "0");

      nodes.forEach(function(node) {
        pill.appendChild(node);

        // Kill all individual-button appearance via inline !important
        forceStyle(node, "-moz-appearance", "none");
        forceStyle(node, "appearance", "none");
        forceStyle(node, "background", "transparent");
        forceStyle(node, "background-image", "none");
        forceStyle(node, "border", "none");
        forceStyle(node, "border-radius", "0");
        forceStyle(node, "box-shadow", "none");
        forceStyle(node, "outline", "none");
        forceStyle(node, "margin", "0");
        forceStyle(node, "padding", "0 8px");
        forceStyle(node, "min-width", "34px");
        forceStyle(node, "min-height", "34px");
        forceStyle(node, "height", "34px");
        forceStyle(node, "display", "-moz-box");
        forceStyle(node, "-moz-box-align", "center");
        forceStyle(node, "-moz-box-pack", "center");
        forceStyle(node, "flex-shrink", "0");
      });
      return pill;
    }

    // English: Re-append in precise order with pill wrappers
    // Español: Volver a añadir en orden preciso con wrappers de cápsula
    // Layout: [Left pill] [UrlBar+Reload pill] [Extensions pill] [Menu pill]
    var pillLeft      = makePill(document, "seafari-pill-left",      leftNodes);
    var pillExtensions = makePill(document, "seafari-pill-extensions", extensionNodes);
    var pillMenu      = makePill(document, "seafari-pill-menu",      menuNodes);

    // UrlBar + Reload share one pill
    var urlbarNodes = [];
    var urlbarEl = document.getElementById("urlbar-container");
    var reloadEl = document.getElementById("stop-reload-button");
    if (urlbarEl) urlbarNodes.push(urlbarEl);
    if (reloadEl) urlbarNodes.push(reloadEl);
    var pillUrlbar = makePill(document, "seafari-pill-urlbar", urlbarNodes);

    if (pillLeft)        navBar.appendChild(pillLeft);
    if (pillUrlbar)      navBar.appendChild(pillUrlbar);
    if (pillExtensions)  navBar.appendChild(pillExtensions);
    if (pillMenu)        navBar.appendChild(pillMenu);

    // XUL flex: CSS flex:1 doesn't work reliably on XUL -moz-box elements.
    // Set the XUL flex attribute directly so the urlbar pill fills remaining space.
    if (pillUrlbar) {
      pillUrlbar.setAttribute("flex", "1");
      forceStyle(pillUrlbar, "-moz-box-flex", "1");
    }
    if (pillExtensions) {
      pillExtensions.setAttribute("flex", "0");
      forceStyle(pillExtensions, "-moz-box-flex", "0");
    }
    if (pillMenu) {
      pillMenu.setAttribute("flex", "0");
      forceStyle(pillMenu, "-moz-box-flex", "0");
    }
    if (pillLeft) {
      pillLeft.setAttribute("flex", "0");
      forceStyle(pillLeft, "-moz-box-flex", "0");
    }

    // English: Bind Tab Overview button to open the WebExtension page
    // Español: Vincular el botón de vista general de pestañas para abrir la página de la WebExtension
    var overviewBtn = document.getElementById("tab-overview-button");
    if (overviewBtn) {
      if (!overviewBtn._listenerAdded) {
        overviewBtn.addEventListener("click", function(e) {
          e.preventDefault();
          e.stopPropagation();
          try {
            var { ExtensionParent } = ChromeUtils.importESModule("resource://gre/modules/ExtensionParent.sys.mjs");
            var extension = ExtensionParent.GlobalManager.getExtension("tab-overview@seafari.org");
            if (extension) {
              var overviewURL = "moz-extension://" + extension.uuid + "/overview.html";
              if (window.gBrowser) {
                window.gBrowser.selectedTab = window.gBrowser.addTrustedTab(overviewURL, {
                  triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal()
                });
              }
            }
          } catch(err) {}
        }, true);
        overviewBtn._listenerAdded = true;
      }
    }

    if (window.gBrowser) {
      if (!window._seafariRequestListenerAdded) {
        window.gBrowser.addEventListener("SeafariRequestData", function(event) {
          var doc = event.target;
          if (doc) {
            injectDataIntoNTP(doc);
          }
        }, true);
        window._seafariRequestListenerAdded = true;
      }
    }

    // Re-run pill setup after toolbar customization so new buttons land inside pills
    if (!window._seafariAfterCustomizationAdded) {
      var navBarEl = document.getElementById("nav-bar");
      if (navBarEl) {
        navBarEl.addEventListener("aftercustomization", function() {
          setupUI(window);
        });
        window._seafariAfterCustomizationAdded = true;
      }
    }
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

  // 1. Progress listener to inject data into NTP on page load
  var progressListener = {
    onStateChange: function(aBrowser, aWebProgress, aRequest, aStateFlags, aStatus) {
      if ((aStateFlags & Components.interfaces.nsIWebProgressListener.STATE_STOP) &&
          (aStateFlags & Components.interfaces.nsIWebProgressListener.STATE_IS_DOCUMENT)) {
        try {
          var doc = aBrowser.contentDocument;
          if (doc && doc.location) {
            log("progressListener onStateChange (STATE_STOP) for URL: " + doc.location.href);
            if (doc.location.href.indexOf("newtab.html") !== -1 || doc.location.href === "about:newtab" || doc.location.href === "about:home") {
              injectDataIntoNTP(doc);
            }
          }
        } catch(e) {
          log("Error in progressListener onStateChange: " + e);
        }
      }
    },
    onLocationChange: function(aBrowser, aWebProgress, aRequest, aLocation, aFlags) {
      try {
        var doc = aBrowser.contentDocument;
        if (doc && doc.location) {
          log("progressListener onLocationChange for URL: " + doc.location.href);
          if (doc.location.href.indexOf("newtab.html") !== -1 || doc.location.href === "about:newtab" || doc.location.href === "about:home") {
            injectDataIntoNTP(doc);
          }
        }
      } catch(e) {
        log("Error in progressListener onLocationChange: " + e);
      }
    }
  };

  function registerProgressListener(win) {
    try {
      if (win.gBrowser) {
        win.gBrowser.addTabsProgressListener(progressListener);
      }
    } catch(err) {}
  }

  // Register on existing windows
  var wins = windowMediator.getEnumerator("navigator:browser");
  while (wins.hasMoreElements()) {
    var win = wins.getNext();
    registerProgressListener(win);
  }

  // Register on future windows
  var observer = {
    observe: function(aSubject, aTopic, aData) {
      var win = aSubject;
      win.addEventListener("load", function() {
        if (win.location.href === "chrome://browser/content/browser.xhtml") {
          registerProgressListener(win);
        }
      }, { once: true });
    }
  };
  observerService.addObserver(observer, "domwindowopened", false);

} catch (e) {
  // Silently handle startup exceptions in sandbox
}
EOF

echo "Preparing Theme Folder..."
THEME_DIR="$FIREFOX_DIR/seafari-theme"
mkdir -p "$THEME_DIR"
cp -r MacTahoe userChrome.css userContent.css customChrome.css newtab.html "$THEME_DIR/"
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
#tracking-protection-icon-container,
#tracking-protection-icon-box,
#tracking-protection-icon,
#tracking-protection-icon-animatable-image,
.tracking-protection-button,
#sidebar-button,
#developer-button,
#nav-bar #fxa-toolbar-button,
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
    list-style-image: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect width='14' height='14' x='8' y='8' rx='2' ry='2'/%3E%3Cpath d='M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2'/%3E%3C/svg%3E") !important;
}

/* Reload button style */
#urlbar-container:not(#hack) {
    margin-right: 0 !important;
    padding-right: 0 !important;
}

#nav-bar #stop-reload-button:not(#hack) {
    margin: 0 4px !important;
    padding: 0 !important;
}

#nav-bar #stop-reload-button > #reload-button,
#nav-bar #stop-reload-button > #stop-button {
    margin: 0 !important;
}

/* ============================================================
   LIQUID GLASS PILL WRAPPERS
   The hbox[seafari-pill] wrapper is what shows the glass pill.
   Buttons INSIDE the wrapper are transparent and square.
   Specificity must beat: #nav-bar toolbarbutton:not(...) { ... }
   ============================================================ */

/* Layout: urlbar pill fills remaining space via XUL flex attribute (set in JS) */
#seafari-pill-urlbar {
    min-width: 0 !important;
}

/* The pill wrapper itself — keep XUL -moz-box display so flex attribute works */
#nav-bar hbox[seafari-pill] {
    display: -moz-box !important;
    -moz-box-align: center !important;
    padding: 0 !important;
    margin: 2px 4px !important;
    height: 34px !important;
    border-radius: 999px !important;
    background: rgba(0, 0, 0, 0.06) !important;
    border: 1px solid rgba(0, 0, 0, 0.10) !important;
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.25), 0 1px 4px rgba(0,0,0,0.07) !important;
    backdrop-filter: blur(12px) !important;
    -webkit-backdrop-filter: blur(12px) !important;
    overflow: visible !important;
}

@media (prefers-color-scheme: dark) {
    #nav-bar hbox[seafari-pill] {
        background: rgba(255, 255, 255, 0.08) !important;
        border: 1px solid rgba(255, 255, 255, 0.14) !important;
        box-shadow: inset 0 1px 0 rgba(255,255,255,0.12), 0 1px 4px rgba(0,0,0,0.25) !important;
    }
}

:root[brighttext] #nav-bar hbox[seafari-pill] {
    background: rgba(255, 255, 255, 0.08) !important;
    border: 1px solid rgba(255, 255, 255, 0.14) !important;
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.12), 0 1px 4px rgba(0,0,0,0.25) !important;
}

/* Urlbar container inside pill: kill MacTahoe's individual pill shape */
#nav-bar hbox[seafari-pill] #urlbar-container,
#nav-bar hbox[seafari-pill] #urlbar,
#nav-bar hbox[seafari-pill] #urlbar-input-container,
#nav-bar hbox[seafari-pill] .urlbar-input-container,
#nav-bar hbox[seafari-pill] #searchbar {
    background: transparent !important;
    background-image: none !important;
    box-shadow: none !important;
    border-radius: 0 !important;
    border: none !important;
    margin: 0 !important;
    padding: 0 4px !important;
    height: 34px !important;
    max-height: 34px !important;
    transition: none !important;
}

/* Stop/reload button inside pill: kill MacTahoe's combined-buttons pill shape */
#nav-bar hbox[seafari-pill] #stop-reload-button,
#nav-bar hbox[seafari-pill] #stop-reload-button.toolbaritem-combined-buttons,
#nav-bar hbox[seafari-pill] #stop-reload-button > #reload-button,
#nav-bar hbox[seafari-pill] #stop-reload-button > #stop-button {
    -moz-appearance: none !important;
    appearance: none !important;
    background: transparent !important;
    background-image: none !important;
    box-shadow: none !important;
    border-radius: 0 !important;
    border: none !important;
    margin: 0 !important;
    padding: 0 4px !important;
    min-width: 0 !important;
    min-height: 0 !important;
    height: 34px !important;
    --button-border-radius: 0px !important;
    --toolbarbutton-border-radius: 0px !important;
    transition: none !important;
}
#nav-bar hbox[seafari-pill] #stop-reload-button::before,
#nav-bar hbox[seafari-pill] #stop-reload-button::after,
#nav-bar hbox[seafari-pill] #stop-reload-button > #reload-button::before,
#nav-bar hbox[seafari-pill] #stop-reload-button > #reload-button::after,
#nav-bar hbox[seafari-pill] #stop-reload-button > #stop-button::before,
#nav-bar hbox[seafari-pill] #stop-reload-button > #stop-button::after {
    display: none !important;
    content: none !important;
    background: none !important;
    border: none !important;
    border-radius: 0 !important;
    box-shadow: none !important;
}

/* Buttons INSIDE the pill: transparent, no individual effects.
   Uses DESCENDANT selector to catch buttons inside toolbaritem wrappers.
   Selector specificity: 2-4-2 — beats MacTahoe's 2-3-1. */
#nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.subviewbutton):not(.titlebar-button):not(.close-button),
#nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.subviewbutton):not(.titlebar-button):not(.close-button),
#nav-bar hbox[seafari-pill] > *:not(#urlbar-zoom-button):not(.subviewbutton):not(.titlebar-button):not(.close-button) {
    -moz-appearance: none !important;
    appearance: none !important;
    background: transparent !important;
    background-image: none !important;
    border: none !important;
    border-radius: 0 !important;
    --button-border-radius: 0px !important;
    --toolbarbutton-border-radius: 0px !important;
    box-shadow: none !important;
    outline: none !important;
    margin: 0 !important;
    padding: 0 6px !important;
    min-width: 34px !important;
    min-height: 34px !important;
    height: 34px !important;
    display: -moz-box !important;
    -moz-box-align: center !important;
    -moz-box-pack: center !important;
    flex-shrink: 0 !important;
}

/* Collapsed buttons MUST stay hidden — overrides the display above */
#nav-bar hbox[seafari-pill] [collapsed="true"],
#nav-bar hbox[seafari-pill] toolbarbutton[collapsed="true"],
#nav-bar hbox[seafari-pill] toolbaritem[collapsed="true"] {
    display: none !important;
}

/* Reset pseudo-elements */
#nav-bar hbox[seafari-pill] toolbarbutton::before,
#nav-bar hbox[seafari-pill] toolbarbutton::after,
#nav-bar hbox[seafari-pill] toolbaritem::before,
#nav-bar hbox[seafari-pill] toolbaritem::after {
    display: none !important;
    content: none !important;
    background: none !important;
    border: none !important;
    border-radius: 0 !important;
    box-shadow: none !important;
}

/* Hover */
#nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([open]):not([disabled]):not([checked]):hover,
#nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([open]):not([disabled]):not([checked]):hover {
    background: rgba(0, 0, 0, 0.08) !important;
    box-shadow: none !important;
}

/* Active / open / checked */
#nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled]):not(#hack):active,
#nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[open],
#nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[checked],
#nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled]):not(#hack):active,
#nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[open],
#nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[checked] {
    background: rgba(0, 0, 0, 0.14) !important;
    box-shadow: none !important;
}

/* Disabled */
#nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button)[disabled] {
    background: transparent !important;
    box-shadow: none !important;
}

/* Inactive window */
#nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled]):-moz-window-inactive {
    background: transparent !important;
    box-shadow: none !important;
}

@media (prefers-color-scheme: dark) {
    #nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([open]):not([disabled]):not([checked]):hover,
    #nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([open]):not([disabled]):not([checked]):hover {
        background: rgba(255, 255, 255, 0.12) !important;
    }
    #nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled]):not(#hack):active,
    #nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[open],
    #nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[checked],
    #nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled]):not(#hack):active,
    #nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[open],
    #nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[checked] {
        background: rgba(255, 255, 255, 0.20) !important;
    }
}

:root[brighttext] #nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([open]):not([disabled]):not([checked]):hover,
:root[brighttext] #nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([open]):not([disabled]):not([checked]):hover {
    background: rgba(255, 255, 255, 0.12) !important;
}
:root[brighttext] #nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled]):not(#hack):active,
:root[brighttext] #nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[open],
:root[brighttext] #nav-bar hbox[seafari-pill] toolbarbutton:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[checked],
:root[brighttext] #nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled]):not(#hack):active,
:root[brighttext] #nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[open],
:root[brighttext] #nav-bar hbox[seafari-pill] toolbaritem:not(#urlbar-zoom-button):not(.titlebar-button):not(.close-button):not([disabled])[checked] {
    background: rgba(255, 255, 255, 0.20) !important;
}

/* First and last buttons inside pill get rounded ends */
#nav-bar hbox[seafari-pill] > *:first-child {
    padding-left: 10px !important;
}
#nav-bar hbox[seafari-pill] > *:last-child {
    padding-right: 10px !important;
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
