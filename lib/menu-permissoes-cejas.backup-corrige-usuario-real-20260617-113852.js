const fs = require("fs");
const path = require("path");
const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

function normalizarEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function usuarioDaSessao(req) {
  const sessao = req.session || {};
  const usuario = sessao.usuario || sessao.user || sessao.admin || {};

  const email = normalizarEmail(
    usuario.email ||
    sessao.email ||
    sessao.userEmail ||
    sessao.adminEmail ||
    null
  );

  const adminEmail = normalizarEmail(process.env.ADMIN_EMAIL);

  const nome =
    usuario.nome ||
    usuario.name ||
    sessao.nome ||
    sessao.userName ||
    (email === adminEmail ? "Eduardo" : email || "Usuário");

  const cargo =
    usuario.cargo ||
    usuario.funcao ||
    usuario.tipo_usuario ||
    usuario.tipo ||
    usuario.role ||
    sessao.cargo ||
    (email === adminEmail ? "Superadmin" : "Comercial");

  const permissoes =
    usuario.permissoes ||
    usuario.permissions ||
    sessao.permissoes ||
    [];

  return {
    email,
    nome,
    cargo,
    permissoes: Array.isArray(permissoes) ? permissoes : []
  };
}

function isSuperadmin(usuario) {
  const adminEmail = normalizarEmail(process.env.ADMIN_EMAIL);

  if (adminEmail && usuario.email === adminEmail) return true;
  if (String(usuario.cargo || "").toLowerCase().includes("super")) return true;
  if (Array.isArray(usuario.permissoes) && usuario.permissoes.includes("*")) return true;

  return false;
}

function normalizarUsuario(u) {
  if (!u) return null;

  const email = normalizarEmail(
    u.email ||
    u.usuario_email ||
    u.login ||
    u.user_email
  );

  if (!email) return null;

  return {
    email,
    nome: u.nome || u.name || u.nome_completo || email.split("@")[0],
    cargo: u.cargo || u.funcao || u.tipo_usuario || u.tipo || u.role || "Comercial",
    permissoes: Array.isArray(u.permissoes)
      ? u.permissoes
      : Array.isArray(u.permissions)
        ? u.permissions
        : []
  };
}

function buscarUsuarioLocal(email) {
  try {
    const arquivo = path.join(__dirname, "..", "data", "usuarios.json");

    if (!fs.existsSync(arquivo)) return null;

    const bruto = JSON.parse(fs.readFileSync(arquivo, "utf8"));

    let lista = [];

    if (Array.isArray(bruto)) lista = bruto;
    else if (Array.isArray(bruto.usuarios)) lista = bruto.usuarios;
    else if (Array.isArray(bruto.users)) lista = bruto.users;
    else if (typeof bruto === "object" && bruto !== null) lista = Object.values(bruto);

    return lista
      .map(normalizarUsuario)
      .filter(Boolean)
      .find((u) => u.email === email) || null;
  } catch {
    return null;
  }
}

async function buscarUsuarioSupabase(email) {
  if (!isSupabaseConfigured()) return null;

  try {
    const { data, error } = await supabaseAdmin
      .from("cejas_usuarios")
      .select("*")
      .eq("email", email)
      .maybeSingle();

    if (error || !data) return null;

    return normalizarUsuario(data);
  } catch {
    return null;
  }
}

async function usuarioAtualCompleto(req) {
  const sessao = usuarioDaSessao(req);
  const adminEmail = normalizarEmail(process.env.ADMIN_EMAIL);

  if (!sessao.email && adminEmail) {
    return {
      email: adminEmail,
      nome: "Eduardo",
      cargo: "Superadmin",
      permissoes: ["*"]
    };
  }

  const local = buscarUsuarioLocal(sessao.email);
  const remoto = await buscarUsuarioSupabase(sessao.email);

  const usuario = {
    ...sessao,
    ...(local || {}),
    ...(remoto || {})
  };

  if (usuario.email === adminEmail) {
    usuario.nome = usuario.nome || "Eduardo";
    usuario.cargo = "Superadmin";
    usuario.permissoes = ["*"];
  }

  return usuario;
}

function montarMenu(usuario) {
  const superadmin = isSuperadmin(usuario);

  const menuComercial = [
    { href: "/dashboard.html", texto: "▦ Painel Geral" },
    { href: "/agenda.html", texto: "◫ Agenda Dinâmica" },
    { href: "/painel-dia.html", texto: "▣ Painel do Dia" },
    { href: "/chat.html", texto: "💬 Chat Interno" },
    { href: "/orcamentos.html", texto: "◉ Orçamentos" },
    { href: "/tarefas.html", texto: "☑ Tarefas Pendentes" },
    { href: "/servidor.html", texto: "▣ Servidor" },
    { href: "/contratos.html", texto: "Contratos" }
  ];

  const menuAdmin = [
    ...menuComercial,
    { href: "/importar-relatorio.html", texto: "▤ Importar Relatório (PDF)" },
    { href: "/usuarios.html", texto: "◦ Acessos / Usuários" },
    { href: "/configuracoes.html", texto: "⚙ Configurações" }
  ];

  return superadmin ? menuAdmin : menuComercial;
}

function registrarMenuPermissoesCejas(app) {
  app.use(async (req, res, next) => {
    try {
      const usuario = await usuarioAtualCompleto(req);
      const superadmin = isSuperadmin(usuario);

      const paginasAdmin = [
        "/configuracoes.html",
        "/usuarios.html",
        "/importar-relatorio.html"
      ];

      if (paginasAdmin.includes(req.path) && !superadmin) {
        return res.redirect("/dashboard.html");
      }

      next();
    } catch {
      next();
    }
  });

  app.get("/api/menu-usuario-atual", async (req, res) => {
    try {
      const usuario = await usuarioAtualCompleto(req);
      const superadmin = isSuperadmin(usuario);

      res.json({
        ok: true,
        usuario: {
          email: usuario.email,
          nome: usuario.nome,
          cargo: superadmin ? "Superadmin" : usuario.cargo || "Comercial",
          superadmin
        },
        menu: montarMenu(usuario)
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  console.log("✅ Menu e permissões CEJAS carregados.");
}

module.exports = {
  registrarMenuPermissoesCejas
};
