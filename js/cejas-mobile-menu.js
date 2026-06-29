(function () {
  if (window.__CEJAS_MOBILE_MENU__) return;
  window.__CEJAS_MOBILE_MENU__ = true;

  function normalizar(path) {
    return String(path || "").replace(/\/+$/, "");
  }

  function montarLinks() {
    const aside = document.querySelector("aside, .sidebar");
    const nav = aside && (aside.querySelector("nav") || aside.querySelector(".nav"));
    const links = nav ? [...nav.querySelectorAll("a")] : [];

    if (links.length) {
      return links.map((a) => ({ href: a.getAttribute("href"), texto: a.textContent.trim() })).filter(item => item.href);
    }

    return [
      { href: "/dashboard.html", texto: "▦ Painel Geral" },
      { href: "/agenda.html", texto: "◫ Agenda Dinâmica" },
      { href: "/painel-dia.html", texto: "▣ Painel do Dia" },
      { href: "/chat.html", texto: "💬 Chat Interno" },
      { href: "/orcamentos.html", texto: "◉ Orçamentos" },
      { href: "/financeiro.html", texto: "💰 Financeiro" },
      { href: "/gratuidades.html", texto: "🏷 Gratuidades" },
      { href: "/tarefas.html", texto: "☑ Tarefas" },
      { href: "/servidor.html", texto: "▣ Servidor" },
      { href: "/importar-relatorio.html", texto: "▤ Importar Relatório" },
      { href: "/usuarios.html", texto: "◦ Usuários" },
      { href: "/configuracoes.html", texto: "⚙ Configurações" }
    ];
  }

  function iniciar() {
    if (document.querySelector(".cejas-mobile-menu-btn")) return;
    if (location.pathname.includes("login")) return;

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "cejas-mobile-menu-btn";
    btn.textContent = "☰ Menu";

    const overlay = document.createElement("div");
    overlay.className = "cejas-mobile-overlay";

    const drawer = document.createElement("div");
    drawer.className = "cejas-mobile-drawer";

    function render() {
      const atual = normalizar(location.pathname);
      const links = montarLinks();
      drawer.innerHTML = `
        <strong>Sistema CEJAS</strong>
        <nav>
          ${links.map(item => {
            const active = normalizar(item.href) === atual ? "active" : "";
            return `<a class="${active}" href="${item.href}">${item.texto}</a>`;
          }).join("")}
        </nav>
      `;
    }

    function abrir() {
      render();
      overlay.classList.add("ativo");
      drawer.classList.add("ativo");
    }

    function fechar() {
      overlay.classList.remove("ativo");
      drawer.classList.remove("ativo");
    }

    btn.addEventListener("click", abrir);
    overlay.addEventListener("click", fechar);
    drawer.addEventListener("click", (event) => {
      if (event.target.closest("a")) fechar();
    });

    document.body.appendChild(btn);
    document.body.appendChild(overlay);
    document.body.appendChild(drawer);

    render();
    setTimeout(render, 700);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", iniciar);
  } else {
    iniciar();
  }
})();
