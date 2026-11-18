document.addEventListener("DOMContentLoaded", () => {
  const grid = document.getElementById("grid");
  const searchInput = document.getElementById("search");
  const tabCountEl = document.getElementById("tab-count");
  let allTabs = [];
  let allPreviews = {};

  function getDomain(url) {
    try {
      if (!url) return "";
      const parsed = new URL(url);
      return parsed.hostname.replace(/^www\./, "");
    } catch(e) {
      return "";
    }
  }

  function escapeHtml(str) {
    if (!str) return "";
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function loadTabs() {
    browser.runtime.sendMessage({ action: "getTabs" }).then((response) => {
      // Filter out overview page itself so it NEVER appears
      allTabs = (response.tabs || []).filter(tab => {
        if (!tab.url) return true;
        if (tab.url.includes("overview.html")) return false;
        return true;
      });
      allPreviews = response.previews || {};
      renderTabs();
    });
  }

  function renderTabs() {
    const query = searchInput.value.toLowerCase().trim();
    grid.innerHTML = "";

    const filteredTabs = allTabs.filter(tab => {
      const titleMatch = tab.title && tab.title.toLowerCase().includes(query);
      const urlMatch = tab.url && tab.url.toLowerCase().includes(query);
      return titleMatch || urlMatch;
    });

    if (tabCountEl) {
      tabCountEl.textContent = filteredTabs.length;
    }

    if (filteredTabs.length === 0) {
      const empty = document.createElement("div");
      empty.className = "empty-state";
      empty.textContent = query ? "No se encontraron pestañas coincidentes" : "No hay pestañas abiertas";
      grid.appendChild(empty);
      return;
    }

    filteredTabs.forEach(tab => {
      const card = document.createElement("div");
      card.className = "card" + (tab.active ? " active-tab" : "");
      card.setAttribute("data-tab-id", tab.id);

      const previewSrc = allPreviews[tab.id];
      const domain = getDomain(tab.url);
      const favIcon = tab.favIconUrl || "../MacTahoe/icons/globe.svg";

      let previewHTML = "";
      if (previewSrc) {
        previewHTML = `<img class="preview-img" src="${previewSrc}" alt="" loading="lazy">`;
      } else {
        previewHTML = `
          <div class="empty-preview">
            <img class="empty-preview-icon" src="${favIcon}" onerror="this.src='../MacTahoe/icons/globe.svg'" alt="">
            <span class="empty-preview-host">${escapeHtml(domain || tab.title || "Nueva pestaña")}</span>
          </div>
        `;
      }

      card.innerHTML = `
        <div class="card-header">
          <div class="card-title-group">
            <img class="favicon" src="${favIcon}" onerror="this.src='../MacTahoe/icons/globe.svg'" alt="">
            <span class="card-title">${escapeHtml(tab.title || domain || "Nueva pestaña")}</span>
          </div>
          <button class="close-btn" data-id="${tab.id}" title="Cerrar pestaña" aria-label="Cerrar pestaña">
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
              <line x1="18" y1="6" x2="6" y2="18"></line>
              <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
          </button>
        </div>
        <div class="preview-container">
          ${previewHTML}
        </div>
      `;

      // Select tab click listener
      card.addEventListener("click", (e) => {
        if (e.target.closest(".close-btn")) return;
        browser.runtime.sendMessage({ action: "selectTab", tabId: tab.id });
      });

      // Close tab click listener
      const closeBtn = card.querySelector(".close-btn");
      closeBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        const tabId = parseInt(closeBtn.getAttribute("data-id"), 10);
        browser.runtime.sendMessage({ action: "closeTab", tabId: tabId }).then(() => {
          allTabs = allTabs.filter(t => t.id !== tabId);
          renderTabs();
        });
      });

      grid.appendChild(card);
    });
  }

  // Search input handler
  searchInput.addEventListener("input", renderTabs);

  // Close overview when pressing Escape
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      browser.tabs.getCurrent().then(tab => {
        if (tab && tab.id) {
          browser.tabs.remove(tab.id);
        }
      });
    }
  });

  loadTabs();
});
