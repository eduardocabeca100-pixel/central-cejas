function normalizarEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function usuarioDaSessao(req) {
  const sessao = req.session || {};
  const user = sessao.user || sessao.usuario || sessao.currentUser || sessao.authUser || {};

  const email = normalizarEmail(
    user.email ||
    sessao.email ||
    ""
  );

  const permissoes = Array.isArray(user.permissoes)
    ? user.permissoes
    : Array.isArray(user.permissions)
      ? user.permissions
      : Array.isArray(sessao.permissoes)
        ? sessao.permissoes
        : [];

  const nome =
    user.nome ||
    user.name ||
    sessao.nome ||
    sessao.name ||
    email.split("@")[0] ||
    "Usuário";

  const cargo =
    user.cargo ||
    user.role ||
    sessao.cargo ||
    sessao.role ||
    "Comercial";

  return {
    email,
    nome,
    cargo,
    permissoes,
    superadmin: Boolean(
      email === normalizarEmail(process.env.ADMIN_EMAIL) ||
      permissoes.includes("*") ||
      user.superadmin === true
    )
  };
}

function montarMenu(usuario) {
  const menuOperacional = [
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

  if (!usuario.superadmin) {
    return menuOperacional;
  }

  return [
    ...menuOperacional,
    { href: "/importar-relatorio.html", texto: "▤ Importar Relatório (PDF)" },
    { href: "/usuarios.html", texto: "◦ Acessos / Usuários" },
    { href: "/configuracoes.html", texto: "⚙ Configurações" }
  ];
}

function registrarMenuPermissoesCejas(app) {
  app.use((req, res, next) => {
    const usuario = usuarioDaSessao(req);

    const paginasSomenteAdmin = [
      "/configuracoes.html",
      "/usuarios.html",
      "/importar-relatorio.html"
    ];

    if (paginasSomenteAdmin.includes(req.path) && !usuario.superadmin) {
      return res.redirect("/dashboard.html");
    }

    next();
  });

  app.get("/api/menu-usuario-atual", (req, res) => {
    const usuario = usuarioDaSessao(req);

    return res.json({
      ok: true,
      usuario: {
        email: usuario.email,
        nome: usuario.nome,
        cargo: usuario.superadmin ? "Superadmin" : usuario.cargo || "Comercial",
        superadmin: usuario.superadmin
      },
      menu: montarMenu(usuario)
    });
  });

  console.log("✅ Menu CEJAS carregado com áreas administrativas somente para Superadmin.");
}

module.exports = {
  registrarMenuPermissoesCejas
};
