(function () {
  if (window.__CEJAS_MENU_FIX__) return;
  window.__CEJAS_MENU_FIX__ = true;

  function corrigirMenu() {
    // Remove cards/links extras do Painel do Dia fora do menu lateral.
    document.querySelectorAll('a[href="/painel-dia.html"], a[href="painel-dia.html"]').forEach((a) => {
      const dentroMenu = Boolean(a.closest("aside") || a.closest("nav"));

      if (!dentroMenu) {
        const card = a.closest("[data-card-painel-dia], .card, article, section, div");
        if (card && !card.closest("aside") && !card.closest("nav")) {
          card.remove();
        } else {
          a.remove();
        }
      }
    });

    const menu = document.querySelector("aside nav") || document.querySelector("aside");

    if (!menu) return;

    let link = menu.querySelector('a[href="/painel-dia.html"], a[href="painel-dia.html"]');

    if (!link) {
      link = document.createElement("a");
      link.href = "/painel-dia.html";
      link.textContent = "▣ Painel do Dia";

      const agenda = Array.from(menu.querySelectorAll("a")).find((a) =>
        String(a.textContent || "").toLowerCase().includes("agenda")
      );

      if (agenda) {
        agenda.insertAdjacentElement("afterend", link);
      } else {
        menu.appendChild(link);
      }
    }

    if (location.pathname.includes("painel-dia")) {
      link.classList.add("active");
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    corrigirMenu();
    setTimeout(corrigirMenu, 300);
    setTimeout(corrigirMenu, 1200);
  });
})();
