// Run in Browser Console (Ctrl+Shift+J) -> select "Browser" (or "Multiprocess") context at top
// Paste this entire script and press Enter.
(function() {
  console.log("=== SEAFARI DOM SEARCH ===");
  // Find uBlock button
  var ublock = document.querySelector('[id*="ublock"]') || document.querySelector('[id*="uBlock"]') || document.querySelector('[data-extensionid*="uBlock"]');
  if (ublock) {
    console.log("uBlock element found:", ublock.tagName, "ID:", ublock.id, "Classes:", ublock.className);
    console.log("uBlock parent:", ublock.parentNode.tagName, "ID:", ublock.parentNode.id);
  } else {
    console.log("uBlock element NOT found by id/extensionid search");
  }

  // Find URL bar elements
  var urlbar = document.getElementById("urlbar");
  if (urlbar) {
    console.log("urlbar tag:", urlbar.tagName, "children:", Array.from(urlbar.children).map(c => c.id || c.tagName).join(", "));
  } else {
    console.log("urlbar NOT found");
  }

  var urlbarInputContainer = document.getElementById("urlbar-input-container");
  if (urlbarInputContainer) {
    console.log("urlbar-input-container children:", Array.from(urlbarInputContainer.children).map(c => c.id || c.tagName).join(", "));
  } else {
    console.log("urlbar-input-container NOT found");
  }

  var identityBox = document.getElementById("identity-box");
  if (identityBox) {
    console.log("identity-box found:", identityBox.tagName, "children:", Array.from(identityBox.children).map(c => c.id || c.tagName).join(", "));
  } else {
    console.log("identity-box NOT found");
  }
})();
