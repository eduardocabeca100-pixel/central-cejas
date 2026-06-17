(function () {
  if (window.__CEJAS_MENU_FIXO__) return;
  window.__CEJAS_MENU_FIXO__ = true;

  const MENU_FALLBACK_COMERCIAL = [
    { href: "/dashboard.html", texto: "▦ Painel Geral" },
    { href: "/agenda.html", texto: "◫ Agenda Dinâmica" },
    { href: "/painel-dia.html", texto: "▣ Painel do Dia" },
    { href: "/chat.html", texto: "💬 Chat Interno" },
    { href: "/orcamentos.html", texto: "◉ Orçamentos" },
    { href: "/tarefas.html", texto: "☑ Tarefas Pendentes" },
    { href: "/servidor.html", texto: "▣ Servidor" },
    { href: "/contratos.html", texto: "Contratos" }
  ];

  function ativo(href) {
    const atual = location.pathname.replace(/\/+$/, "");
    return atual === href;
  }

  function htmlMenu(itens) {
    return itens.map((item) => `
      <a href="${item.href}" class="${ativo(item.href) ? "active" : ""}">
        ${item.texto}
      </a>
    `).join("");
  }

  function removerCardsExtrasPainelDia() {
    document.querySelectorAll('[data-card-painel-dia="true"]').forEach((el) => el.remove());

    document.querySelectorAll('a[href="/painel-dia.html"], a[href="painel-dia.html"]').forEach((a) => {
      const dentroMenu = Boolean(a.closest("aside nav"));
      if (dentroMenu) return;

      const card = a.closest(".card, article, section, div");

      if (card && !card.closest("aside nav")) {
        const texto = String(card.textContent || "").toLowerCase();
        if (texto.includes("painel do dia") || texto.includes("visão operacional")) {
          card.remove();
        }
      }
    });
  }

  function atualizarUsuario(usuario) {
    if (!usuario) return;

    const nomes = document.querySelectorAll(".user strong, #usuarioNome");
    const cargos = document.querySelectorAll(".user span, #usuarioCargo");

    nomes.forEach((el) => {
      el.textContent = usuario.nome || "Usuário";
    });

    cargos.forEach((el) => {
      el.textContent = usuario.superadmin ? "Superadmin" : usuario.cargo || "Comercial";
    });

    const avatar = document.querySelector(".user .avatar, .user-card .avatar");
    if (avatar) {
      avatar.textContent = String(usuario.nome || "U").slice(0, 1).toUpperCase();
    }
  }

  async function carregarMenu() {
    try {
      const resposta = await fetch("/api/menu-usuario-atual?ts=" + Date.now(), {
        cache: "no-store"
      });

      const dados = await resposta.json();

      if (dados.ok && Array.isArray(dados.menu)) {
        return dados;
      }
    } catch {}

    return {
      ok: true,
      usuario: {
        nome: "Usuário",
        cargo: "Comercial",
        superadmin: false
      },
      menu: MENU_FALLBACK_COMERCIAL
    };
  }

  async function aplicarMenu() {
    const aside = document.querySelector("aside");
    if (!aside) return;

    let nav = aside.querySelector("nav");

    if (!nav) {
      nav = document.createElement("nav");
      aside.appendChild(nav);
    }

    const dados = await carregarMenu();

    nav.innerHTML = htmlMenu(dados.menu || MENU_FALLBACK_COMERCIAL);

    atualizarUsuario(dados.usuario);
    removerCardsExtrasPainelDia();

    // Segurança visual: se não for superadmin, remove qualquer link administrativo
    // que outra parte antiga do sistema tente inserir depois.
    if (!dados.usuario?.superadmin) {
      nav.querySelectorAll("a").forEach((a) => {
        const href = a.getAttribute("href") || "";
        const texto = String(a.textContent || "").toLowerCase();

        if (
          href.includes("configuracoes") ||
          href.includes("usuarios") ||
          href.includes("importar-relatorio") ||
          texto.includes("configurações") ||
          texto.includes("acessos") ||
          texto.includes("importar relatório")
        ) {
          a.remove();
        }
      });
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    aplicarMenu();
    setTimeout(aplicarMenu, 400);
    setTimeout(aplicarMenu, 1200);
    setTimeout(aplicarMenu, 2500);
  });
})();
