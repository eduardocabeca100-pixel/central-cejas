const bcrypt = require("bcryptjs");
const fs = require("fs");
const path = require("path");
const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

function emailLimpo(email) {
  return String(email || "").trim().toLowerCase();
}

function institucional(email) {
  return emailLimpo(email).endsWith("@cejas.com.br");
}

function normalizarUsuario(u) {
  if (!u) return null;

  const email = emailLimpo(u.email || u.login || u.usuario_email || u.user_email);
  if (!email) return null;

  return {
    ...u,
    email,
    nome: u.nome || u.name || u.nome_completo || email.split("@")[0],
    cargo: u.cargo || u.funcao || u.area || u.setor || "Comercial",
    senha_hash: u.senha_hash || u.password_hash || u.passwordHash || null,
    ativo: u.ativo ?? true,
    primeiro_acesso: u.primeiro_acesso ?? false,
    precisa_trocar_senha: u.precisa_trocar_senha ?? false,
    permissoes: Array.isArray(u.permissoes)
      ? u.permissoes
      : Array.isArray(u.permissions)
        ? u.permissions
        : []
  };
}

function usuariosLocais() {
  try {
    const file = path.join(__dirname, "..", "data", "usuarios.json");
    if (!fs.existsSync(file)) return [];

    const bruto = JSON.parse(fs.readFileSync(file, "utf8"));

    if (Array.isArray(bruto)) return bruto;
    if (Array.isArray(bruto.usuarios)) return bruto.usuarios;
    if (Array.isArray(bruto.users)) return bruto.users;
    if (typeof bruto === "object" && bruto) return Object.values(bruto);

    return [];
  } catch {
    return [];
  }
}

async function buscarUsuario(email) {
  email = emailLimpo(email);
  const adminEmail = emailLimpo(process.env.ADMIN_EMAIL);

  if (email === adminEmail) {
    return {
      email,
      nome: "Eduardo",
      cargo: "Superadmin",
      senha_hash: process.env.ADMIN_PASSWORD_HASH,
      ativo: true,
      primeiro_acesso: false,
      precisa_trocar_senha: false,
      permissoes: ["*"],
      origem: "env"
    };
  }

  if (isSupabaseConfigured()) {
    try {
      const { data, error } = await supabaseAdmin
        .from("cejas_usuarios")
        .select("*")
        .eq("email", email)
        .maybeSingle();

      if (!error && data) {
        return { ...normalizarUsuario(data), origem: "supabase" };
      }
    } catch {}
  }

  const local = usuariosLocais()
    .map(normalizarUsuario)
    .filter(Boolean)
    .find((u) => u.email === email);

  return local ? { ...local, origem: "local" } : null;
}

function criarSessao(req, usuario, lembrar) {
  const superadmin =
    usuario.email === emailLimpo(process.env.ADMIN_EMAIL) ||
    usuario.permissoes.includes("*") ||
    String(usuario.cargo || "").toLowerCase().includes("super");

  const sessao = {
    email: usuario.email,
    nome: usuario.nome,
    cargo: superadmin ? "Superadmin" : usuario.cargo,
    permissoes: superadmin ? ["*"] : usuario.permissoes,
    superadmin
  };

  req.session.usuario = sessao;
  req.session.email = sessao.email;
  req.session.nome = sessao.nome;
  req.session.cargo = sessao.cargo;
  req.session.permissoes = sessao.permissoes;

  if (req.session.cookie) {
    req.session.cookie.maxAge = lembrar
      ? 1000 * 60 * 60 * 24 * 30
      : 1000 * 60 * 60 * 8;
  }

  return sessao;
}

function registrarLoginPublicoCejas(app) {
  app.post("/api/public/login-cejas", async (req, res) => {
    try {
      const email = emailLimpo(req.body.email);
      const senha = String(req.body.senha || "");
      const lembrar = Boolean(req.body.lembrar);

      if (!institucional(email)) {
        return res.status(403).json({
          ok: false,
          message: "Use apenas e-mail institucional @cejas.com.br."
        });
      }

      const usuario = await buscarUsuario(email);

      if (!usuario || usuario.ativo === false) {
        return res.status(401).json({
          ok: false,
          message: "Usuário não encontrado ou inativo."
        });
      }

      if (!usuario.senha_hash) {
        return res.status(401).json({
          ok: false,
          message: "Usuário sem senha cadastrada."
        });
      }

      const senhaOk = await bcrypt.compare(senha, usuario.senha_hash);

      if (!senhaOk) {
        return res.status(401).json({
          ok: false,
          message: "E-mail ou senha inválidos."
        });
      }

      const sessao = criarSessao(req, usuario, lembrar);

      if (isSupabaseConfigured() && usuario.origem === "supabase") {
        await supabaseAdmin
          .from("cejas_usuarios")
          .update({ ultimo_login: new Date().toISOString() })
          .eq("email", email);
      }

      return res.json({
        ok: true,
        trocarSenha: Boolean(usuario.primeiro_acesso || usuario.precisa_trocar_senha),
        usuario: sessao
      });
    } catch (error) {
      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  console.log("✅ Login público CEJAS carregado.");
}

module.exports = { registrarLoginPublicoCejas };
