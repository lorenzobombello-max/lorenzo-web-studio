(() => {
  const documentRoot = document.documentElement;
  const menu = document.getElementById("primaryNav");
  const menuToggle = document.querySelector("[data-menu-toggle]");
  const productGrid = document.querySelector("[data-product-grid]");
  const products = [...document.querySelectorAll("[data-product]")];
  const panel = document.querySelector("[data-panel]");
  const panelContent = document.querySelector("[data-panel-content]");
  const toast = document.querySelector("[data-toast]");
  const wishlist = new Set();
  let cartCount = 0;
  let toastTimer;

  const refreshIcons = () => window.lucide?.createIcons({ attrs: { "aria-hidden": "true" } });
  const showToast = (message) => {
    toast.textContent = message;
    toast.classList.add("is-visible");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove("is-visible"), 2200);
  };
  const openPanel = (content) => {
    panelContent.innerHTML = content;
    panel.showModal();
    document.body.classList.add("is-locked");
    refreshIcons();
  };
  const closePanel = () => {
    panel.close();
    document.body.classList.remove("is-locked");
  };

  document.querySelector("[data-close-announcement]")?.addEventListener("click", (event) => {
    event.currentTarget.closest(".announcement").remove();
  });
  menuToggle?.addEventListener("click", () => {
    const isOpen = menu.classList.toggle("is-open");
    menuToggle.setAttribute("aria-expanded", String(isOpen));
  });
  menu?.addEventListener("click", (event) => {
    if (event.target.closest("a")) {
      menu.classList.remove("is-open");
      menuToggle.setAttribute("aria-expanded", "false");
    }
  });

  const applyFilter = (category) => {
    let visible = 0;
    products.forEach((product) => {
      product.hidden = category !== "all" && product.dataset.category !== category && category !== "clothing";
      if (!product.hidden) visible += 1;
    });
    document.querySelector("[data-result-count]").textContent = String(visible);
    document.querySelector("[data-empty-state]").hidden = visible !== 0;
    document.querySelectorAll("[data-filter]").forEach((button) => button.classList.toggle("is-selected", button.dataset.filter === category));
  };
  document.querySelectorAll("[data-filter]").forEach((button) => button.addEventListener("click", () => applyFilter(button.dataset.filter)));
  document.querySelectorAll("[data-filter-link]").forEach((link) => link.addEventListener("click", () => applyFilter(link.dataset.filterLink)));
  document.querySelector("[data-sort]")?.addEventListener("change", (event) => {
    const mode = event.target.value;
    const sorted = [...products].sort((left, right) => {
      if (mode === "low") return Number(left.dataset.price) - Number(right.dataset.price);
      if (mode === "high") return Number(right.dataset.price) - Number(left.dataset.price);
      return products.indexOf(left) - products.indexOf(right);
    });
    sorted.forEach((product) => productGrid.append(product));
  });

  document.querySelectorAll("[data-wishlist]").forEach((button) => button.addEventListener("click", () => {
    const product = button.closest("[data-product]");
    const name = product.dataset.name;
    if (wishlist.has(name)) wishlist.delete(name); else wishlist.add(name);
    button.classList.toggle("is-saved", wishlist.has(name));
    button.setAttribute("aria-label", `${wishlist.has(name) ? "Remove" : "Save"} ${name}`);
    document.querySelector("[data-wishlist-count]").textContent = String(wishlist.size);
    showToast(wishlist.has(name) ? "Saved to your edit" : "Removed from your edit");
  }));

  document.querySelectorAll("[data-quick-view]").forEach((button) => button.addEventListener("click", () => {
    const product = button.closest("[data-product]");
    const image = product.querySelector("img");
    const detail = product.querySelector(".product-card__details");
    openPanel(`<article class="panel__product"><img src="${image.src}" alt="${image.alt}"><div><p class="eyebrow">Aldara Atelier</p><h2>${product.dataset.name}</h2><p>${detail.querySelector("div p").textContent} · €${product.dataset.price}</p><button type="button" data-add-cart>Add to bag</button></div></article>`);
    panel.querySelector("[data-add-cart]").addEventListener("click", () => {
      cartCount += 1;
      document.querySelector("[data-cart-count]").textContent = String(cartCount);
      closePanel();
      showToast(`${product.dataset.name} added to bag`);
    });
  }));

  document.querySelectorAll("[data-open-search]").forEach((button) => button.addEventListener("click", () => {
    openPanel(`<div class="panel__body"><p class="eyebrow">Find a piece</p><h2>Search Aldara</h2><p>Search the current edit by name, material or category.</p><form data-search-form><input name="query" type="search" placeholder="Try “silk”" aria-label="Search products" autofocus><button type="submit" aria-label="Submit search"><i data-lucide="arrow-right"></i></button></form></div>`);
    const input = panel.querySelector("input");
    input.focus();
    panel.querySelector("[data-search-form]").addEventListener("submit", (event) => {
      event.preventDefault();
      const query = new FormData(event.currentTarget).get("query").toString().trim().toLowerCase();
      let visible = 0;
      products.forEach((product) => {
        product.hidden = !product.textContent.toLowerCase().includes(query);
        if (!product.hidden) visible += 1;
      });
      document.querySelector("[data-result-count]").textContent = String(visible);
      document.querySelector("[data-empty-state]").hidden = visible !== 0;
      closePanel();
      document.querySelector("#catalog").scrollIntoView();
    });
  }));

  document.querySelector("[data-open-wishlist]")?.addEventListener("click", () => openPanel(`<div class="panel__body"><p class="eyebrow">Your edit</p><h2>Saved pieces</h2><p>${wishlist.size ? [...wishlist].join("<br>") : "No pieces saved yet."}</p></div>`));
  document.querySelector("[data-open-cart]")?.addEventListener("click", () => openPanel(`<div class="panel__body"><p class="eyebrow">Shopping bag</p><h2>${cartCount ? `${cartCount} ${cartCount === 1 ? "piece" : "pieces"}` : "Your bag is empty"}</h2><p>${cartCount ? "Your selection is reserved for this browsing session." : "Open a piece to add it to your bag."}</p></div>`));
  document.querySelector("[data-open-account]")?.addEventListener("click", () => openPanel(`<div class="panel__body"><p class="eyebrow">Client account</p><h2>Welcome back</h2><p>Account access is available to Aldara clients.</p><form><input type="email" placeholder="Email address" aria-label="Email address"><button type="submit" aria-label="Continue"><i data-lucide="arrow-right"></i></button></form></div>`));
  document.querySelector("[data-close-panel]")?.addEventListener("click", closePanel);
  panel?.addEventListener("click", (event) => { if (event.target === panel) closePanel(); });
  panel?.addEventListener("close", () => document.body.classList.remove("is-locked"));

  documentRoot.classList.add("is-ready");
  refreshIcons();
})();