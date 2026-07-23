// Copy and paste this script into the Firefox Browser Console (Ctrl+Shift+J) in "Browser" context:
(function() {
  console.log("=== SEAFARI DIAGNOSTIC AND EXTRACTION TEST ===");

  // 1. Check Extensions remote preference
  try {
    var remotePref = Services.prefs.getBoolPref("extensions.webextensions.remote");
    console.log("Preference 'extensions.webextensions.remote' is:", remotePref);
  } catch(e) {
    console.log("Preference 'extensions.webextensions.remote' could not be read:", e.message);
  }

  // 2. Query History
  try {
    var historyService = Components.classes["@mozilla.org/browser/nav-history-service;1"]
                                   .getService(Components.interfaces.nsINavHistoryService);
    var query = historyService.getNewQuery();
    var options = historyService.getNewQueryOptions();
    options.maxResults = 6;
    options.sortingMode = Components.interfaces.nsINavHistoryQueryOptions.SORT_BY_VISITCOUNT_DESCENDING;
    
    var result = historyService.executeQuery(query, options);
    var root = result.root;
    root.containerOpen = true;
    
    var historyItems = [];
    for (var i = 0; i < root.childCount; i++) {
      var node = root.getChild(i);
      historyItems.push({
        title: node.title || node.uri,
        url: node.uri
      });
    }
    root.containerOpen = false;
    console.log("History Query Result (Found " + historyItems.length + "):", historyItems);
  } catch (e) {
    console.error("History query failed:", e);
  }

  // 3. Inspect uBlock Origin
  try {
    var { ExtensionParent } = ChromeUtils.importESModule("resource://gre/modules/ExtensionParent.sys.mjs");
    var extension = ExtensionParent.GlobalManager.getExtension("uBlock0@raymondhill.net");
    if (extension) {
      console.log("uBlock Origin Extension Found. ID:", extension.id, "UUID:", extension.uuid);
      if (extension.views) {
        console.log("Number of views in extension.views:", extension.views.size);
        var index = 0;
        for (var view of extension.views) {
          console.log(`View #${index}: type=${view.viewType}, contentWindow=${view.contentWindow}`);
          if (view.viewType === "background" && view.contentWindow) {
            var bgWin = view.contentWindow;
            var uBlockObj = bgWin.µBlock || bgWin.μBlock || bgWin.uBlock;
            if (uBlockObj) {
              console.log("µBlock object found on background window!");
              if (uBlockObj.localSettings) {
                console.log("Total Blocked (blockedRequestCount):", uBlockObj.localSettings.blockedRequestCount);
              } else {
                console.log("µBlock.localSettings is undefined.");
              }
            } else {
              console.log("µBlock/μBlock/uBlock global object is NOT found on background window.");
              // Print some keys of background window to help diagnose
              console.log("Background window global keys:", Object.keys(bgWin).slice(0, 50));
            }
          }
          index++;
        }
      } else {
        console.log("extension.views is undefined or empty.");
      }
    } else {
      console.log("uBlock Origin (uBlock0@raymondhill.net) not found in ExtensionParent.");
    }
  } catch (e) {
    console.error("uBlock Inspection failed:", e);
  }

  // 4. Inspect New Tab page data injection
  try {
    var windowMediator = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                                   .getService(Components.interfaces.nsIWindowMediator);
    var browserWin = windowMediator.getMostRecentWindow("navigator:browser");
    if (browserWin && browserWin.gBrowser) {
      var tabs = browserWin.gBrowser.tabs;
      console.log("Open tabs count:", tabs.length);
      for (var t of tabs) {
        var browser = t.linkedBrowser;
        if (browser && browser.currentURI) {
          console.log(`Tab URL: ${browser.currentURI.spec}`);
          if (browser.currentURI.spec.includes("newtab.html")) {
            var doc = browser.contentDocument;
            var win = browser.contentWindow;
            if (win) {
              console.log("New tab page window found!");
              console.log("realHistoryData on page:", win.wrappedJSObject.realHistoryData);
              console.log("realPrivacyStats on page:", win.wrappedJSObject.realPrivacyStats);
            }
          }
        }
      }
    }
  } catch(e) {
    console.error("New Tab page inspection failed:", e);
  }
})();
