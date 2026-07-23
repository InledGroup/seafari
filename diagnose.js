// Run in Browser Console (Ctrl+Shift+J) → select "Browser" context at top
// Paste this entire script and press Enter.
(function() {
  var R = [];
  function ok(msg)  { R.push("[OK]   " + msg); }
  function fail(msg) { R.push("[FAIL] " + msg); }
  function info(msg) { R.push("[INFO] " + msg); }

  info("=== SEAFARI DIAGNOSTIC ===");

  // 1. Check if seafari.cfg loaded at all
  try {
    var cfgFile = Services.dirsvc.get("ProfD", Components.interfaces.nsIFile);
    cfgFile.append("chrome");
    cfgFile.append("newtab.html");
    if (cfgFile.exists()) {
      ok("NTP file exists at: " + cfgFile.path);
    } else {
      fail("NTP file NOT found at: " + cfgFile.path);
    }
  } catch(e) { fail("NTP file check error: " + e); }

  // 2. Check if seafari.cfg is the active AutoConfig
  try {
    var cfgName = Services.prefs.getCharPref("general.config.filename");
    info("general.config.filename = " + cfgName);
    if (cfgName === "seafari.cfg") ok("AutoConfig filename is correct");
    else fail("AutoConfig filename is '" + cfgName + "', expected 'seafari.cfg'");
  } catch(e) { fail("Cannot read general.config.filename: " + e); }

  // 3. Check if the seafari.cfg file exists in Firefox dir
  try {
    var greDir = Services.dirsvc.get("GreD", Components.interfaces.nsIFile);
    var cfgPath = greDir.path;
    // On Linux, seafari.cfg is in the AppImage's firefox/ dir
    info("GreD = " + cfgPath);
  } catch(e) { info("GreD check error: " + e); }

  // 4. Check if state file exists
  try {
    var stateFile = Services.dirsvc.get("ProfD", Components.interfaces.nsIFile);
    stateFile.append("seafari-state.json");
    if (stateFile.exists()) {
      ok("State file exists: " + stateFile.path);
      // Read it
      var fis = Components.classes["@mozilla.org/file/input-stream;1"]
                          .createInstance(Components.interfaces.nsIFileInputStream);
      fis.init(stateFile, 0x01, 0444, 0);
      var cis = Components.classes["@mozilla.org/intl/converter-input-stream;1"]
                          .createInstance(Components.interfaces.nsIConverterInputStream);
      cis.init(fis, "UTF-8", 1024, Components.interfaces.nsIConverterInputStream.DEFAULT_REPLACEMENT_CHARACTER);
      var data = "", str = {};
      while (cis.readString(4096, str)) data += str.value;
      cis.close();
      info("State file contents: " + data.substring(0, 500));
    } else {
      info("State file does NOT exist yet (will be created on first save)");
    }
  } catch(e) { info("State file check error: " + e); }

  // 5. Check if NTP is open and inspect it
  try {
    var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                       .getService(Components.interfaces.nsIWindowMediator);
    var browserWin = wm.getMostRecentWindow("navigator:browser");
    if (!browserWin || !browserWin.gBrowser) {
      fail("No browser window found");
    } else {
      var tabs = browserWin.gBrowser.tabs;
      info("Open tabs: " + tabs.length);
      var ntpFound = false;
      for (var i = 0; i < tabs.length; i++) {
        var browser = tabs[i].linkedBrowser;
        if (!browser || !browser.currentURI) continue;
        var url = browser.currentURI.spec;
        info("Tab " + i + ": " + url);
        if (url.includes("newtab.html") || url === "about:newtab") {
          ntpFound = true;
          var doc = browser.contentDocument;
          var win = browser.contentWindow;
          if (!win) { fail("NTP window is null"); continue; }

          // Check wrappedJSObject access
          var wJSO = win.wrappedJSObject;
          if (wJSO.realHistoryData !== undefined) {
            ok("realHistoryData is INJECTED (" + wJSO.realHistoryData.length + " items)");
            info("  Data: " + JSON.stringify(wJSO.realHistoryData).substring(0, 300));
          } else {
            fail("realHistoryData is UNDEFINED — injectDataIntoNTP was NOT called or failed");
          }

          if (wJSO.realPrivacyStats !== undefined) {
            ok("realPrivacyStats is INJECTED (totalBlocked=" + wJSO.realPrivacyStats.totalBlocked + ")");
          } else {
            fail("realPrivacyStats is UNDEFINED — injectDataIntoNTP was NOT called or failed");
          }

          if (wJSO.realUserState !== undefined) {
            ok("realUserState is INJECTED");
            info("  State: " + JSON.stringify(wJSO.realUserState).substring(0, 300));
          } else {
            fail("realUserState is UNDEFINED — injectDataIntoNTP was NOT called or failed");
          }

          // Check the NTP's own state
          try {
            var ntpState = wJSO.state;
            if (ntpState) {
              info("NTP state.favorites: " + JSON.stringify(ntpState.favorites).substring(0, 200));
              info("NTP state.history length: " + (ntpState.history ? ntpState.history.length : "null"));
              info("NTP state.readingList: " + JSON.stringify(ntpState.readingList).substring(0, 200));
            } else {
              info("NTP state object is null/undefined");
            }
          } catch(e) { info("Cannot read NTP state: " + e); }

          // Check _seafariSave
          try {
            var pending = wJSO._seafariSave;
            if (pending) {
              info("Pending save on window._seafariSave: " + pending.substring(0, 200));
            } else {
              info("No pending save (_seafariSave is empty)");
            }
          } catch(e) {}
        }
      }
      if (!ntpFound) fail("NTP tab is NOT open");
    }
  } catch(e) { fail("Browser window inspection error: " + e); }

  // 6. Check if progress listener might be registered by checking gBrowser
  try {
    var wm2 = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                        .getService(Components.interfaces.nsIWindowMediator);
    var bw = wm2.getMostRecentWindow("navigator:browser");
    if (bw && bw.gBrowser) {
      var gb = bw.gBrowser;
      info("gBrowser exists, tabsCount=" + gb.tabs.length);

      // Try manual injection to test if injectDataIntoNTP works at all
      info("--- MANUAL INJECTION TEST ---");
      for (var j = 0; j < gb.tabs.length; j++) {
        var br = gb.tabs[j].linkedBrowser;
        if (br && br.currentURI && br.currentURI.spec.includes("newtab.html")) {
          var testDoc = br.contentDocument;
          // We can't call injectDataIntoNTP directly (it's in seafari.cfg scope),
          // but we can test the individual pieces
          try {
            var hs = Components.classes["@mozilla.org/browser/nav-history-service;1"]
                               .getService(Components.interfaces.nsINavHistoryService);
            var q = hs.getNewQuery();
            var o = hs.getNewQueryOptions();
            o.maxResults = 6;
            o.sortingMode = Components.interfaces.nsINavHistoryQueryOptions.SORT_BY_VISITCOUNT_DESCENDING;
            var r = hs.executeQuery(q, o);
            var rt = r.root;
            rt.containerOpen = true;
            var items = [];
            for (var k = 0; k < rt.childCount; k++) {
              var n = rt.getChild(k);
              items.push({ title: n.title || n.uri, url: n.uri });
            }
            rt.containerOpen = false;
            ok("Manual history query returned " + items.length + " items");
            if (items.length > 0) {
              info("  First: " + JSON.stringify(items[0]));
            }
          } catch(e) { fail("Manual history query failed: " + e); }

          // Test cloneInto
          try {
            var testData = [{ title: "test", url: "http://test.com" }];
            br.contentWindow.wrappedJSObject.realHistoryData =
              Components.utils.cloneInto(testData, br.contentWindow);
            var evt = testDoc.createEvent("CustomEvent");
            evt.initCustomEvent("SeafariDataReady", true, true, null);
            testDoc.dispatchEvent(evt);
            ok("Manual cloneInto + SeafariDataReady dispatch succeeded");
            info("Check the NTP tab now — if history shows 'test', the bridge works");
          } catch(e) { fail("Manual cloneInto failed: " + e); }
          break;
        }
      }
    }
  } catch(e) { fail("Manual injection test error: " + e); }

  // Print results
  info("");
  info("=== RESULTS ===");
  for (var i = 0; i < R.length; i++) console.log(R[i]);
  info("=== END DIAGNOSTIC ===");
})();
