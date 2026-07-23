window.ublockStats = null;
let tabPreviews = {};

// Capture active tab screenshot
function captureActiveTab() {
  browser.tabs.query({ active: true, currentWindow: true }).then((tabs) => {
    if (tabs.length === 0) return;
    let tab = tabs[0];
    // Don't capture privileged or empty tabs
    if (!tab.url || tab.url.startsWith("about:") || tab.url.startsWith("chrome:") || tab.url.startsWith("moz-extension:")) {
      return;
    }
    browser.tabs.captureVisibleTab(null, { format: "jpeg", quality: 50 }).then((dataUrl) => {
      tabPreviews[tab.id] = dataUrl;
    }).catch(() => {});
  });
}

// Watch for tab selection changes
browser.tabs.onActivated.addListener(() => {
  // Wait a small moment for the page to render before capturing
  setTimeout(captureActiveTab, 500);
});

// Watch for tab load completions
browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" && tab.active) {
    setTimeout(captureActiveTab, 500);
  }
});

// Message listener to return the previews and tabs list to overview page
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === "getTabs") {
    browser.tabs.query({ currentWindow: true }).then((tabs) => {
      sendResponse({
        tabs: tabs,
        previews: tabPreviews
      });
    });
    return true; // Keep message channel open for async response
  }
  if (message.action === "selectTab") {
    browser.tabs.update(message.tabId, { active: true }).then(() => {
      if (sender.tab && sender.tab.id) {
        browser.tabs.remove(sender.tab.id);
      }
    });
    sendResponse({ success: true });
  }
  if (message.action === "closeTab") {
    browser.tabs.remove(message.tabId).then(() => {
      sendResponse({ success: true });
    });
    return true;
  }
});
