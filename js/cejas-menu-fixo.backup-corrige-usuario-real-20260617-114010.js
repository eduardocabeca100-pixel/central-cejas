(function () {
  if (window.__CEJAS_MENU_FIXO__) return;
  window.__CEJAS_MENU_FIXO__ = true;

  const MENU_COMERCIAL = [
    { href: "/dashboard.html", texto: "▦ Painel Geral" },
    { href: "/agenda.html", texto: "◫ Agenda Dinâmica" },
    { href: "/painel-dia.html", texto: "▣ Painel do Dia" },
    { href: "/chat.html", texto: "💬 Chat Interno" },
    { href: "/orcamentos.html", texto: "◉ Orçamentos" },
    { href: "/tarefas.html", texto: "☑ Tarefas Pendentes" },
    { href: "/servidor.html", texto: "▣ Servidor" },
    { href: "/contratos.html", texto: "Contratos" }
  ];

  const ADMIN_HREFS = [
    "configuracoes",
    "usuarios",
    "importar-relatorio"
  ];

  const ADMIN_TEXTOS = [
    "configurações",
    "configuracoes",
    "acessos",
    "usuários",
    "usuarios",
    "importar relatório",
    "importar relatorio"
  ];

  let ultimoUsuario = null;
  let ultimoMenu = null;

  function ativo(href) {
    return location.pathname.replace(/\/+$/, "") === href;
  }

  function htmlMenu(itens) {
    return itens.map((item) => `
      <a href="${item.href}" class="${ativo(item.href) ? "active" : ""}">
        ${item.texto}
      </a>
    `).join("");
  }

  function limparAdministrativo(usuario) {
    if (usuario?.superadmin) return;

    document.querySelectorAll("aside a, nav a, main a").forEach((a) => {
      const href = String(a.getAttribute("href") || "").toLowerCase();
      const texto = String(a.textContent || "").toLowerCase();

      const adminHref = ADMIN_HREFS.some((x) => href.includes(x));
      const adminTexto = ADMIN_TEXTOS.some((x) => texto.includes(x));

      if (adminHref || adminTexto) {
        const dentroMenu = Boolean(a.closest("aside") || a.closest("nav"));

        if (dentroMenu) {
          a.remove();
        } else {
          const card = a.closest(".card, article, section, div");
          if (card && !card.closest("aside")) card.remove();
          else a.remove();
        }
      }
    });
  }

  function removerCardsExtrasPainelDia() {
    document.querySelectorAll('[data-card-painel-dia="true"]').forEach((el) => el.remove());

    document.querySelectorAll('main a[href="/painel-dia.html"], main a[href="painel-dia.html"]').forEach((a) => {
      const card = a.closest(".card, article, section, div");
      if (card) card.remove();
      else a.remove();
    });
  }

  function atualizarUsuario(usuario) {
    if (!usuario) return;

    const nome = usuario.nome || "Usuário";
    const cargo = usuario.superadmin ? "Superadmin" : usuario.cargo || "Comercial";

    document.querySelectorAll(".user strong, #usuarioNome").forEach((el) => {
      el.textContent = nome;
    });

    document.querySelectorAll(".user span, #usuarioCargo").forEach((el) => {
      el.textContent = cargo;
    });

    document.querySelectorAll(".user").forEach((box) => {
      const strong = box.querySelector("strong");
      const span = box.querySelector("span");

      if (strong) strong.textContent = nome;
      if (span) span.textContent = cargo;
    });

    document.querySelectorAll(".avatar, .logo-user-avatar").forEach((avatar) => {
      const txt = String(avatar.textContent || "").trim();
      if (txt.length <= 2) {
        avatar.textContent = nome.slice(0, 1).toUpperCase();
      }
    });
  }

  async function buscarMenu() {
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
      menu: MENU_COMERCIAL
    };
  }

  async function aplicarMenu(forcar = false) {
    const aside = document.querySelector("aside");
    if (!aside) return;

    let nav = aside.querySelector("nav");

    if (!nav) {
      nav = document.createElement("nav");
      aside.appendChild(nav);
    }

    if (forcar || !ultimoMenu || !ultimoUsuario) {
      const dados = await buscarMenu();
      ultimoUsuario = dados.usuario || { nome: "Usuário", cargo: "Comercial", superadmin: false };
      ultimoMenu = dados.menu || MENU_COMERCIAL;
    }

    nav.innerHTML = htmlMenu(ultimoMenu);

    atualizarUsuario(ultimoUsuario);
    limparAdministrativo(ultimoUsuario);
    removerCardsExtrasPainelDia();
  }

  document.addEventListener("DOMContentLoaded", () => {
    aplicarMenu(true);

    // Impede scripts antigos de recolocarem itens administrativos depois.
    setTimeout(() => aplicarMenu(false), 300);
    setTimeout(() => aplicarMenu(false), 900);
    setTimeout(() => aplicarMenu(false), 1800);
    setInterval(() => {
      atualizarUsuario(ultimoUsuario);
      limparAdministrativo(ultimoUsuario);
      removerCardsExtrasPainelDia();
    }, 1500);
  });
})();
