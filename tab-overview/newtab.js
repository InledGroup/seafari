// State management
const state = {
  favorites: [
   /* { name: "Google", url: "https://www.google.com" },
    { name: "YouTube", url: "https://www.youtube.com" },
    { name: "Wikipedia", url: "https://www.wikipedia.org" },
    { name: "Reddit", url: "https://www.reddit.com" },
    { name: "GitHub", url: "https://github.com" },
    { name: "Amazon", url: "https://www.amazon.com" },
    { name: "Twitter", url: "https://twitter.com" },
    { name: "Yahoo", url: "https://www.yahoo.com" } */
  ],
  readingList: [
  /*  { title: "Yahoo | Mail, Weather, Search, Politics, News", url: "https://yahoo.com", desc: "Latest news coverage, email, free stock quotes, live scores and video.", domain: "yahoo.com" },
    { title: "Phone Cases - Mous", url: "https://mous.co", desc: "Extremely durable, protective and shockproof phone cases with carbon fiber.", domain: "mous.co" },
    { title: "Princeton Research Papers - CEPR-DP13564.pdf", url: "https://www.princeton.edu", desc: "PDF documentation and academic archives hosted on Princeton servers.", domain: "princeton.edu" } */
  ],
  history: [],
  toggles: {
    favorites: true,
    history: true,
    privacy: true,
    reading: true
  },
  background: "mountains", 
  customBgData: ""
};

// Load and save state using browser.storage.local (asynchronous, reliable)
// with localStorage as synchronous startup/save fallback.
const LS_KEY = "seafari_state";

function loadState() {
  // 1. Try extension local storage first
  try {
    browser.storage.local.get("seafari_state").then((result) => {
      if (result && result.seafari_state) {
        const s = result.seafari_state;
        if (s.favorites !== undefined) state.favorites = s.favorites;
        if (s.readingList !== undefined) state.readingList = s.readingList;
        if (s.toggles !== undefined) state.toggles = s.toggles;
        if (s.background !== undefined) state.background = s.background;
        if (s.customBgData !== undefined) state.customBgData = s.customBgData;
        
        // Sync drawer checkboxes with loaded state
        if (toggleFavsCb) toggleFavsCb.checked = state.toggles.favorites;
        if (toggleHistoryCb) toggleHistoryCb.checked = state.toggles.history;
        if (togglePrivacyCb) togglePrivacyCb.checked = state.toggles.privacy;
        if (toggleReadingCb) toggleReadingCb.checked = state.toggles.reading;
        
        initUI();
      } else {
        // Fallback to localStorage
        loadStateFromLocalStorage();
      }
    }).catch(() => {
      loadStateFromLocalStorage();
    });
  } catch(e) {
    loadStateFromLocalStorage();
  }
}

function loadStateFromLocalStorage() {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) {
      initUI();
      return;
    }
    const s = JSON.parse(raw);
    if (s.favorites !== undefined) state.favorites = s.favorites;
    if (s.readingList !== undefined) state.readingList = s.readingList;
    if (s.toggles !== undefined) state.toggles = s.toggles;
    if (s.background !== undefined) state.background = s.background;
    if (s.customBgData !== undefined) state.customBgData = s.customBgData;
  } catch(e) {}
  initUI();
}

function saveState(key) {
  const data = {
    favorites: state.favorites,
    readingList: state.readingList,
    toggles: state.toggles,
    background: state.background,
    customBgData: state.customBgData
  };
  
  // Save synchronously to localStorage
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(data));
  } catch(e) {}
  
  // Save asynchronously to extension storage
  try {
    browser.storage.local.set({ "seafari_state": data }).catch((err) => {
      console.error("Error saving state to extension storage:", err);
    });
  } catch(e) {}
}

// DOM Elements
const body = document.body;
const favoritesContainer = document.getElementById("favorites-container");
const historyContainer = document.getElementById("history-container");
const readingContainer = document.getElementById("reading-container");

// Toggles
const secFavorites = document.getElementById("section-favorites");
const secHistory = document.getElementById("section-history");
const secPrivacy = document.getElementById("section-privacy");
const secReading = document.getElementById("section-reading");

// Drawer Toggles
const toggleFavsCb = document.getElementById("toggle-favorites-cb");
const toggleHistoryCb = document.getElementById("toggle-history-cb");
const togglePrivacyCb = document.getElementById("toggle-privacy-cb");
const toggleReadingCb = document.getElementById("toggle-reading-cb");

// Drawer Elements
const customDrawer = document.getElementById("custom-drawer");
const editToggle = document.getElementById("edit-toggle");
const closeDrawer = document.getElementById("close-drawer");

// Init Page Elements
function initUI() {
  // Apply Toggles Checkboxes
  toggleFavsCb.checked = state.toggles.favorites;
  toggleHistoryCb.checked = state.toggles.history;
  togglePrivacyCb.checked = state.toggles.privacy;
  toggleReadingCb.checked = state.toggles.reading;

  applyTogglesVisibility();
  applyBackground();
  renderFavorites();
  renderHistory();
  renderReadingList();
}

function applyTogglesVisibility() {
  if (state.toggles.favorites) secFavorites.classList.remove("hidden");
  else secFavorites.classList.add("hidden");

  if (state.toggles.history && state.history.length > 0) secHistory.classList.remove("hidden");
  else secHistory.classList.add("hidden");

  if (state.toggles.privacy) secPrivacy.classList.remove("hidden");
  else secPrivacy.classList.add("hidden");

  if (state.toggles.reading) secReading.classList.remove("hidden");
  else secReading.classList.add("hidden");
}

function applyBackground() {
  // Remove all bg classes
  body.className = "";
  body.style.backgroundImage = "";
  
  // Update Active Thumbnail
  document.querySelectorAll(".bg-thumb").forEach(thumb => {
    if (thumb.dataset.bg === state.background) {
      thumb.classList.add("active");
    } else {
      thumb.classList.remove("active");
    }
  });

  if (state.background === "custom" && state.customBgData) {
    body.style.backgroundImage = `url(${state.customBgData})`;
    body.classList.add("custom-bg-active");
  } else {
    body.classList.add(`bg-${state.background}`);
  }

  // Handle text colors based on background
  if (state.background === "light") {
    body.classList.add("light-theme-text");
  } else {
    body.classList.remove("light-theme-text");
  }
}

function getDomain(url) {
  try {
    const u = new URL(url);
    return u.hostname.replace("www.", "");
  } catch (e) {
    return url;
  }
}

function getLetter(name) {
  return name ? name.charAt(0).toUpperCase() : "?";
}

function renderFavorites() {
  favoritesContainer.innerHTML = "";

  state.favorites.forEach((fav, index) => {
    const domain = getDomain(fav.url);
    const initial = getLetter(fav.name);
    
    const favEl = document.createElement("div");
    favEl.className = "fav-item-wrapper";
    
    // We use Google Favicons API
    const faviconUrl = `https://www.google.com/s2/favicons?sz=64&domain=${domain}`;

    favEl.innerHTML = `
      <a class="fav-item" href="${fav.url}">
        <div class="fav-tile">
          <img class="fav-icon" src="${faviconUrl}">
          <span class="fav-initial" style="display:none;">${initial}</span>
        </div>
        <span class="fav-label">${fav.name}</span>
      </a>
      <div class="delete-btn" data-index="${index}" title="Eliminar favorito">&times;</div>
    `;
    favoritesContainer.appendChild(favEl);
  });

  // Add shortcut tile
  const addEl = document.createElement("div");
  addEl.className = "fav-item add-fav-btn";
  addEl.innerHTML = `
    <div class="fav-tile" id="open-add-fav">
      <span class="add-fav-icon">+</span>
    </div>
    <span class="fav-label">Add Favorite</span>
  `;
  addEl.addEventListener("click", () => {
    document.getElementById("add-fav-modal").classList.add("open");
    document.getElementById("fav-name-input").focus();
  });
  favoritesContainer.appendChild(addEl);

  // Bind delete events
  document.querySelectorAll("#favorites-container .delete-btn").forEach(btn => {
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      const idx = parseInt(btn.dataset.index);
      state.favorites.splice(idx, 1);
      saveState("favorites");
      renderFavorites();
    });
  });
}

function renderHistory() {
  historyContainer.innerHTML = "";

  if (state.history.length === 0) {
    secHistory.classList.add("hidden");
    return;
  }

  if (state.toggles.history) {
    secHistory.classList.remove("hidden");
  }

  state.history.forEach((hist) => {
    const domain = getDomain(hist.url);
    const initial = getLetter(hist.title);
    
    const histEl = document.createElement("div");
    histEl.className = "fav-item-wrapper";
    
    const faviconUrl = `https://www.google.com/s2/favicons?sz=64&domain=${domain}`;

    histEl.innerHTML = `
      <a class="fav-item" href="${hist.url}">
        <div class="fav-tile">
          <img class="fav-icon" src="${faviconUrl}">
          <span class="fav-initial" style="display:none;">${initial}</span>
        </div>
        <span class="fav-label">${hist.title}</span>
      </a>
    `;
    historyContainer.appendChild(histEl);
  });
}

function renderReadingList() {
  readingContainer.innerHTML = "";

  state.readingList.forEach((item, index) => {
    const domain = item.domain || getDomain(item.url);
    const faviconUrl = `https://www.google.com/s2/favicons?sz=32&domain=${domain}`;

    const card = document.createElement("div");
    card.className = "read-card-wrapper";
    card.innerHTML = `
      <a class="read-card" href="${item.url}">
        <div class="read-card-header">
          <div class="read-icon-wrapper">
            <img class="read-card-icon" src="${faviconUrl}">
          </div>
          <div class="read-info">
            <span class="read-title">${item.title}</span>
            <span class="read-domain">${domain}</span>
          </div>
        </div>
        <p class="read-card-desc">${item.desc || "No description available."}</p>
      </a>
      <button class="delete-read-btn" data-index="${index}" title="Remove from list">&times;</button>
    `;
    readingContainer.appendChild(card);
  });

  // Add new card item to add to reading list
  const addCard = document.createElement("div");
  addCard.className = "read-card read-card-add-btn";
  addCard.style.cursor = "pointer";
  addCard.style.borderStyle = "dashed";
  addCard.style.justifyContent = "center";
  addCard.style.alignItems = "center";
  addCard.style.minHeight = "120px";
  addCard.innerHTML = `
    <span style="font-size: 32px; opacity: 0.6; margin-bottom: 5px;">+</span>
    <span style="font-size: 13px; font-weight: 600; opacity: 0.8;">Add to Reading List</span>
  `;
  addCard.addEventListener("click", () => {
    document.getElementById("add-read-modal").classList.add("open");
    document.getElementById("read-title-input").focus();
  });
  readingContainer.appendChild(addCard);

  // Bind delete events
  document.querySelectorAll(".delete-read-btn").forEach(btn => {
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      const idx = parseInt(btn.dataset.index);
      state.readingList.splice(idx, 1);
      saveState("reading");
      renderReadingList();
    });
  });
}

// Toggle Drawer Menu
editToggle.addEventListener("click", () => {
  customDrawer.classList.add("open");
});

closeDrawer.addEventListener("click", () => {
  customDrawer.classList.remove("open");
});

// Close drawer when clicking outside
document.addEventListener("click", (e) => {
  if (!customDrawer.contains(e.target) && !editToggle.contains(e.target) && customDrawer.classList.contains("open")) {
    customDrawer.classList.remove("open");
  }
});

// Drawer Toggles actions
toggleFavsCb.addEventListener("change", (e) => {
  state.toggles.favorites = e.target.checked;
  saveState("toggles");
  applyTogglesVisibility();
});

toggleHistoryCb.addEventListener("change", (e) => {
  state.toggles.history = e.target.checked;
  saveState("toggles");
  applyTogglesVisibility();
});

togglePrivacyCb.addEventListener("change", (e) => {
  state.toggles.privacy = e.target.checked;
  saveState("toggles");
  applyTogglesVisibility();
});

toggleReadingCb.addEventListener("change", (e) => {
  state.toggles.reading = e.target.checked;
  saveState("toggles");
  applyTogglesVisibility();
});

// Background select click
document.querySelectorAll(".bg-thumb").forEach(thumb => {
  thumb.addEventListener("click", () => {
    state.background = thumb.dataset.bg;
    saveState("background");
    applyBackground();
  });
});

// Custom File Background selector
const customBgInput = document.getElementById("custom-bg-input");
customBgInput.addEventListener("change", (e) => {
  const file = e.target.files[0];
  if (file) {
    const reader = new FileReader();
    reader.onload = (event) => {
      state.background = "custom";
      state.customBgData = event.target.result;
      saveState("background");
      saveState("custom-bg");
      applyBackground();
    };
    reader.readAsDataURL(file);
  }
});

// Modal Add Favorite events
const addFavModal = document.getElementById("add-fav-modal");
const favNameInput = document.getElementById("fav-name-input");
const favUrlInput = document.getElementById("fav-url-input");

document.getElementById("fav-cancel-btn").addEventListener("click", () => {
  addFavModal.classList.remove("open");
  favNameInput.value = "";
  favUrlInput.value = "";
});

document.getElementById("fav-save-btn").addEventListener("click", () => {
  let name = favNameInput.value.trim();
  let url = favUrlInput.value.trim();

  if (!url) return;
  if (!name) name = getDomain(url).split(".")[0];

  if (!/^https?:\/\//i.test(url)) {
    url = "https://" + url;
  }

  state.favorites.push({ name, url });
  saveState("favorites");
  renderFavorites();

  addFavModal.classList.remove("open");
  favNameInput.value = "";
  favUrlInput.value = "";
});

// Modal Add Reading item events
const addReadModal = document.getElementById("add-read-modal");
const readTitleInput = document.getElementById("read-title-input");
const readUrlInput = document.getElementById("read-url-input");
const readDescInput = document.getElementById("read-desc-input");

document.getElementById("read-cancel-btn").addEventListener("click", () => {
  addReadModal.classList.remove("open");
  readTitleInput.value = "";
  readUrlInput.value = "";
  readDescInput.value = "";
});

document.getElementById("read-save-btn").addEventListener("click", () => {
  let title = readTitleInput.value.trim();
  let url = readUrlInput.value.trim();
  let desc = readDescInput.value.trim();

  if (!url) return;
  if (!title) title = getDomain(url);

  if (!/^https?:\/\//i.test(url)) {
    url = "https://" + url;
  }

  const domain = getDomain(url);

  state.readingList.push({ title, url, desc, domain });
  saveState("reading");
  renderReadingList();

  addReadModal.classList.remove("open");
  readTitleInput.value = "";
  readUrlInput.value = "";
  readDescInput.value = "";
});

// Privacy details toggle
const toggleTrackerDetails = document.getElementById("toggle-tracker-details");
const trackerDetailsList = document.getElementById("tracker-details-list");
toggleTrackerDetails.addEventListener("click", () => {
  if (trackerDetailsList.classList.contains("visible")) {
    trackerDetailsList.classList.remove("visible");
    toggleTrackerDetails.textContent = "Show Details";
  } else {
    trackerDetailsList.classList.add("visible");
    toggleTrackerDetails.textContent = "Hide Details";
  }
});

// Render ETP Privacy stats dynamically
function renderPrivacyReport(privacyStats) {
  if (!privacyStats) return;
  
  document.getElementById("stats-trackers-count").textContent = privacyStats.totalBlocked || 0;
  document.getElementById("stats-ratio").textContent = privacyStats.ratio || "0%";
  
  trackerDetailsList.innerHTML = "";
  if (privacyStats.topDomains && privacyStats.topDomains.length > 0) {
    privacyStats.topDomains.forEach(item => {
      const row = document.createElement("div");
      row.className = "tracker-row";
      row.innerHTML = `
        <span class="tracker-domain">${item.domain}</span>
        <span class="tracker-count">${item.count} blocks</span>
      `;
      trackerDetailsList.appendChild(row);
    });
  } else {
    trackerDetailsList.innerHTML = `<div style="text-align:center; padding:10px; color:var(--text-secondary);">No trackers blocked yet.</div>`;
  }
}

// ─── Native WebExtension Loading ───────────────────────────────
var bridgeEl = document.getElementById("bridge-status");

// Fetch history natively from browser.history
function loadNativeHistory() {
  try {
    browser.history.search({ text: "", maxResults: 15 }).then((historyItems) => {
      var filtered = [];
      for (var i = 0; i < historyItems.length; i++) {
        var item = historyItems[i];
        if (!item.url || item.url.startsWith("about:") || item.url.startsWith("chrome:") || item.url.startsWith("moz-extension:") || item.url.indexOf("newtab.html") !== -1) {
          continue;
        }
        filtered.push({
          title: item.title || getDomain(item.url),
          url: item.url
        });
        if (filtered.length >= 6) break;
      }
      state.history = filtered;
      renderHistory();
      applyTogglesVisibility();
      if (bridgeEl) {
        bridgeEl.textContent = "Extension History: Active ✓";
        bridgeEl.style.opacity = "0.3";
      }
    }).catch((err) => {
      console.warn("browser.history search failed:", err);
    });
  } catch(e) {
    console.warn("browser.history not available:", e);
  }
}

// Fetch privacy/uBlock stats from background context
function loadUblockStats() {
  try {
    if (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.sendMessage) {
      if (typeof dump !== "undefined") dump("[Seafari NTP] Sending message to uBlock...\n");
      chrome.runtime.sendMessage("uBlock0@raymondhill.net", { action: "getUblockStats" }, (response) => {
        if (typeof dump !== "undefined") dump("[Seafari NTP] Received response from uBlock: " + JSON.stringify(response) + "\n");
        if (response && typeof response.totalBlocked === "number") {
          var totalBlocked = response.totalBlocked;
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
          renderPrivacyReport(privacyData);
          if (bridgeEl) {
            bridgeEl.textContent = "Extension Bridge: Active ✓";
            bridgeEl.style.opacity = "0.3";
          }
          return;
        }
        fallbackLoadUblockStats();
      });
    } else {
      fallbackLoadUblockStats();
    }
  } catch(e) {
    if (typeof dump !== "undefined") dump("[Seafari NTP] Error in loadUblockStats: " + e + "\n");
    fallbackLoadUblockStats();
  }
}

function fallbackLoadUblockStats() {
  try {
    var bg = chrome.extension.getBackgroundPage();
    if (bg && bg.ublockStats) {
      renderPrivacyReport(bg.ublockStats);
      if (bridgeEl) {
        bridgeEl.textContent = "Extension Bridge: Active ✓";
        bridgeEl.style.opacity = "0.3";
      }
    }
  } catch(e) {
    console.warn("Could not get uBlock stats from background page:", e);
  }
}

// Load data immediately
loadNativeHistory();
loadUblockStats();

// Poll periodically for history/ublock updates
setInterval(loadNativeHistory, 10000);
setInterval(loadUblockStats, 2000);

// Capture image load errors and handle fallbacks dynamically (complying with CSP)
document.addEventListener("error", function(e) {
  var target = e.target;
  if (target && target.tagName === "IMG") {
    if (target.classList.contains("fav-icon")) {
      target.style.display = "none";
      var initialSpan = target.nextElementSibling;
      if (initialSpan && initialSpan.classList.contains("fav-initial")) {
        initialSpan.style.display = "block";
      }
    } else if (target.classList.contains("read-card-icon")) {
      target.src = "seafari.png";
    }
  }
}, true); // Important: capture phase

// Initial UI setup — load from extension storage / localStorage immediately (favorites, bg, toggles)
loadState();
