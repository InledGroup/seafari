window.ublockStats = null;
let tabPreviews = {};

// Capture active tab screenshot
function captureActiveTab() {
  browser.tabs.query({ active: true, currentWindow: true }).then((tabs) => {
    if (tabs.length === 0) return;
    let tab = tabs[0];
    // Don't capture privileged, empty or overview tabs
    if (!tab.url || tab.url.startsWith("about:") || tab.url.startsWith("chrome:") || 
        tab.url.startsWith("moz-extension:") || tab.url.includes("overview.html")) {
      return;
    }
    browser.tabs.captureVisibleTab(null, { format: "jpeg", quality: 60 }).then((dataUrl) => {
      tabPreviews[tab.id] = dataUrl;
    }).catch(() => {});
  });
}

// Watch for tab selection changes
browser.tabs.onActivated.addListener(() => {
  setTimeout(captureActiveTab, 500);
});

// Watch for tab load completions
browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" && tab.active) {
    setTimeout(captureActiveTab, 500);
  }
});

// Watch for closed tabs to clean up preview memory
browser.tabs.onRemoved.addListener((tabId) => {
  delete tabPreviews[tabId];
});

// Message listener to return the previews and tabs list to overview page
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === "getTabs") {
    browser.tabs.query({ currentWindow: true }).then((tabs) => {
      // Filter out overview tab itself so it NEVER appears in the overview
      let filtered = tabs.filter(t => {
        if (!t.url) return true;
        if (t.url.includes("overview.html")) return false;
        if (sender && sender.tab && t.id === sender.tab.id) return false;
        return true;
      });
      sendResponse({
        tabs: filtered,
        previews: tabPreviews
      });
    });
    return true; // Keep message channel open for async response
  }
  if (message.action === "selectTab") {
    browser.tabs.update(message.tabId, { active: true }).then(() => {
      if (sender && sender.tab && sender.tab.id) {
        browser.tabs.remove(sender.tab.id);
      }
    });
    sendResponse({ success: true });
  }
  if (message.action === "closeTab") {
    delete tabPreviews[message.tabId];
    browser.tabs.remove(message.tabId).then(() => {
      sendResponse({ success: true });
    });
    return true;
  }
});
