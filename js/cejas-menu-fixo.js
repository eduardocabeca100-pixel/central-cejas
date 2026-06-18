(function () {
  if (window.__CEJAS_MENU_FIXO__) return;
  window.__CEJAS_MENU_FIXO__ = true;

  const MENU_OPERACIONAL = [
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

  const ADMIN_HREFS = ["configuracoes", "usuarios", "importar-relatorio"];
  const ADMIN_TEXTOS = ["configurações", "configuracoes", "acessos", "usuários", "usuarios", "importar relatório", "importar relatorio"];

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
    if (usuario && usuario.superadmin) return;

    document.querySelectorAll("aside a, nav a").forEach((a) => {
      const href = String(a.getAttribute("href") || "").toLowerCase();
      const texto = String(a.textContent || "").toLowerCase();

      const adminHref = ADMIN_HREFS.some((x) => href.includes(x));
      const adminTexto = ADMIN_TEXTOS.some((x) => texto.includes(x));

      if (adminHref || adminTexto) a.remove();
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
      menu: MENU_OPERACIONAL
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

    if (forcar || !ultimoUsuario || !ultimoMenu) {
      const dados = await buscarMenu();
      ultimoUsuario = dados.usuario || { nome: "Usuário", cargo: "Comercial", superadmin: false };
      ultimoMenu = dados.menu || MENU_OPERACIONAL;
    }

    if (!ultimoUsuario.superadmin) {
      ultimoMenu = ultimoMenu.filter((item) => {
        const href = String(item.href || "").toLowerCase();
        const texto = String(item.texto || "").toLowerCase();

        return !ADMIN_HREFS.some((x) => href.includes(x)) &&
               !ADMIN_TEXTOS.some((x) => texto.includes(x));
      });
    }

    nav.innerHTML = htmlMenu(ultimoMenu);

    atualizarUsuario(ultimoUsuario);
    limparAdministrativo(ultimoUsuario);
  }

  document.addEventListener("DOMContentLoaded", () => {
    aplicarMenu(true);

    setTimeout(() => aplicarMenu(false), 300);
    setTimeout(() => aplicarMenu(false), 900);
    setTimeout(() => aplicarMenu(false), 1800);

    setInterval(() => {
      atualizarUsuario(ultimoUsuario);
      limparAdministrativo(ultimoUsuario);
    }, 1500);
  });
})();

/* CEJAS_FIX_FINANCEIRO_CLICAVEL */
(function () {
  if (window.__CEJAS_FINANCEIRO_CLICAVEL__) return;
  window.__CEJAS_FINANCEIRO_CLICAVEL__ = true;

  function criarLinkFinanceiro() {
    const a = document.createElement("a");
    a.href = "/financeiro.html";
    a.textContent = "💰 Financeiro";
    a.style.pointerEvents = "auto";
    a.style.cursor = "pointer";
    a.addEventListener("click", function (event) {
      event.preventDefault();
      window.location.href = "/financeiro.html";
    });
    return a;
  }

  function corrigirFinanceiro() {
    const aside = document.querySelector("aside");
    if (!aside) return;

    let nav = aside.querySelector("nav");

    if (!nav) {
      nav = document.createElement("nav");
      aside.appendChild(nav);
    }

    const itens = Array.from(nav.children);
    const itemFinanceiro = itens.find((el) => {
      return String(el.textContent || "").toLowerCase().includes("financeiro");
    });

    if (itemFinanceiro) {
      if (itemFinanceiro.tagName.toLowerCase() === "a") {
        itemFinanceiro.setAttribute("href", "/financeiro.html");
        itemFinanceiro.style.pointerEvents = "auto";
        itemFinanceiro.style.cursor = "pointer";
        itemFinanceiro.onclick = function (event) {
          event.preventDefault();
          window.location.href = "/financeiro.html";
        };
      } else {
        itemFinanceiro.replaceWith(criarLinkFinanceiro());
      }

      return;
    }

    const link = criarLinkFinanceiro();

    const itemOrcamentos = itens.find((el) => {
      return String(el.textContent || "").toLowerCase().includes("orçamento") ||
             String(el.textContent || "").toLowerCase().includes("orcamento");
    });

    if (itemOrcamentos && itemOrcamentos.parentNode) {
      itemOrcamentos.insertAdjacentElement("afterend", link);
    } else {
      nav.appendChild(link);
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    corrigirFinanceiro();
    setTimeout(corrigirFinanceiro, 300);
    setTimeout(corrigirFinanceiro, 900);
    setTimeout(corrigirFinanceiro, 1800);
  });

  setInterval(corrigirFinanceiro, 1500);
})();
