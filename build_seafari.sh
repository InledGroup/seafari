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

check_tarball() {
    local file="$1"
    if [ -f "$file" ] && [ -s "$file" ]; then
        if tar -tf "$file" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

check_xpi() {
    local file="$1"
    if [ -f "$file" ] && [ -s "$file" ]; then
        if unzip -tq "$file" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

if ! check_tarball "$CACHE_DIR/firefox.tar.xz"; then
    echo "Downloading fresh Seafari base ($ARCH_TYPE)..."
    rm -f "$CACHE_DIR/firefox.tar.xz" "$CACHE_DIR/firefox.tar.xz.tmp"
    wget -L -O "$CACHE_DIR/firefox.tar.xz.tmp" "$FF_URL"
    if check_tarball "$CACHE_DIR/firefox.tar.xz.tmp"; then
        mv "$CACHE_DIR/firefox.tar.xz.tmp" "$CACHE_DIR/firefox.tar.xz"
    else
        echo "ERROR: Downloaded Seafari base tarball is corrupt or incomplete!"
        rm -f "$CACHE_DIR/firefox.tar.xz.tmp"
        exit 1
    fi
else
    echo "Using cached Seafari base tarball from $CACHE_DIR/firefox.tar.xz"
fi

if ! check_xpi "$CACHE_DIR/ublock_origin.xpi"; then
    echo "Downloading uBlock Origin..."
    rm -f "$CACHE_DIR/ublock_origin.xpi"
    wget -O "$CACHE_DIR/ublock_origin.xpi" "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
fi

if ! check_xpi "$CACHE_DIR/adaptive_tab_bar_colour.xpi"; then
    echo "Downloading Adaptive Tab Bar Colour..."
    rm -f "$CACHE_DIR/adaptive_tab_bar_colour.xpi"
    wget -O "$CACHE_DIR/adaptive_tab_bar_colour.xpi" "https://addons.mozilla.org/firefox/downloads/file/4704834/adaptive_tab_bar_colour-3.3.2.xpi"
fi

cp "$CACHE_DIR/firefox.tar.xz" "$WORKSPACE/firefox.tar.xz"
cp "$CACHE_DIR/ublock_origin.xpi" "$WORKSPACE/ublock_origin.xpi"
cp "$CACHE_DIR/adaptive_tab_bar_colour.xpi" "$WORKSPACE/adaptive_tab_bar_colour.xpi"

# Patch uBlock Origin to allow external messaging
echo "Patching uBlock Origin XPI to allow external messaging..."
mkdir -p "$WORKSPACE/ublock_temp"
unzip -q "$WORKSPACE/ublock_origin.xpi" -d "$WORKSPACE/ublock_temp"

python3 -c '
import json
import os
manifest_path = "'"$ROOT_DIR/$WORKSPACE"'/ublock_temp/manifest.json"
if os.path.exists(manifest_path):
    with open(manifest_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    data["externally_connectable"] = {
        "ids": ["tab-overview@seafari.org"]
    }
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
'

# Append our custom message listener to js/background.js
cat <<'EOF' >> "$WORKSPACE/ublock_temp/js/background.js"

// Seafari NTP integration listener
if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.onMessageExternal) {
  browser.runtime.onMessageExternal.addListener((message, sender, sendResponse) => {
    if (sender.id === "tab-overview@seafari.org") {
      if (message && message.action === "getUblockStats") {
        var totalBlocked = 0;
        try {
          var ub = typeof µBlock !== 'undefined' ? µBlock : (typeof µb !== 'undefined' ? µb : (typeof uBlock0 !== 'undefined' ? uBlock0 : (typeof uBlock !== 'undefined' ? uBlock : null)));
          if (ub) {
            if (ub.requestStats && typeof ub.requestStats.blockedCount === "number") {
              totalBlocked = ub.requestStats.blockedCount;
            } else if (ub.stats && typeof ub.stats.blocked === "number") {
              totalBlocked = ub.stats.blocked;
            } else if (ub.localSettings && typeof ub.localSettings.blockedRequestCount === "number") {
              totalBlocked = ub.localSettings.blockedRequestCount;
            } else if (typeof ub.blockedRequestCount === "number") {
              totalBlocked = ub.blockedRequestCount;
            }
          }
        } catch(e) {
          totalBlocked = -1;
        }
        sendResponse({ totalBlocked: totalBlocked });
        return true;
      }
    }
    return false;
  });
}
EOF

# Repack uBlock Origin
rm -f "$WORKSPACE/ublock_origin.xpi"
(cd "$WORKSPACE/ublock_temp" && zip -q -r "$ROOT_DIR/$WORKSPACE/ublock_origin.xpi" .)
rm -rf "$WORKSPACE/ublock_temp"

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
      "ATBC@EasonWong": {
        "installation_mode": "normal_installed",
        "install_url": "file:///usr/lib/seafari/distribution/extensions/ATBC@EasonWong.xpi"
      },
      "uBlock0@raymondhill.net": {
        "installation_mode": "normal_installed",
        "install_url": "file:///usr/lib/seafari/distribution/extensions/uBlock0@raymondhill.net.xpi"
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
      "browser.startup.page": 1,
      "browser.startup.homepage_override.mstone": "ignore",
      "browser.newtabpage.enabled": true,
      "browser.newtabpage.url": "about:newtab",
      "browser.newtabpage.activity-stream.enabled": false,
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
var Services = typeof Services !== "undefined" ? Services : (typeof globalThis !== "undefined" ? globalThis.Services : null);
var ChromeUtils = typeof ChromeUtils !== "undefined" ? ChromeUtils : (typeof globalThis !== "undefined" ? globalThis.ChromeUtils : null);
var logFile = null;
function log(msg) {
  try {
    try {
      dump("[Seafari Config] " + msg + "\n");
    } catch(e) {}
    try {
      Components.classes["@mozilla.org/consoleservice;1"]
                .getService(Components.interfaces.nsIConsoleService)
                .logStringMessage("[Seafari Config] " + msg);
    } catch(e) {}
    if (!logFile) {
      logFile = Components.classes["@mozilla.org/file/directory_service;1"]
                           .getService(Components.interfaces.nsIProperties)
                           .get("ProfD", Components.interfaces.nsIFile);
      logFile.append("seafari-debug.log");
    }
    var fos = Components.classes["@mozilla.org/file/output-stream;1"]
                        .createInstance(Components.interfaces.nsIFileOutputStream);
    fos.init(logFile, 0x02 | 0x08 | 0x10, 438, 0); // write, create, append (438 is decimal for octal 0666)
    var converter = Components.classes["@mozilla.org/intl/converter-output-stream;1"]
                              .createInstance(Components.interfaces.nsIConverterOutputStream);
    converter.init(fos, "UTF-8", 0, 0);
    converter.writeString("[" + new Date().toISOString() + "] " + msg + "\n");
    converter.close();
  } catch(e) {}
}

log("Seafari Autoconfig initialization started");

try {
  // Set custom new tab page to chrome/newtab.html inside user profile
  var file = Components.classes["@mozilla.org/file/directory_service;1"]
                       .getService(Components.interfaces.nsIProperties)
                       .get("ProfD", Components.interfaces.nsIFile);
  file.append("chrome");
  file.append("newtab.html");
  var ioService = Components.classes["@mozilla.org/network/io-service;1"]
                            .getService(Components.interfaces.nsIIOService);
  var newtabURI = ioService.newFileURI(file).spec;
  log("New tab URI resolved to: " + newtabURI);

  // Method 1: XPCOM pref branch — most reliable, available very early in startup
  try {
    var prefBranch = Components.classes["@mozilla.org/preferences-service;1"]
                               .getService(Components.interfaces.nsIPrefBranch);
    prefBranch.setCharPref("browser.newtabpage.url", newtabURI);
    log("Set browser.newtabpage.url via nsIPrefBranch");
  } catch(e) {
    log("nsIPrefBranch setCharPref failed: " + e);
  }

  // Method 2: AboutNewTab module — backup approach
  try {
    ChromeUtils.importESModule("resource:///modules/AboutNewTab.sys.mjs").AboutNewTab.newTabURL = newtabURI;
    log("Set AboutNewTab.newTabURL via ESM");
  } catch(e) {
    try {
      var AboutNewTab = Components.utils.import("resource:///modules/AboutNewTab.jsm", {}).AboutNewTab;
      AboutNewTab.newTabURL = newtabURI;
      log("Set AboutNewTab.newTabURL via JSM");
    } catch(err) {
      log("AboutNewTab fallback also failed: " + err);
    }
  }
} catch(e) {
  log("Error in newtab setup: " + e);
}

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
  pref("widget.gtk.global-menu.enabled", true);
  pref("widget.use-xdg-desktop-portal.menubar", true);
  pref("browser.startup.page", 1);
  pref("browser.startup.homepage_override.mstone", "ignore");
  pref("browser.newtabpage.activity-stream.enabled", false);
  pref("browser.dom.window.dump.enabled", true);
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

  // log is defined globally at the top level

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

      function extractCount(ub) {
        if (!ub) return 0;
        if (ub.stats && typeof ub.stats.blocked === "number") return ub.stats.blocked;
        if (ub.localSettings && typeof ub.localSettings.blockedRequestCount === "number") return ub.localSettings.blockedRequestCount;
        if (typeof ub.blockedRequestCount === "number") return ub.blockedRequestCount;
        return 0;
      }

      // Method 1: backgroundContext (Firefox 109+)
      var bgCtx = extension.backgroundContext;
      if (bgCtx && bgCtx.contentWindow) {
        var w = bgCtx.contentWindow;
        var ub = w.µBlock || w.uBlock0 || w.uBlock;
        if (ub) {
          totalBlocked = extractCount(ub);
          if (totalBlocked > 0) return totalBlocked;
        }
        if (w.wrappedJSObject) {
          var wjs = w.wrappedJSObject;
          var ubw = wjs.µBlock || wjs.uBlock0 || wjs.uBlock;
          if (ubw) {
            totalBlocked = extractCount(ubw);
            if (totalBlocked > 0) return totalBlocked;
          }
        }
      }

      // Method 2: iterate extension.views Set
      if (extension.views && extension.views.size > 0) {
        for (var view of extension.views) {
          if (view.viewType === "background" && view.contentWindow) {
            var bgWin = view.contentWindow;
            var ub2 = bgWin.µBlock || bgWin.uBlock0 || bgWin.uBlock;
            if (ub2) {
              totalBlocked = extractCount(ub2);
              if (totalBlocked > 0) return totalBlocked;
            }
            if (bgWin.wrappedJSObject) {
              var w2 = bgWin.wrappedJSObject;
              var ub3 = w2.µBlock || w2.uBlock0 || w2.uBlock;
              if (ub3) {
                totalBlocked = extractCount(ub3);
                if (totalBlocked > 0) return totalBlocked;
              }
            }
          }
        }
      }
    } catch(uErr) {
      log("getUBlockStats error: " + uErr);
    }
    return totalBlocked;
  }

  // ---- User state bridge (newtab <-> profile JSON) ----------------------
  // The newtab page saves its full state (including large background videos,
  // which exceed localStorage quota) via the SeafariSaveData custom event.
  // Chrome persists it to a JSON file in the profile and injects it back on
  // load as realUserState.
  function stateFilePath() {
    var f = Components.classes["@mozilla.org/file/directory_service;1"]
                      .getService(Components.interfaces.nsIProperties)
                      .get("ProfD", Components.interfaces.nsIFile);
    f.append("seafari-state.json");
    return f;
  }

  function readUserState() {
    try {
      var f = stateFilePath();
      if (!f.exists()) return null;
      var fis = Components.classes["@mozilla.org/network/file-input-stream;1"]
                          .createInstance(Components.interfaces.nsIFileInputStream);
      fis.init(f, 0x01, 0, 0); // read-only
      var data = "";
      try {
        var sis = Components.classes["@mozilla.org/scriptableinputstream;1"]
                            .createInstance(Components.interfaces.nsIScriptableInputStream);
        sis.init(fis);
        data = sis.read(sis.available());
        sis.close();
      } finally {
        fis.close();
      }
      return data ? JSON.parse(data) : null;
    } catch(e) {
      log("readUserState error: " + e);
      return null;
    }
  }

  function writeUserState(json) {
    try {
      var f = stateFilePath();
      var fos = Components.classes["@mozilla.org/file/output-stream;1"]
                          .createInstance(Components.interfaces.nsIFileOutputStream);
      // write | create | truncate, mode 0666
      fos.init(f, 0x02 | 0x08 | 0x20, 438, 0);
      var converter = Components.classes["@mozilla.org/intl/converter-output-stream;1"]
                                .createInstance(Components.interfaces.nsIConverterOutputStream);
      converter.init(fos, "UTF-8", 0, 0);
      converter.writeString(json);
      converter.close();
      log("writeUserState: saved " + json.length + " chars");
    } catch(e) {
      log("writeUserState error: " + e);
    }
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

      var userState = readUserState();
      if (userState) {
        contentWindow.wrappedJSObject.realUserState = Components.utils.cloneInto(userState, contentWindow);
        log("Injected realUserState into NTP");
      }

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
    log("setupUI called for window: " + (window.location ? window.location.href : "no-location"));
    var document = window.document;
    var navBar = document.getElementById("nav-bar-customization-target");
    if (!navBar) return;

    function relocateUblockBtn(node) {
      if (!node) return;
      
      // Relocate the entire wrapper node to preserve popup functionality
      var ublockBtn = node;
      
      log("Relocating uBlock button wrapper to URL bar: " + ublockBtn.id);
      
      var identityBox = document.getElementById("identity-box");
      var urlbarContainer = identityBox ? identityBox.parentNode : null;
      if (!urlbarContainer) {
        urlbarContainer = document.querySelector(".urlbar-input-container") || document.getElementById("urlbar-input-container");
      }
      if (urlbarContainer && identityBox) {
        urlbarContainer.insertBefore(ublockBtn, identityBox);
        
        // Ensure it is visible
        ublockBtn.style.removeProperty("display");
        ublockBtn.removeAttribute("hidden");
        
        // Style it inline to fit properly in the URL bar
        forceStyle(ublockBtn, "display", "-moz-inline-box");
        forceStyle(ublockBtn, "visibility", "visible");
        forceStyle(ublockBtn, "margin", "0 4px");
        forceStyle(ublockBtn, "padding", "0");
        forceStyle(ublockBtn, "width", "30px");
        forceStyle(ublockBtn, "height", "30px");
        forceStyle(ublockBtn, "min-width", "30px");
        forceStyle(ublockBtn, "min-height", "30px");
        
        // Ensure the inner button is also visible and styled
        var innerBtn = ublockBtn.querySelector("toolbarbutton") || ublockBtn;
        if (innerBtn !== ublockBtn) {
          innerBtn.style.removeProperty("display");
          innerBtn.removeAttribute("hidden");
          forceStyle(innerBtn, "display", "-moz-box");
          forceStyle(innerBtn, "visibility", "visible");
          forceStyle(innerBtn, "width", "30px");
          forceStyle(innerBtn, "height", "30px");
          forceStyle(innerBtn, "min-width", "30px");
          forceStyle(innerBtn, "min-height", "30px");
        }
        
        // Event listeners
        if (!ublockBtn._seafariListenersAdded) {
          var dragBtn = innerBtn || ublockBtn;
          dragBtn.setAttribute("draggable", "true");
          dragBtn.addEventListener("dragstart", function(event) {
            if (window.gIdentityHandler && typeof window.gIdentityHandler.onDragStart === "function") {
              log("Forwarding dragstart from ublockBtn to gIdentityHandler");
              window.gIdentityHandler.onDragStart(event);
            }
          }, true);
          ublockBtn._seafariListenersAdded = true;
        }
        log("uBlock button wrapper successfully moved and configured");
      }
    }

    // Set up a 10s refresh interval to keep extension ublock stats up to date.
    if (!window._seafariUblockRefreshAdded) {
      function updateUBlockStatsInExtension() {
        try {
          try {
            var childIds = Array.from(navBar.children).map(function(c) {
              return c.tagName + "#" + c.id + " (class: " + c.className + ")";
            }).join(", ");
            log("Navbar children: " + childIds);
          } catch(e) {}
          var totalBlocked = getUBlockStats();
          var privacyData = {
            totalBlocked: totalBlocked,
            ratio: totalBlocked > 0 ? "86%" : "0%",
            topDomains: [
              { domain: "google-analytics.com", count: Math.round(totalBlocked * 0.4) },
              { domain: "doubleclick.net",       count: Math.round(totalBlocked * 0.3) },
              { domain: "facebook.com",          count: Math.round(totalBlocked * 0.2) },
              { domain: "adnxs.com",             count: Math.round(totalBlocked * 0.1) }
            ]
          };
          
          var { ExtensionParent } = ChromeUtils.importESModule("resource://gre/modules/ExtensionParent.sys.mjs");
          var extension = ExtensionParent.GlobalManager.getExtension("tab-overview@seafari.org");
          if (extension && extension.backgroundContext && extension.backgroundContext.contentWindow) {
            var bgWin = extension.backgroundContext.contentWindow;
            if (bgWin.wrappedJSObject) {
              bgWin.wrappedJSObject.ublockStats = privacyData;
            } else {
              bgWin.ublockStats = privacyData;
            }
          }
        } catch(e) { log("updateUBlockStatsInExtension error: " + e); }
      }

      window.setInterval(updateUBlockStatsInExtension, 10000);
      window._seafariUblockRefreshAdded = true;
      // Initial run after a small delay to let extension load
      window.setTimeout(updateUBlockStatsInExtension, 2000);
    }

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
        // Dynamic installation of uBlock Origin
        try {
          var file2 = Services.dirsvc.get("GreD", Components.interfaces.nsIFile);
          file2.append("distribution");
          file2.append("extensions");
          file2.append("uBlock0@raymondhill.net.xpi");
          if (file2.exists() && AddonManager) {
            AddonManager.installTemporaryAddon(file2).then(function(addon) {
              log("uBlock Origin temporary addon installed successfully");
            }).catch(function(e) {
              log("Error installing uBlock Origin: " + e);
            });
          } else {
            log("uBlock Origin xpi file not found at: " + file2.path);
          }
        } catch(e) {
          log("Error loading uBlock Origin: " + e);
        }

        // Dynamic installation of Adaptive Tab Bar Colour (ATBC)
        try {
          var fileATBC = Services.dirsvc.get("GreD", Components.interfaces.nsIFile);
          fileATBC.append("distribution");
          fileATBC.append("extensions");
          fileATBC.append("ATBC@EasonWong.xpi");
          if (fileATBC.exists() && AddonManager) {
            AddonManager.installTemporaryAddon(fileATBC).then(function(addon) {
              log("ATBC temporary addon installed successfully");
            }).catch(function(e) {
              log("Error installing ATBC: " + e);
            });
          } else {
            log("ATBC xpi file not found at: " + fileATBC.path);
          }
        } catch(e) {
          log("Error loading ATBC: " + e);
        }

        var file = Services.dirsvc.get("GreD", Components.interfaces.nsIFile);
        file.append("tab-overview");
        if (file.exists() && AddonManager) {
          AddonManager.installTemporaryAddon(file).then(function(addon) {
            log("tab-overview temporary addon installed successfully");
            try {
              var { ExtensionParent } = ChromeUtils.importESModule("resource://gre/modules/ExtensionParent.sys.mjs");
              var extension = ExtensionParent.GlobalManager.getExtension("tab-overview@seafari.org");
              if (extension) {
                var extNewtabURI = "moz-extension://" + extension.uuid + "/newtab.html";
                log("Updating newtab URL to extension: " + extNewtabURI);
                resolvedExtNewtabURL = extNewtabURI;
                // Method 1: XPCOM pref
                try {
                  var prefBranch = Components.classes["@mozilla.org/preferences-service;1"]
                                             .getService(Components.interfaces.nsIPrefBranch);
                  prefBranch.setCharPref("browser.newtabpage.url", extNewtabURI);
                } catch(e) {}
                // Method 2: AboutNewTab module
                try {
                  ChromeUtils.importESModule("resource:///modules/AboutNewTab.sys.mjs").AboutNewTab.newTabURL = extNewtabURI;
                } catch(e) {
                  try {
                    Cu.import("resource:///modules/AboutNewTab.jsm");
                    AboutNewTab.newTabURL = extNewtabURI;
                  } catch(err) {}
                }

                // Redirect any already open about:newtab/about:home tabs to the extension's newtab page
                try {
                  var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                                     .getService(Components.interfaces.nsIWindowMediator);
                  var enumerator = wm.getEnumerator("navigator:browser");
                  while (enumerator.hasMoreElements()) {
                    var win = enumerator.getNext();
                    if (win.gBrowser) {
                      for (let tab of win.gBrowser.tabs) {
                        var browser = tab.linkedBrowser;
                        if (browser && browser.currentURI) {
                          var spec = browser.currentURI.spec;
                          if (spec === "about:newtab" || spec === "about:home") {
                            log("Redirecting active tab " + spec + " to " + extNewtabURI);
                            try {
                              var uri = Services.io.newURI(extNewtabURI);
                              browser.loadURI(uri, {
                                triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal()
                              });
                            } catch(ex) {
                              try {
                                var uri = Services.io.newURI(extNewtabURI);
                                win.gBrowser.loadURI(browser, uri, {
                                  triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal()
                                });
                              } catch(ex2) {
                                browser.location = extNewtabURI;
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                } catch(ex) {
                  log("Error redirecting existing tabs: " + ex);
                }
              }
            } catch(ex) {
              log("Error updating newtab URL to extension: " + ex);
            }
          }).catch(function(err) {
            log("Error installing temporary addon: " + err);
          });
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

    // --- KDE Global Menu / DBus AppMenu integration ---
    // Populate #toolbar-menubar with XUL menu items so KDE's global menu panel
    // picks them up via DBus. The menubar stays hidden in Firefox (CSS),
    // but its DOM structure is exposed to the desktop environment.
    try {
      if (!window._seafariGlobalMenuSetup) {
        var menubar = document.getElementById("toolbar-menubar");
        if (menubar && menubar.children.length === 0) {
          function gMenuPopup() {
            return document.createXULElement("menupopup");
          }
          function gMenu(label, accesskey) {
            var m = document.createXULElement("menu");
            m.setAttribute("label", label);
            m.setAttribute("accesskey", accesskey);
            return m;
          }
          function gMenuItem(label, key, command) {
            var mi = document.createXULElement("menuitem");
            mi.setAttribute("label", label);
            if (key) mi.setAttribute("key", key);
            if (command) mi.setAttribute("command", command);
            return mi;
          }
          function gMenuSep() {
            return document.createXULElement("menuseparator");
          }

          // --- File ---
          var fileMenu = gMenu("File", "F");
          var filePopup = gMenuPopup();
          filePopup.appendChild(gMenuItem("New Tab", "key_newNavigatorTab", "cmd_newNavigatorTab"));
          filePopup.appendChild(gMenuItem("New Window", "key_newNavigator", "cmd_newNavigator"));
          filePopup.appendChild(gMenuSep());
          filePopup.appendChild(gMenuItem("Close Tab", "key_close", "cmd_close"));
          filePopup.appendChild(gMenuItem("Close Window", "key_closeWindow", "cmd_closeWindow"));
          filePopup.appendChild(gMenuSep());
          filePopup.appendChild(gMenuItem("Save Page As…", "key_savePage", "cmd_savePage"));
          filePopup.appendChild(gMenuItem("Print…", "key_print", "cmd_print"));
          fileMenu.appendChild(filePopup);
          menubar.appendChild(fileMenu);

          // --- Edit ---
          var editMenu = gMenu("Edit", "E");
          var editPopup = gMenuPopup();
          editPopup.appendChild(gMenuItem("Undo", "key_undo", "cmd_undo"));
          editPopup.appendChild(gMenuItem("Redo", "key_redo", "cmd_redo"));
          editPopup.appendChild(gMenuSep());
          editPopup.appendChild(gMenuItem("Cut", "key_cut", "cmd_cut"));
          editPopup.appendChild(gMenuItem("Copy", "key_copy", "cmd_copy"));
          editPopup.appendChild(gMenuItem("Paste", "key_paste", "cmd_paste"));
          editPopup.appendChild(gMenuItem("Select All", "key_selectAll", "cmd_selectAll"));
          editMenu.appendChild(editPopup);
          menubar.appendChild(editMenu);

          // --- View ---
          var viewMenu = gMenu("View", "V");
          var viewPopup = gMenuPopup();
          viewPopup.appendChild(gMenuItem("Zoom In", "key_zoomIn", "cmd_zoomIn"));
          viewPopup.appendChild(gMenuItem("Zoom Out", "key_zoomOut", "cmd_zoomOut"));
          viewPopup.appendChild(gMenuItem("Reset Zoom", "key_zoomReset", "cmd_zoomReset"));
          viewPopup.appendChild(gMenuSep());
          viewPopup.appendChild(gMenuItem("Page Source", "key_viewSource", "cmd_viewSource"));
          viewPopup.appendChild(gMenuItem("Page Info", "key_pageInfo", "cmd_pageInfo"));
          viewMenu.appendChild(viewPopup);
          menubar.appendChild(viewMenu);

          // --- History ---
          var historyMenu = gMenu("History", "H");
          var historyPopup = gMenuPopup();
          historyPopup.appendChild(gMenuItem("Back", "key_back", "cmd_back"));
          historyPopup.appendChild(gMenuItem("Forward", "key_forward", "cmd_forward"));
          historyPopup.appendChild(gMenuSep());
          historyPopup.appendChild(gMenuItem("Home", "key_home", "cmd_home"));
          historyPopup.appendChild(gMenuSep());
          historyPopup.appendChild(gMenuItem("Show All History", "key_history", "cmd_history"));
          historyMenu.appendChild(historyPopup);
          menubar.appendChild(historyMenu);

          // --- Bookmarks ---
          var bmMenu = gMenu("Bookmarks", "B");
          var bmPopup = gMenuPopup();
          bmPopup.appendChild(gMenuItem("Bookmark This Page", "key_addBookmark", "AddBookmarkAs"));
          bmPopup.appendChild(gMenuItem("Show All Bookmarks", "key_bookmarks", "cmd_bookmarks"));
          bmMenu.appendChild(bmPopup);
          menubar.appendChild(bmMenu);

          // --- Tools ---
          var toolsMenu = gMenu("Tools", "T");
          var toolsPopup = gMenuPopup();
          toolsPopup.appendChild(gMenuItem("Add-ons Manager", null, "cmd_addons"));
          toolsPopup.appendChild(gMenuItem("Downloads", "key_downloads", "Tools:Downloads"));
          toolsPopup.appendChild(gMenuSep());
          toolsPopup.appendChild(gMenuItem("Settings", null, "cmd_preferences"));
          toolsMenu.appendChild(toolsPopup);
          menubar.appendChild(toolsMenu);

          // --- Help ---
          var helpMenu = gMenu("Help", "?");
          var helpPopup = gMenuPopup();
          helpPopup.appendChild(gMenuItem("About Seafari", null, "Help:About"));
          helpMenu.appendChild(helpPopup);
          menubar.appendChild(helpMenu);

          log("KDE Global Menu menubar populated with " + menubar.children.length + " menus");
        }
        window._seafariGlobalMenuSetup = true;
      }
    } catch(e) {
      log("Error setting up global menu: " + e);
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

    // Right pill: [new-tab | PanelUI-menu | tab-overview]
    var knownLeftIds  = ["back-button", "forward-button"];
    var knownMenuIds  = ["new-tab-button", "PanelUI-menu-button", "tab-overview-button"];
    var knownSkipIds  = ["urlbar-container", "stop-reload-button",
                         "sidebar-button", "developer-button",
                         "fxa-toolbar-button", "unified-extensions-button"];

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
    // Right pill: explicit order new-tab → menu → tab-overview
    knownMenuIds.forEach(function(id) {
      var node = findNode(id);
      if (node) menuNodes.push(node);
    });

    // Extensions pill: fxa first (explicit), then unified-extensions, then any unknown dynamic buttons
    var fxaNode = findNode("fxa-toolbar-button");
    var unifiedExtNode = findNode("unified-extensions-button");
    if (fxaNode) extensionNodes.push(fxaNode);
    if (unifiedExtNode) extensionNodes.push(unifiedExtNode);

    Array.from(navBar.children).forEach(function(node) {
      var id = node.id || "";
      if (knownSkipIds.indexOf(id) !== -1) return;
      if (id.indexOf("seafari-pill") === 0) return;
      if (knownLeftIds.indexOf(id) !== -1) return;
      if (knownMenuIds.indexOf(id) !== -1) return;
      if (knownAll[id]) return;
      // Unknown buttons (user-installed extension buttons) → extensions pill
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
    // Layout: [Left pill] [UrlBar+Reload pill] [Ext pill] [Right pill: + | ☰ | 🗂]
    var pillLeft       = makePill(document, "seafari-pill-left",       leftNodes);
    var pillExtensions = makePill(document, "seafari-pill-extensions", extensionNodes);
    var pillMenu       = makePill(document, "seafari-pill-menu",       menuNodes);

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

    // MutationObserver to capture dynamically loaded extensions (like uBlock)
    try {
      var observer = new window.MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          if (mutation.addedNodes) {
            Array.from(mutation.addedNodes).forEach(function(node) {
              if (node.nodeType !== 1) return; // Only element nodes
              var id = node.id || "";
              if (id.indexOf("seafari-pill") === 0) return;
              if (knownSkipIds.indexOf(id) !== -1) return;
              if (knownAll[id]) return;
              
              // This is an extension or custom button!
              log("Dynamic button added to toolbar: " + id + ". Moving to extensions pill...");
              
              // If this is uBlock, relocate it
              if (id.indexOf("ublock") !== -1 || id.indexOf("uBlock") !== -1) {
                relocateUblockBtn(node);
                return;
              }

              // Get or create seafari-pill-extensions
              var extPill = document.getElementById("seafari-pill-extensions");
              if (!extPill) {
                extPill = makePill(document, "seafari-pill-extensions", [node]);
                // Insert it before the menu pill or at the end
                var menuPill = document.getElementById("seafari-pill-menu");
                if (menuPill) {
                  navBar.insertBefore(extPill, menuPill);
                } else {
                  navBar.appendChild(extPill);
                }
                extPill.setAttribute("flex", "0");
                forceStyle(extPill, "-moz-box-flex", "0");
              } else {
                extPill.appendChild(node);
                // Apply pill child styling to the new node
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
              }
            });
          }
        });
      });
      observer.observe(navBar, { childList: true });
    } catch(e) {
      log("Error setting up MutationObserver: " + e);
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

    // --- Move uBlock button to replace tracking protection shield ---
    try {
      if (!window._seafariUblockRelocated) {
        // Log all toolbar buttons to find uBlock
        var allBtns = document.querySelectorAll("toolbarbutton");
        var btnIds = [];
        allBtns.forEach(function(b) { if (b.id) btnIds.push(b.id); });
        log("All toolbarbutton IDs: " + btnIds.join(", "));

        var ublockBtn = null;
        // Method 1: exact ID
        ublockBtn = document.getElementById("ublock0_raymondhill_net-browser-action");
        if (!ublockBtn) {
          // Method 2: query by attribute
          ublockBtn = document.querySelector('[id*="ublock"][id*="browser-action"]');
        }
        if (!ublockBtn) {
          // Method 3: by extension ID attribute
          ublockBtn = document.querySelector('[data-extensionid="uBlock0@raymondhill.net"]');
        }
        if (!ublockBtn) {
          // Method 4: by class webextension-action
          var extBtns = document.querySelectorAll(".webextension-action");
          extBtns.forEach(function(b) {
            log("webextension-action button: id=" + b.id + " title=" + (b.getAttribute("tooltiptext") || b.getAttribute("title") || ""));
            if (!ublockBtn && b.id && (b.id.indexOf("ublock") !== -1 || b.id.indexOf("uBlock") !== -1)) {
              ublockBtn = b;
            }
          });
        }

        if (ublockBtn) {
          relocateUblockBtn(ublockBtn);
        } else {
          log("uBlock button NOT found in toolbar");
        }
        window._seafariUblockRelocated = true;
      }
    } catch(e) { log("uBlock relocation error: " + e); }

    if (window.gBrowser) {
      if (!window._seafariRequestListenerAdded) {
        window.gBrowser.addEventListener("SeafariRequestData", function(event) {
          var doc = event.target;
          if (doc) {
            injectDataIntoNTP(doc);
          }
        }, true);
        window.gBrowser.addEventListener("SeafariSaveData", function(event) {
          try {
            var json = (event.detail && String(event.detail)) || "";
            if (json) writeUserState(json);
          } catch(e) {
            log("SeafariSaveData handler error: " + e);
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

  // 1. Progress listener: redirect about:newtab AND inject data into NTP
  var resolvedExtNewtabURL = null;

  var progressListener = {
    onStateChange: function(aBrowser, aWebProgress, aRequest, aStateFlags, aStatus) {
      if ((aStateFlags & Components.interfaces.nsIWebProgressListener.STATE_STOP) &&
          (aStateFlags & Components.interfaces.nsIWebProgressListener.STATE_IS_DOCUMENT)) {
        try {
          var doc = aBrowser.contentDocument;
          if (doc && doc.location) {
            if (doc.location.href.indexOf("newtab.html") !== -1 || doc.location.href === "about:newtab" || doc.location.href === "about:home") {
              injectDataIntoNTP(doc);
            }
          }
        } catch(e) {}
      }
    },
    onLocationChange: function(aBrowser, aWebProgress, aRequest, aLocation, aFlags) {
      try {
        var url = aLocation.spec;
        // Intercept about:newtab, about:home, and local newtab.html → redirect to extension's newtab
        if (url === "about:newtab" || url === "about:home" || (url && url.indexOf("newtab.html") !== -1 && !url.startsWith("moz-extension://"))) {
          // Resolve extension URL once
          if (!resolvedExtNewtabURL) {
            try {
              var { ExtensionParent } = ChromeUtils.importESModule("resource://gre/modules/ExtensionParent.sys.mjs");
              var ext = ExtensionParent.GlobalManager.getExtension("tab-overview@seafari.org");
              if (ext) {
                resolvedExtNewtabURL = "moz-extension://" + ext.uuid + "/newtab.html";
                log("Resolved extension newtab URL: " + resolvedExtNewtabURL);
              }
            } catch(e) {}
          }
          if (resolvedExtNewtabURL) {
            log("Redirecting " + url + " → " + resolvedExtNewtabURL);
            var win = aBrowser.ownerGlobal;
            if (win && win.gBrowser) {
              try {
                var uri = Services.io.newURI(resolvedExtNewtabURL);
                aBrowser.loadURI(uri, {
                  triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal()
                });
              } catch(e) {
                try {
                  var uri = Services.io.newURI(resolvedExtNewtabURL);
                  win.gBrowser.loadURI(aBrowser, uri, {
                    triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal()
                  });
                } catch(e2) {
                  var originalTab = win.gBrowser.getTabForBrowser(aBrowser);
                  var newTab = win.gBrowser.addTrustedTab(resolvedExtNewtabURL, {
                    triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal()
                  });
                  win.gBrowser.selectedTab = newTab;
                  // Close the original about:newtab tab after a tick
                  setTimeout(function() {
                    try { win.gBrowser.removeTab(originalTab); } catch(err) {}
                  }, 100);
                }
              }
            }
            return;
          }
        }
        // Inject data into NTP pages
        var doc = aBrowser.contentDocument;
        if (doc && doc.location) {
          if (doc.location.href.indexOf("newtab.html") !== -1 || doc.location.href === "about:newtab" || doc.location.href === "about:home") {
            injectDataIntoNTP(doc);
          }
        }
      } catch(e) {}
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

// ============================================================
// Seafari overlay: Safari-like scroll auto-hide and adaptive UI.
// ------------------------------------------------------------
// DESIGN:
//   - At rest the toolbox is in flow (position: static, margin-top: 0).
//     The page uses its original viewport height.
//     The toolbar paints the page's adaptive background color
//     (--gnome-toolbar-background / --lwt-accent-color).
//   - Scroll DOWN -> toolbox smoothly slides up via margin-top collapse,
//     smoothly vacating the space so #browser expands to 100% full
//     window height.
//   - Scroll UP / mouse near top edge (<45px) / URL bar focused /
//     tab switch -> toolbox slides back down smoothly into flow.
// ============================================================
try {
  function later(fn, ms) {
    try {
      var t = Components.classes["@mozilla.org/timer;1"].createInstance(Components.interfaces.nsITimer);
      t.initWithCallback({ notify: function() { try { fn(); } catch(e) {} } }, ms || 0, Components.interfaces.nsITimer.TYPE_ONE_SHOT);
    } catch(e) { try { fn(); } catch(e2) {} }
  }

  function setupOverlayUI(win) {
    try {
      var doc = win.document;
      var toolbox = doc.getElementById("navigator-toolbox");
      if (!toolbox || win._seafariOverlayAdded) return;
      win._seafariOverlayAdded = true;

      var hidden = false;
      function setHidden(h) {
        h = !!h;
        if (h === hidden) return;
        hidden = h;
        try {
          if (h) {
            updateToolboxHeight();
            toolbox.classList.add("seafari-toolbox-hidden");
          } else {
            toolbox.classList.remove("seafari-toolbox-hidden");
          }
        } catch(e) {}
        log("OVERLAY-HIDE " + hidden);
      }

      function updateToolboxHeight() {
        try {
          if (!toolbox.classList.contains("seafari-toolbox-hidden")) {
            var rect = toolbox.getBoundingClientRect();
            if (rect.height > 20) {
              win.document.documentElement.style.setProperty("--seafari-toolbox-height", Math.round(rect.height) + "px");
            }
          }
        } catch(e) {}
      }
      later(updateToolboxHeight, 500);
      win.addEventListener("resize", function() { later(updateToolboxHeight, 100); });

      var urlbar = doc.getElementById("urlbar");

      function isTopProtected() {
        try {
          if (urlbar && doc.activeElement && urlbar.contains(doc.activeElement)) return true;
          var popups = doc.querySelectorAll("menupopup[open], panel[open], #widget-overflow[open]");
          if (popups && popups.length > 0) return true;
        } catch(e) {}
        return false;
      }

      // --- Instant Direction-Based Scroll Listener ---
      var scrollAccum = 0;
      var lastWheelTime = 0;
      win.addEventListener("wheel", function(ev) {
        try {
          if (isTopProtected()) {
            setHidden(false);
            return;
          }
          var now = Date.now();
          if (now - lastWheelTime > 250) scrollAccum = 0;
          lastWheelTime = now;

          if (ev.deltaY > 0) {
            scrollAccum = Math.max(0, scrollAccum) + ev.deltaY;
            if (scrollAccum >= 5 || ev.deltaY >= 6) {
              setHidden(true);
              scrollAccum = 0;
            }
          } else if (ev.deltaY < 0) {
            scrollAccum = Math.min(0, scrollAccum) + ev.deltaY;
            if (scrollAccum <= -3 || ev.deltaY <= -4) {
              setHidden(false);
              scrollAccum = 0;
            }
          }
        } catch(e) {}
      }, { capture: true, passive: true });

      // --- Keydown Scroll Listener ---
      win.addEventListener("keydown", function(ev) {
        try {
          if (isTopProtected()) return;
          var target = ev.target;
          var tag = target && target.tagName ? target.tagName.toLowerCase() : "";
          if (tag === "input" || tag === "textarea" || (target && target.isContentEditable)) return;

          if (ev.key === "PageDown" || ev.key === "ArrowDown" || (ev.key === " " && !ev.shiftKey)) {
            setHidden(true);
          } else if (ev.key === "PageUp" || ev.key === "ArrowUp" || ev.key === "Home" || (ev.key === " " && ev.shiftKey)) {
            setHidden(false);
          }
        } catch(e) {}
      }, { capture: true, passive: true });

      // --- Mouse near top edge (<45px) brings back toolbar ---
      win.addEventListener("mousemove", function(ev) {
        try {
          if (ev.clientY < 45) {
            setHidden(false);
            scrollAccum = 0;
          }
        } catch(e) {}
      }, { capture: true, passive: true });

      // --- Dynamic Adaptive Toolbar Luminance Detector ---
      function updateToolbarLuminance() {
        try {
          var bg = win.getComputedStyle(toolbox).backgroundColor || "";
          var isDark = true;
          var m = bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
          if (m) {
            var r = parseInt(m[1], 10);
            var g = parseInt(m[2], 10);
            var b = parseInt(m[3], 10);
            var lum = 0.299 * r + 0.587 * g + 0.114 * b;
            isDark = lum < 145;
          }
          var themeVal = isDark ? "dark" : "light";
          if (doc.documentElement.getAttribute("seafari-toolbar-theme") !== themeVal) {
            doc.documentElement.setAttribute("seafari-toolbar-theme", themeVal);
          }
        } catch(e) {}
      }

      updateToolbarLuminance();
      later(updateToolbarLuminance, 100);
      later(updateToolbarLuminance, 400);
      later(updateToolbarLuminance, 1000);

      // --- Tab switch / Navigation brings back toolbar & updates luminance ---
      win.addEventListener("TabSelect", function() {
        setHidden(false);
        scrollAccum = 0;
        later(updateToolboxHeight, 100);
        later(updateToolbarLuminance, 50);
        later(updateToolbarLuminance, 250);
      }, true);

      try {
        var lumObserver = new win.MutationObserver(function() {
          updateToolbarLuminance();
        });
        lumObserver.observe(toolbox, { attributes: true, attributeFilter: ["style", "class"] });
        lumObserver.observe(doc.documentElement, { attributes: true, attributeFilter: ["style", "class"] });
      } catch(e) {}

      if (urlbar) {
        urlbar.addEventListener("focusin", function() { setHidden(false); updateToolbarLuminance(); });
        urlbar.addEventListener("focusout", function() { scrollAccum = 0; updateToolbarLuminance(); });
      }

    } catch(e) { log("setupOverlayUI error: " + e); }
  }

  var overlayObsSvc = Components.classes["@mozilla.org/observer-service;1"]
                                 .getService(Components.interfaces.nsIObserverService);
  var overlayObs = {
    observe: function(aSubject) {
      var w = aSubject;
      w.addEventListener("load", function() {
        if (w.location && w.location.href === "chrome://browser/content/browser.xhtml") {
          setupOverlayUI(w);
        }
      }, { once: true });
    }
  };
  overlayObsSvc.addObserver(overlayObs, "domwindowopened", false);

  var overlayMediator = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                                   .getService(Components.interfaces.nsIWindowMediator);
  var overlayWins = overlayMediator.getEnumerator("navigator:browser");
  while (overlayWins.hasMoreElements()) {
    var ow = overlayWins.getNext();
    if (ow.location && ow.location.href === "chrome://browser/content/browser.xhtml") {
      setupOverlayUI(ow);
    }
  }
} catch (e) {
  // Overlay UI is optional; never break startup
}
EOF

echo "Preparing Theme Folder..."
THEME_DIR="$FIREFOX_DIR/seafari-theme"
mkdir -p "$THEME_DIR"
cp -r MacTahoe userChrome.css userContent.css customChrome.css newtab.html "$THEME_DIR/"
cp "seafari.png" "$THEME_DIR/seafari.png"

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

    # Patch about-firefox.mjs to add Discord, Matrix and GitHub links in about:preferences#about
    local about_firefox_mjs="$temp_dir/chrome/browser/content/browser/preferences/config/about-firefox.mjs"
    if [ -f "$about_firefox_mjs" ]; then
        echo "Patching about-firefox.mjs..."
        # 1. Register the settings
        perl -0777 -pi -e 's|Preferences\.addSetting\(\{\s*id:\s*"supportShareIdeas",\s*\}\);|Preferences.addSetting({\n  id: "supportShareIdeas",\n});\nPreferences.addSetting({\n  id: "supportDiscord",\n});\nPreferences.addSetting({\n  id: "supportMatrix",\n});\nPreferences.addSetting({\n  id: "supportGithub",\n});|g' "$about_firefox_mjs"
        # 2. Add items to supportLinksGroup
        perl -0777 -pi -e 's|(\{\s*id:\s*"supportShareIdeas",\s*l10nId:\s*"support-share-ideas",\s*control:\s*"moz-box-link",\s*controlAttrs:\s*\{\s*href:\s*"https://connect.mozilla.org/",\s*\},\s*\})|${1},\n          {\n            id: "supportDiscord",\n            control: "moz-box-link",\n            controlAttrs: {\n              href: "https://discord.com/invite/PSeTkDMnr",\n              label: "Join our Discord",\n            },\n          },\n          {\n            id: "supportMatrix",\n            control: "moz-box-link",\n            controlAttrs: {\n              href: "https://matrix.inled.es",\n              label: "Join our Matrix space",\n            },\n          },\n          {\n            id: "supportGithub",\n            control: "moz-box-link",\n            controlAttrs: {\n              href: "https://github.com/InledGroup/seafari",\n              label: "GitHub Repository",\n            },\n          }|g' "$about_firefox_mjs"
    fi

    # Find and redirect native newtab pages to our extension's newtab (CSP-safe by modifying external JS)
    find "$temp_dir" -type f \( -name "newtab.xhtml" -o -name "newtab.html" -o -name "activity-stream.html" \) 2>/dev/null | while read -r ntp_file; do
        echo "Found native newtab file: $ntp_file"
        local ntp_dir
        ntp_dir=$(dirname "$ntp_file")
        
        local js_files_found=0
        # Prepend the redirect script to all JS files in the same directory (so it gets loaded by the page)
        find "$ntp_dir" -type f -name "*.js" 2>/dev/null | while read -r js_file; do
            echo "Prepending redirect script to JS file: $js_file"
            local tmp_js
            tmp_js=$(mktemp)
            echo "try {
              var prefURL = '';
              if (typeof Services !== 'undefined' && Services.prefs) {
                prefURL = Services.prefs.getStringPref('browser.newtabpage.url');
              } else {
                var prefService = Components.classes['@mozilla.org/preferences-service;1'].getService(Components.interfaces.nsIPrefBranch);
                prefURL = prefService.getCharPref('browser.newtabpage.url');
              }
              if (prefURL && prefURL.startsWith('moz-extension://')) {
                window.location.replace(prefURL);
              }
            } catch(e) {}" > "$tmp_js"
            cat "$js_file" >> "$tmp_js"
            mv "$tmp_js" "$js_file"
            js_files_found=1
        done
        
        # Fallback inline injection if no JS files were found in the same folder
        if [ "$js_files_found" -eq 0 ]; then
            echo "No JS files found in $ntp_dir, injecting inline fallback script..."
            local redirect_script="<script type=\"text/javascript\">try { var prefURL = \"\"; if (typeof Services !== \"undefined\" && Services.prefs) { prefURL = Services.prefs.getStringPref(\"browser.newtabpage.url\"); } else { var prefService = Components.classes[\"@mozilla.org/preferences-service;1\"].getService(Components.interfaces.nsIPrefBranch); prefURL = prefService.getCharPref(\"browser.newtabpage.url\"); } if (prefURL && prefURL.startsWith(\"moz-extension://\")) { window.location.replace(prefURL); } } catch(e) {}</script>"
            if grep -q "<head>" "$ntp_file"; then
                sed -i "s|<head>|<head>${redirect_script}|g" "$ntp_file"
            elif grep -q "<html>" "$ntp_file"; then
                sed -i "s|<html>|<html>${redirect_script}|g" "$ntp_file"
            elif grep -q "<html " "$ntp_file"; then
                sed -i "s|<html [^>]*>|&\n${redirect_script}|g" "$ntp_file"
            else
                local tmp_ntp
                tmp_ntp=$(mktemp)
                echo -e "${redirect_script}" > "$tmp_ntp"
                cat "$ntp_file" >> "$tmp_ntp"
                mv "$tmp_ntp" "$ntp_file"
            fi
        fi
    done

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
PROFILE_DIR="${SEAFARI_PROFILE:-$HOME/.mozilla/seafari-profile}"
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
sed -i '/browser.startup.page/d' "$USER_JS"
echo 'user_pref("browser.startup.page", 1);' >> "$USER_JS"
sed -i '/browser.startup.homepage_override.mstone/d' "$USER_JS"
echo 'user_pref("browser.startup.homepage_override.mstone", "ignore");' >> "$USER_JS"
sed -i '/browser.newtabpage.url/d' "$USER_JS"
echo "user_pref(\"browser.newtabpage.url\", \"file://$PROFILE_DIR/chrome/newtab.html\");" >> "$USER_JS"
sed -i '/browser.newtabpage.activity-stream.enabled/d' "$USER_JS"
echo 'user_pref("browser.newtabpage.activity-stream.enabled", false);' >> "$USER_JS"
sed -i '/browser.startup.homepage/d' "$USER_JS"
echo "user_pref(\"browser.startup.homepage\", \"file://$PROFILE_DIR/chrome/newtab.html\");" >> "$USER_JS"

CRASH_LOG="$PROFILE_DIR/seafari_crash.log"
echo "=== Seafari Session Start: $(date) ===" > "$CRASH_LOG"

# Run Firefox capturing logs
export MOZ_CRASHREPORTER_DISABLE=1
"$LIB_DIR/firefox" --name "seafari" --class "seafari" --profile "$PROFILE_DIR" -no-remote "$@" 2>&1 | tee -a "$CRASH_LOG"
EXIT_CODE=${PIPESTATUS[0]}

echo "=== Seafari Session End with exit code $EXIT_CODE ===" >> "$CRASH_LOG"

# Check if exited with crash signals (anything > 128 indicating a signal exit, except SIGINT/130 and SIGTERM/143)
if [ $EXIT_CODE -gt 128 ] && [ $EXIT_CODE -ne 130 ] && [ $EXIT_CODE -ne 143 ]; then
    echo "Seafari crashed (Exit Code: $EXIT_CODE). Launching custom crash handler..." >> "$CRASH_LOG"
    if command -v zenity &> /dev/null; then
        # Try to copy to clipboard in background
        CLIPBOARD_MSG=""
        if command -v wl-copy &> /dev/null; then
            wl-copy < "$CRASH_LOG" && CLIPBOARD_MSG="\n(The logs have been automatically copied to your clipboard)"
        elif command -v xclip &> /dev/null; then
            xclip -selection clipboard < "$CRASH_LOG" && CLIPBOARD_MSG="\n(The logs have been automatically copied to your clipboard)"
        elif command -v xsel &> /dev/null; then
            xsel --clipboard --input < "$CRASH_LOG" && CLIPBOARD_MSG="\n(The logs have been automatically copied to your clipboard)"
        fi

        # First alert the user and ask to open GitHub
        zenity --question \
            --title="Seafari Crash Handler" \
            --text="Seafari has closed unexpectedly (Exit Code: $EXIT_CODE).\n\nWould you like to open our GitHub issues page to report this crash?$CLIPBOARD_MSG\n\n(You can copy and view the crash logs on the next screen)" \
            --ok-label="Open GitHub & View Logs" \
            --cancel-label="Close" \
            --width=500 --height=180

        if [ $? -eq 0 ]; then
            # Open GitHub issues page in background
            xdg-open "https://github.com/InledGroup/seafari/issues" &
            
            # Show the crash log to let them inspect/copy it
            zenity --text-info \
                --title="Seafari Crash Log" \
                --filename="$CRASH_LOG" \
                --ok-label="Close" \
                --width=700 \
                --height=500
        fi
    else
        echo "=========================================================="
        echo "SEAFARI CRASHED (Exit Code: $EXIT_CODE)"
        echo "Please report the crash to: https://github.com/InledGroup/seafari"
        echo "Logs saved to: $CRASH_LOG"
        echo "=========================================================="
    fi
fi

exit $EXIT_CODE
EOF
chmod +x "$WORKSPACE/seafari.sh"

echo "Packaging .deb for $ARCH_TYPE..."
DEB_ROOT="$WORKSPACE/deb"
mkdir -p "$DEB_ROOT/usr/bin" "$DEB_ROOT/usr/lib/seafari" "$DEB_ROOT/usr/share/applications" "$DEB_ROOT/DEBIAN" \
    "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps" \
    "$DEB_ROOT/usr/share/icons/hicolor/16x16/apps" \
    "$DEB_ROOT/usr/share/icons/hicolor/32x32/apps" \
    "$DEB_ROOT/usr/share/icons/hicolor/48x48/apps" \
    "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps" \
    "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps" \
    "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"
cp -r "$FIREFOX_DIR/"* "$DEB_ROOT/usr/lib/seafari/"
cp "$WORKSPACE/seafari.sh" "$DEB_ROOT/usr/bin/seafari"
# English: Install the Seafari icon in the standard hicolor locations so every
# desktop environment (GNOME, KDE Plasma, XFCE...) can find it. The PNG is placed
# both in scalable/apps (GTK fallback) and in fixed size dirs (preferred by KDE).
# If ImageMagick is available, generate proper resized copies; otherwise reuse the
# original PNG as a fallback.
# Español: Instalar el icono de Seafari en las ubicaciones hicolor estándar para
# que todos los entornos de escritorio (GNOME, KDE Plasma, XFCE...) puedan encontrarlo.
# El PNG se coloca tanto en scalable/apps (respaldo GTK) como en directorios de
# tamaño fijo (preferido por KDE). Si ImageMagick está disponible, se generan copias
# redimensionadas; si no, se reutiliza el PNG original como respaldo.
ICON_DIR="$DEB_ROOT/usr/share/icons/hicolor"
for SIZE in 16 32 48 64 128 256; do
    if command -v convert &> /dev/null; then
        convert "$ROOT_DIR/seafari.png" -resize "${SIZE}x${SIZE}" "$ICON_DIR/${SIZE}x${SIZE}/apps/seafari.png"
    else
        cp "$ROOT_DIR/seafari.png" "$ICON_DIR/${SIZE}x${SIZE}/apps/seafari.png"
    fi
done
cp "$ROOT_DIR/seafari.png" "$ICON_DIR/scalable/apps/seafari.png"
cat <<EOF > "$DEB_ROOT/usr/share/applications/seafari.desktop"
[Desktop Entry]
Name=Seafari
Exec=seafari %u
Icon=seafari
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/x-www-form-urlencoded;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=seafari
EOF
cat <<EOF > "$DEB_ROOT/DEBIAN/control"
Package: seafari
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: Seafari Team
Description: Seafari - Safari styled browser.
EOF
# English: Post-install script shared by the .deb, .rpm and pacman packages.
# It regenerates the icon and desktop-file caches so the Seafari logo appears
# right after installation (fpm pacman/rpm packages do not refresh them by default).
# Español: Script post-instalación compartido por los paquetes .deb, .rpm y pacman.
# Regenera las cachés de iconos y archivos .desktop para que el logo de Seafari
# aparezca justo después de la instalación (los paquetes pacman/rpm de fpm no las
# refrescan por defecto).
POSTINSTALL="$WORKSPACE/seafari.postinst"
cat <<'EOF' > "$POSTINSTALL"
#!/bin/sh
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database >/dev/null 2>&1 || true
fi
# Register Seafari as a browser so the OS offers it for web links.
# Only become the default if the user has not chosen another browser yet.
if command -v xdg-settings >/dev/null 2>&1; then
    CURRENT_DEFAULT="$(xdg-settings get default-web-browser 2>/dev/null || true)"
    if [ -z "$CURRENT_DEFAULT" ] || [ "$CURRENT_DEFAULT" = "unknown" ] || [ "$CURRENT_DEFAULT" = "firefox.desktop" ]; then
        xdg-settings set default-web-browser seafari.desktop >/dev/null 2>&1 || true
    fi
fi
if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default seafari.desktop text/html text/xml application/xhtml+xml x-scheme-handler/http x-scheme-handler/https >/dev/null 2>&1 || true
fi
exit 0
EOF
chmod +x "$POSTINSTALL"
cp "$POSTINSTALL" "$DEB_ROOT/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$DEB_ROOT" "seafari_${VERSION}_${DEB_ARCH}.deb"

if [ "$SKIP_RPM" == "true" ]; then
    echo "Skipping RPM and Arch Linux (pacman) packaging (--skip-rpm)..."
else
    echo "Packaging .rpm and .pkg.tar.zst..."

    # English: Arch Linux (pacman) package built with bsdtar + zstd (no fpm needed).
    # A .pkg.tar.zst is just a zstd-compressed tar, so these portable tools work on any distro.
    # Español: Paquete de Arch Linux (pacman) construido con bsdtar + zstd (sin necesidad de fpm).
    # Un .pkg.tar.zst es solo un tar comprimido con zstd, así que estas herramientas portables
    # funcionan en cualquier distribución.
    PKG_ROOT="$WORKSPACE/pkg"
    rm -rf "$PKG_ROOT"
    mkdir -p "$PKG_ROOT"
    cp -a "$DEB_ROOT/usr" "$PKG_ROOT/"
    PKG_SIZE=$(du -sk "$PKG_ROOT" | cut -f1)
    PKG_DATE=$(date -u +%s)
    cat > "$PKG_ROOT/.PKGINFO" <<EOF
pkgname = seafari
pkgver = ${VERSION}-1
pkgdesc = Seafari - Safari styled browser.
url =
builddate = ${PKG_DATE}
packager = Unknown Packager
size = ${PKG_SIZE}
arch = ${RPM_ARCH}
license = MPL-2.0
EOF
    cat > "$PKG_ROOT/.INSTALL" <<'EOF'
post_install() {
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database >/dev/null 2>&1 || true
    fi
    if command -v xdg-settings >/dev/null 2>&1; then
        CURRENT_DEFAULT="$(xdg-settings get default-web-browser 2>/dev/null || true)"
        if [ -z "$CURRENT_DEFAULT" ] || [ "$CURRENT_DEFAULT" = "unknown" ] || [ "$CURRENT_DEFAULT" = "firefox.desktop" ]; then
            xdg-settings set default-web-browser seafari.desktop >/dev/null 2>&1 || true
        fi
    fi
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default seafari.desktop text/html text/xml application/xhtml+xml x-scheme-handler/http x-scheme-handler/https >/dev/null 2>&1 || true
    fi
}
post_upgrade() {
    post_install
}
post_remove() {
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database >/dev/null 2>&1 || true
    fi
}
EOF
    ( cd "$PKG_ROOT" && bsdtar -cf - .PKGINFO .INSTALL usr ) | zstd -c -z -q -T0 -19 - > "seafari-${VERSION}-1-${RPM_ARCH}.pkg.tar.zst"
    echo "Created seafari-${VERSION}-1-${RPM_ARCH}.pkg.tar.zst"

    # English: RPM package built with rpmbuild (no fpm needed).
    # Español: Paquete RPM construido con rpmbuild (sin necesidad de fpm).
    if command -v rpmbuild &> /dev/null; then
        RPMBUILD_DIR="$(readlink -f "$WORKSPACE/rpmbuild")"
        rm -rf "$RPMBUILD_DIR"
        mkdir -p "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
        DEB_ROOT_ABS="$(readlink -f "$DEB_ROOT")"
        SPEC="$RPMBUILD_DIR/SPECS/seafari.spec"
        cat > "$SPEC" <<EOF
Name:           seafari
Version:        $VERSION
Release:        1
Summary:        Seafari - Safari styled browser
License:        MPL-2.0
URL:            https://github.com/InledGroup/seafari
AutoReqProv:    no
%global __os_install_post %{nil}

%description
Seafari - Safari styled browser.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr
cp -a $DEB_ROOT_ABS/usr/. %{buildroot}/usr/

%post
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database >/dev/null 2>&1 || true
fi
if command -v xdg-settings >/dev/null 2>&1; then
    CURRENT_DEFAULT="\$(xdg-settings get default-web-browser 2>/dev/null || true)"
    if [ -z "\$CURRENT_DEFAULT" ] || [ "\$CURRENT_DEFAULT" = "unknown" ] || [ "\$CURRENT_DEFAULT" = "firefox.desktop" ]; then
        xdg-settings set default-web-browser seafari.desktop >/dev/null 2>&1 || true
    fi
fi
if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default seafari.desktop text/html text/xml application/xhtml+xml x-scheme-handler/http x-scheme-handler/https >/dev/null 2>&1 || true
fi
exit 0

%postun
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database >/dev/null 2>&1 || true
fi
exit 0

%files
EOF
        ( cd "$DEB_ROOT" && find usr -type f -print -o -type l -print | sed 's|^|/|' ) >> "$SPEC"
        rpmbuild --define "_topdir $RPMBUILD_DIR" --target "$RPM_ARCH" -bb "$SPEC"
        cp "$RPMBUILD_DIR/RPMS/$RPM_ARCH/seafari-${VERSION}-1.${RPM_ARCH}.rpm" .
        echo "Created seafari-${VERSION}-1.${RPM_ARCH}.rpm"
    else
        echo "WARNING: rpmbuild not found. Skipping RPM packaging."
    fi
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




