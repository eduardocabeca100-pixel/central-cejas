const fs = require("fs");
const path = require("path");
const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

function normalizarEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function valorTexto(v) {
  return String(v || "").trim();
}

function acharEmailProfundo(obj, depth = 0) {
  if (!obj || typeof obj !== "object" || depth > 5) return null;

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

function acharNomeProfundo(obj, depth = 0) {
  if (!obj || typeof obj !== "object" || depth > 5) return null;

  const possiveis = [
    obj.nome,
    obj.name,
    obj.nome_completo,
    obj.displayName,
    obj.userName
  ];

  for (const valor of possiveis) {
    const nome = valorTexto(valor);
    if (nome) return nome;
  }

  for (const valor of Object.values(obj)) {
    if (valor && typeof valor === "object") {
      const achado = acharNomeProfundo(valor, depth + 1);
      if (achado) return achado;
    }
  }

  return null;
}

function acharCargoProfundo(obj, depth = 0) {
  if (!obj || typeof obj !== "object" || depth > 5) return null;

  const possiveis = [
    obj.cargo,
    obj.funcao,
    obj.area,
    obj.setor,
    obj.tipo_usuario,
    obj.tipo,
    obj.role,
    obj.perfil
  ];

  for (const valor of possiveis) {
    const cargo = valorTexto(valor);
    if (cargo) return cargo;
  }

  for (const valor of Object.values(obj)) {
    if (valor && typeof valor === "object") {
      const achado = acharCargoProfundo(valor, depth + 1);
      if (achado) return achado;
    }
  }

  return null;
}

function acharPermissoesProfundo(obj, depth = 0) {
  if (!obj || typeof obj !== "object" || depth > 5) return [];

  if (Array.isArray(obj.permissoes)) return obj.permissoes;
  if (Array.isArray(obj.permissions)) return obj.permissions;

  for (const valor of Object.values(obj)) {
    if (valor && typeof valor === "object") {
      const achado = acharPermissoesProfundo(valor, depth + 1);
      if (achado.length) return achado;
    }
  }

  return [];
}

function temFlagAdminProfunda(obj, depth = 0) {
  if (!obj || typeof obj !== "object" || depth > 5) return false;

  const flags = [
    obj.superadmin,
    obj.superAdmin,
    obj.isSuperAdmin,
    obj.is_super_admin,
    obj.admin,
    obj.isAdmin,
    obj.is_admin
  ];

  if (flags.some((v) => v === true || v === "true" || v === 1 || v === "1")) {
    return true;
  }

  for (const valor of Object.values(obj)) {
    if (valor && typeof valor === "object") {
      if (temFlagAdminProfunda(valor, depth + 1)) return true;
    }
  }

  return false;
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
  const nome = acharNomeProfundo(sessao);
  const cargo = acharCargoProfundo(sessao);
  const permissoes = acharPermissoesProfundo(sessao);
  const flagAdmin = temFlagAdminProfunda(sessao);

  if (!email) {
    return {
      email: "",
      nome: nome || "Usuário",
      cargo: cargo || "Comercial",
      permissoes,
      flagAdmin
    };
  }

  return {
    email,
    nome: nome || email.split("@")[0],
    cargo: cargo || "Comercial",
    permissoes,
    flagAdmin
  };
}

function isSuperadmin(usuario) {
  if (!usuario) return false;

  const adminEmail = normalizarEmail(process.env.ADMIN_EMAIL);
  const email = normalizarEmail(usuario.email);
  const cargo = String(usuario.cargo || "").toLowerCase();

  if (adminEmail && email === adminEmail) return true;
  if (usuario.flagAdmin === true) return true;
  if (cargo.includes("super")) return true;
  if (Array.isArray(usuario.permissoes) && usuario.permissoes.includes("*")) return true;

  return false;
}

async function usuarioAtualCompleto(req) {
  const sessao = usuarioDaSessao(req);

  const local = sessao.email ? buscarUsuarioLocalPorEmail(sessao.email) : null;
  const remoto = sessao.email ? await buscarUsuarioSupabasePorEmail(sessao.email) : null;

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

  console.log("✅ Menu e permissões CEJAS carregados com admin corrigido.");
}

module.exports = {
  registrarMenuPermissoesCejas
};
