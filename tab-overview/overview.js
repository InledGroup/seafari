document.addEventListener("DOMContentLoaded", () => {
  const grid = document.getElementById("grid");
  const searchInput = document.getElementById("search");
  let allTabs = [];
  let allPreviews = {};

  function loadTabs() {
    browser.runtime.sendMessage({ action: "getTabs" }).then((response) => {
      allTabs = response.tabs;
      allPreviews = response.previews;
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

    filteredTabs.forEach(tab => {
      const card = document.createElement("div");
      card.className = "card";
      
      const previewSrc = allPreviews[tab.id];
      let previewHTML = "";
      if (previewSrc) {
        previewHTML = `<img class="preview-img" src="${previewSrc}">`;
      } else {
        previewHTML = `<div class="placeholder">No preview available</div>`;
      }

      const favIcon = tab.favIconUrl || "../MacTahoe/icons/globe.svg";

      card.innerHTML = `
        <div class="card-header">
          <div class="card-title-group">
            <img class="favicon" src="${favIcon}" onerror="this.src='../MacTahoe/icons/globe.svg'">
            <span class="card-title">${tab.title || "New Tab"}</span>
          </div>
          <button class="close-btn" data-id="${tab.id}">&#10005;</button>
        </div>
        <div class="preview-container">
          ${previewHTML}
        </div>
      `;

      // Select tab click listener
      card.addEventListener("click", (e) => {
        if (e.target.classList.contains("close-btn")) return;
        browser.runtime.sendMessage({ action: "selectTab", tabId: tab.id });
      });

      // Close tab click listener
      card.querySelector(".close-btn").addEventListener("click", (e) => {
        e.stopPropagation();
        const tabId = parseInt(e.target.dataset.id);
        browser.runtime.sendMessage({ action: "closeTab", tabId: tabId }).then(() => {
          allTabs = allTabs.filter(t => t.id !== tabId);
          renderTabs();
        });
      });

      grid.appendChild(card);
    });
  }

  searchInput.addEventListener("input", renderTabs);

  loadTabs();
});
