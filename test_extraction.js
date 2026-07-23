// Copy and paste this script into the Firefox Browser Console (Ctrl+Shift+J) in "Browser" context:
(function() {
  console.log("=== Testing Seafari Data Extraction ===");

  // 1. Test History Extraction
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
    
    var items = [];
    for (var i = 0; i < root.childCount; i++) {
      var node = root.getChild(i);
      items.push({
        title: node.title || node.uri,
        url: node.uri
      });
    }
    root.containerOpen = false;
    console.log("History extraction successful. Found " + items.length + " items:", items);
  } catch (e) {
    console.error("History extraction failed:", e);
  }

  // 2. Test uBlock Origin Badge Text Extraction (Parent Process UI State)
  try {
    var { ExtensionParent } = ChromeUtils.importESModule("resource://gre/modules/ExtensionParent.sys.mjs");
    var extension = ExtensionParent.GlobalManager.getExtension("uBlock0@raymondhill.net");
    if (extension) {
      console.log("uBlock Origin extension instance found. UUID:", extension.uuid);
      var browserAction = extension.browserAction;
      if (browserAction) {
        // Get the active window's current tab
        var windowMediator = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                                       .getService(Components.interfaces.nsIWindowMediator);
        var recentWindow = windowMediator.getMostRecentWindow("navigator:browser");
        if (recentWindow && recentWindow.gBrowser) {
          var activeTab = recentWindow.gBrowser.selectedTab;
          // Get the badge text for the active tab from the parent process UI state
          var badgeText = browserAction.getProperty(activeTab, "badgeText") || "";
          console.log("uBlock Stats extraction successful. Current Tab Blocked Count:", badgeText);
        } else {
          console.log("No active browser window found to query tab-specific badge text.");
        }
      } else {
        console.log("extension.browserAction is undefined.");
      }
    } else {
      console.error("uBlock Origin extension (uBlock0@raymondhill.net) is not loaded or not found.");
    }
  } catch (e) {
    console.error("uBlock Stats extraction failed:", e);
  }
})();
