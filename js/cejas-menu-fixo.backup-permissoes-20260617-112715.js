(function () {
  if (window.__CEJAS_MENU_FIXO__) return;
  window.__CEJAS_MENU_FIXO__ = true;

  const itens = [
    { href: "/dashboard.html", texto: "▦ Painel Geral" },
    { href: "/agenda.html", texto: "◫ Agenda Dinâmica" },
    { href: "/painel-dia.html", texto: "▣ Painel do Dia" },
    { href: "/chat.html", texto: "💬 Chat Interno" },
    { href: "/orcamentos.html", texto: "◉ Orçamentos" },
    { href: "/importar-relatorio.html", texto: "▤ Importar Relatório (PDF)" },
    { href: "/tarefas.html", texto: "☑ Tarefas Pendentes" },
    { href: "/servidor.html", texto: "▣ Servidor" },
    { href: "/usuarios.html", texto: "◦ Acessos / Usuários" },
    { href: "/contratos.html", texto: "Contratos" },
    { href: "/configuracoes.html", texto: "⚙ Configurações" }
  ];

  function ativo(href) {
    const atual = location.pathname.replace(/\/+$/, "");
    return atual === href;
  }

  function criarNav() {
    return itens.map((item) => `
      <a href="${item.href}" class="${ativo(item.href) ? "active" : ""}">
        ${item.texto}
      </a>
    `).join("");
  }

  function removerCardsExtrasPainelDia() {
    document.querySelectorAll('a[href="/painel-dia.html"], a[href="painel-dia.html"]').forEach((a) => {
      const dentroMenu = Boolean(a.closest("aside nav"));
      if (dentroMenu) return;

      const texto = String(a.textContent || "").toLowerCase();

      if (texto.includes("abrir painel") || texto.includes("painel do dia")) {
        const card = a.closest("[data-card-painel-dia], article, section, .card, div");

        if (card && !card.closest("aside nav")) {
          card.remove();
        } else {
          a.remove();
        }
      }
    });

    document.querySelectorAll('[data-card-painel-dia="true"]').forEach((el) => el.remove());
  }

  function aplicarMenu() {
    const aside = document.querySelector("aside");
    if (!aside) return;

    let nav = aside.querySelector("nav");

    if (!nav) {
      nav = document.createElement("nav");
      aside.appendChild(nav);
    }

    nav.innerHTML = criarNav();

    removerCardsExtrasPainelDia();
  }

  document.addEventListener("DOMContentLoaded", () => {
    aplicarMenu();
    setTimeout(aplicarMenu, 300);
    setTimeout(aplicarMenu, 1000);
  });
})();
