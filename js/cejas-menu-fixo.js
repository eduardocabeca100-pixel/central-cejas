(function () {
  if (window.__CEJAS_MENU_FIXO_ESTAVEL__) return;
  window.__CEJAS_MENU_FIXO_ESTAVEL__ = true;

  const MENU_BASE = [
    { href: "/dashboard.html", texto: "▦ Painel Geral" },
    { href: "/agenda.html", texto: "◫ Agenda Dinâmica" },
    { href: "/painel-dia.html", texto: "▣ Painel do Dia" },
    { href: "/chat.html", texto: "💬 Chat Interno" },
    { href: "/orcamentos.html", texto: "◉ Orçamentos" },
    { href: "/financeiro.html", texto: "💰 Financeiro" },
    { href: "/tarefas.html", texto: "☑ Tarefas Pendentes" },
    { href: "/servidor.html", texto: "▣ Servidor" },
    { href: "/contratos.html", texto: "Contratos" }
  ];

  const MENU_ADMIN = [
    { href: "/importar-relatorio.html", texto: "▤ Importar Relatório (PDF)" },
    { href: "/usuarios.html", texto: "◦ Acessos / Usuários" },
    { href: "/configuracoes.html", texto: "⚙ Configurações" }
  ];

  const ADMIN_HREFS = ["configuracoes", "usuarios", "importar-relatorio"];

  function normalizarPath(path) {
    return String(path || "").replace(/\/+$/, "");
  }

  function htmlMenu(menu) {
    const atual = normalizarPath(location.pathname);

    return menu.map((item) => {
      const ativo = normalizarPath(item.href) === atual ? "active" : "";

      return `<a href="${item.href}" class="${ativo}">${item.texto}</a>`;
    }).join("");
  }

  function limparAjuda() {
    document.querySelectorAll("aside *").forEach((el) => {
      const texto = String(el.textContent || "").toLowerCase();

      if (texto.includes("precisa de ajuda")) {
        const card = el.closest(".help, .ajuda, .support, .card, div");
        if (card) card.remove();
      }
    });
  }

  function atualizarUsuario(usuario) {
    const nome = usuario?.nome || usuario?.name || "Eduardo";
    const cargo = usuario?.superadmin ? "Superadmin" : (usuario?.cargo || "Superadmin");

    document.querySelectorAll("#usuarioNome, aside .user strong").forEach((el) => {
      el.textContent = nome;
    });

    document.querySelectorAll("#usuarioCargo, aside .user span").forEach((el) => {
      el.textContent = cargo;
    });

    document.querySelectorAll("aside .avatar, aside .user-avatar").forEach((el) => {
      el.textContent = nome.charAt(0).toUpperCase();
    });
  }

  async function buscarUsuario() {
    try {
      const res = await fetch("/api/menu-usuario-atual?ts=" + Date.now(), {
        cache: "no-store",
        credentials: "same-origin"
      });

      const dados = await res.json();

      if (dados && dados.ok) {
        return dados.usuario || {};
      }
    } catch {}

    return { nome: "Eduardo", cargo: "Superadmin", superadmin: true };
  }

  async function iniciar() {
    const aside = document.querySelector("aside");
    if (!aside) return;

    let nav = aside.querySelector("nav");

    if (!nav) {
      nav = document.createElement("nav");
      aside.appendChild(nav);
    }

    const usuario = await buscarUsuario();
    const superadmin = Boolean(usuario.superadmin);

    const menu = superadmin ? [...MENU_BASE, ...MENU_ADMIN] : MENU_BASE;
    const novoHtml = htmlMenu(menu);

    if (nav.innerHTML.trim() !== novoHtml.trim()) {
      nav.innerHTML = novoHtml;
    }

    atualizarUsuario(usuario);
    limparAjuda();

    // Garantia única, sem intervalo infinito/piscando
    setTimeout(() => {
      atualizarUsuario(usuario);
      limparAjuda();
    }, 500);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", iniciar);
  } else {
    iniciar();
  }
})();
