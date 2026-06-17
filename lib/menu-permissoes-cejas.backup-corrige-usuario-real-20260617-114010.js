const fs = require("fs");
const path = require("path");
const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

function normalizarEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function acharEmailProfundo(obj, depth = 0) {
  if (!obj || typeof obj !== "object" || depth > 4) return null;

  const possiveis = [
    obj.email,
    obj.userEmail,
    obj.adminEmail,
    obj.usuario_email,
    obj.login,
    obj.emailUsuario
  ];

  for (const valor of possiveis) {
    const email = normalizarEmail(valor);
    if (email && email.includes("@")) return email;
  }

  for (const valor of Object.values(obj)) {
    if (valor && typeof valor === "object") {
      const achado = acharEmailProfundo(valor, depth + 1);
      if (achado) return achado;
    }
  }

  return null;
}

function normalizarUsuario(u) {
  if (!u) return null;

  const email = normalizarEmail(
    u.email ||
    u.usuario_email ||
    u.login ||
    u.user_email ||
    u.emailUsuario
  );

  if (!email) return null;

  const ativo = u.ativo ?? u.active ?? u.is_active ?? true;

  if (ativo === false || ativo === "false" || ativo === 0) return null;

  const permissoes = Array.isArray(u.permissoes)
    ? u.permissoes
    : Array.isArray(u.permissions)
      ? u.permissions
      : [];

  return {
    id: u.id || u.user_id || u.usuario_id || null,
    email,
    nome: u.nome || u.name || u.nome_completo || u.displayName || email.split("@")[0],
    cargo: u.cargo || u.funcao || u.area || u.setor || u.tipo_usuario || u.tipo || u.role || "Comercial",
    permissoes
  };
}

function buscarUsuarioLocalPorEmail(email) {
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

async function buscarUsuarioSupabasePorEmail(email) {
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

function usuarioDaSessao(req) {
  const sessao = req.session || {};
  const email = acharEmailProfundo(sessao);

  if (!email) {
    return null;
  }

  const candidatos = [
    sessao.usuario,
    sessao.user,
    sessao.admin,
    sessao.currentUser,
    sessao.authUser,
    sessao
  ].filter(Boolean);

  let base = null;

  for (const c of candidatos) {
    const u = normalizarUsuario(c);
    if (u && u.email === email) {
      base = u;
      break;
    }
  }

  if (!base) {
    base = {
      email,
      nome: sessao.nome || sessao.userName || email.split("@")[0],
      cargo: sessao.cargo || sessao.funcao || sessao.area || "Comercial",
      permissoes: Array.isArray(sessao.permissoes) ? sessao.permissoes : []
    };
  }

  return base;
}

function isSuperadmin(usuario) {
  if (!usuario) return false;

  const adminEmail = normalizarEmail(process.env.ADMIN_EMAIL);
  const email = normalizarEmail(usuario.email);
  const cargo = String(usuario.cargo || "").toLowerCase();

  if (adminEmail && email === adminEmail) return true;
  if (cargo.includes("super")) return true;
  if (Array.isArray(usuario.permissoes) && usuario.permissoes.includes("*")) return true;

  return false;
}

async function usuarioAtualCompleto(req) {
  const sessao = usuarioDaSessao(req);

  // IMPORTANTE:
  // Se não encontrar sessão, NÃO assume Eduardo.
  // Assim usuário comum nunca vira Superadmin por engano.
  if (!sessao?.email) {
    return {
      email: "",
      nome: "Usuário",
      cargo: "Comercial",
      permissoes: [],
      superadmin: false
    };
  }

  const local = buscarUsuarioLocalPorEmail(sessao.email);
  const remoto = await buscarUsuarioSupabasePorEmail(sessao.email);

  const usuario = {
    ...sessao,
    ...(local || {}),
    ...(remoto || {})
  };

  if (isSuperadmin(usuario)) {
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

  console.log("✅ Menu e permissões CEJAS carregados com usuário real.");
}

module.exports = {
  registrarMenuPermissoesCejas
};
