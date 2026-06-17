const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

const DATA_DIR = path.join(__dirname, "..", "data");
const RESET_FILE = path.join(DATA_DIR, "redefinicoes-senha-local.json");

function normalizarEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function emailInstitucional(email) {
  return normalizarEmail(email).endsWith("@cejas.com.br");
}

function garantirData() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

function lerJson(file, fallback) {
  try {
    garantirData();
    if (!fs.existsSync(file)) fs.writeFileSync(file, JSON.stringify(fallback, null, 2));
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return fallback;
  }
}

function salvarJson(file, data) {
  garantirData();
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

function usuariosLocais() {
  return lerJson(path.join(DATA_DIR, "usuarios.json"), []);
}

function salvarUsuariosLocais(lista) {
  salvarJson(path.join(DATA_DIR, "usuarios.json"), lista);
}

function normalizarUsuario(u) {
  if (!u) return null;

  const email = normalizarEmail(u.email || u.login || u.usuario_email || u.user_email);
  if (!email) return null;

  return {
    ...u,
    email,
    nome: u.nome || u.name || u.nome_completo || email.split("@")[0],
    cargo: u.cargo || u.funcao || u.area || u.setor || "Comercial",
    senha_hash: u.senha_hash || u.password_hash || u.passwordHash || null,
    ativo: u.ativo ?? true,
    primeiro_acesso: u.primeiro_acesso ?? u.primeiroAcesso ?? false,
    precisa_trocar_senha: u.precisa_trocar_senha ?? u.precisaTrocarSenha ?? false,
    permissoes: Array.isArray(u.permissoes) ? u.permissoes : Array.isArray(u.permissions) ? u.permissions : []
  };
}

async function buscarUsuario(email) {
  email = normalizarEmail(email);
  const adminEmail = normalizarEmail(process.env.ADMIN_EMAIL);

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
      origem: "admin-env"
    };
  }

  if (isSupabaseConfigured()) {
    try {
      const { data, error } = await supabaseAdmin
        .from("cejas_usuarios")
        .select("*")
        .eq("email", email)
        .maybeSingle();

      if (!error && data) return { ...normalizarUsuario(data), origem: "supabase" };
    } catch {}
  }

  const local = usuariosLocais()
    .map(normalizarUsuario)
    .filter(Boolean)
    .find((u) => u.email === email);

  return local ? { ...local, origem: "local" } : null;
}

async function atualizarSenha(email, senhaHash) {
  email = normalizarEmail(email);

  if (email === normalizarEmail(process.env.ADMIN_EMAIL)) {
    return { ok: false, message: "Senha do Superadmin deve ser alterada no .env." };
  }

  let ok = false;

  if (isSupabaseConfigured()) {
    try {
      const { error } = await supabaseAdmin
        .from("cejas_usuarios")
        .update({
          senha_hash: senhaHash,
          primeiro_acesso: false,
          precisa_trocar_senha: false
        })
        .eq("email", email);

      if (!error) ok = true;
    } catch {}
  }

  const lista = usuariosLocais();
  let mudou = false;

  const novaLista = lista.map((u) => {
    const nu = normalizarUsuario(u);
    if (!nu || nu.email !== email) return u;

    mudou = true;
    return {
      ...u,
      senha_hash: senhaHash,
      primeiro_acesso: false,
      precisa_trocar_senha: false
    };
  });

  if (mudou) {
    salvarUsuariosLocais(novaLista);
    ok = true;
  }

  return {
    ok,
    message: ok ? "Senha atualizada." : "Usuário não encontrado."
  };
}

function criarSessao(req, usuario, lembrar) {
  const superadmin =
    usuario.email === normalizarEmail(process.env.ADMIN_EMAIL) ||
    usuario.permissoes?.includes("*") ||
    String(usuario.cargo || "").toLowerCase().includes("super");

  const sessaoUsuario = {
    email: usuario.email,
    nome: usuario.nome,
    cargo: superadmin ? "Superadmin" : usuario.cargo || "Comercial",
    permissoes: superadmin ? ["*"] : usuario.permissoes || [],
    superadmin
  };

  req.session.usuario = sessaoUsuario;
  req.session.email = sessaoUsuario.email;
  req.session.nome = sessaoUsuario.nome;
  req.session.cargo = sessaoUsuario.cargo;
  req.session.permissoes = sessaoUsuario.permissoes;

  if (req.session.cookie) {
    req.session.cookie.maxAge = lembrar
      ? 1000 * 60 * 60 * 24 * 30
      : 1000 * 60 * 60 * 8;
  }

  return sessaoUsuario;
}

function registrarLoginCejas(app) {
  app.post("/api/auth/login-cejas", async (req, res) => {
    try {
      const email = normalizarEmail(req.body.email);
      const senha = String(req.body.senha || "");
      const lembrar = Boolean(req.body.lembrar);

      if (!emailInstitucional(email)) {
        return res.status(403).json({ ok: false, message: "Use apenas e-mail institucional @cejas.com.br." });
      }

      const usuario = await buscarUsuario(email);

      if (!usuario || usuario.ativo === false) {
        return res.status(401).json({ ok: false, message: "Usuário não encontrado ou inativo." });
      }

      if (!usuario.senha_hash) {
        return res.status(401).json({ ok: false, message: "Usuário sem senha cadastrada." });
      }

      const senhaOk = await bcrypt.compare(senha, usuario.senha_hash);

      if (!senhaOk) {
        return res.status(401).json({ ok: false, message: "E-mail ou senha inválidos." });
      }

      const sessaoUsuario = criarSessao(req, usuario, lembrar);

      if (isSupabaseConfigured() && usuario.origem === "supabase") {
        await supabaseAdmin
          .from("cejas_usuarios")
          .update({ ultimo_login: new Date().toISOString() })
          .eq("email", email);
      }

      const trocarSenha = Boolean(usuario.primeiro_acesso || usuario.precisa_trocar_senha);
      req.session.precisaTrocarSenha = trocarSenha;

      res.json({ ok: true, trocarSenha, usuario: sessaoUsuario });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.post("/api/auth/primeiro-acesso", async (req, res) => {
    try {
      const email = normalizarEmail(req.session?.usuario?.email || req.session?.email);
      const novaSenha = String(req.body.novaSenha || "");

      if (!email) return res.status(401).json({ ok: false, message: "Sessão expirada." });
      if (novaSenha.length < 8) return res.status(400).json({ ok: false, message: "A senha precisa ter pelo menos 8 caracteres." });

      const hash = await bcrypt.hash(novaSenha, 10);
      const resultado = await atualizarSenha(email, hash);

      if (!resultado.ok) return res.status(400).json(resultado);

      req.session.precisaTrocarSenha = false;
      res.json({ ok: true, message: "Senha alterada com sucesso." });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.post("/api/auth/solicitar-redefinicao", async (req, res) => {
    try {
      const email = normalizarEmail(req.body.email);

      if (!emailInstitucional(email)) {
        return res.json({ ok: true, message: "Se o e-mail estiver cadastrado, enviaremos as instruções." });
      }

      const usuario = await buscarUsuario(email);

      if (!usuario) {
        return res.json({ ok: true, message: "Se o e-mail estiver cadastrado, enviaremos as instruções." });
      }

      const codigo = String(crypto.randomInt(100000, 999999));
      const codigoHash = await bcrypt.hash(codigo, 10);
      const expiraEm = new Date(Date.now() + 1000 * 60 * 15).toISOString();

      if (isSupabaseConfigured()) {
        try {
          await supabaseAdmin
            .from("cejas_redefinicoes_senha")
            .insert({ email, codigo_hash: codigoHash, expira_em: expiraEm });
        } catch {}
      }

      const local = lerJson(RESET_FILE, []);
      local.push({ email, codigo_hash: codigoHash, usado: false, expira_em: expiraEm, criado_em: new Date().toISOString() });
      salvarJson(RESET_FILE, local);

      console.log("");
      console.log("🔐 CÓDIGO DE REDEFINIÇÃO CEJAS");
      console.log("E-mail:", email);
      console.log("Código:", codigo);
      console.log("Válido por 15 minutos.");
      console.log("");

      res.json({
        ok: true,
        message: "Código gerado. Em desenvolvimento, veja o código no terminal do servidor."
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.post("/api/auth/redefinir-senha", async (req, res) => {
    try {
      const email = normalizarEmail(req.body.email);
      const codigo = String(req.body.codigo || "").trim();
      const novaSenha = String(req.body.novaSenha || "");

      if (!emailInstitucional(email)) return res.status(403).json({ ok: false, message: "Use apenas @cejas.com.br." });
      if (novaSenha.length < 8) return res.status(400).json({ ok: false, message: "A senha precisa ter pelo menos 8 caracteres." });

      let registros = lerJson(RESET_FILE, []);
      let encontrado = null;

      for (const r of registros.filter((x) => x.email === email && !x.usado)) {
        if (new Date(r.expira_em).getTime() < Date.now()) continue;
        if (await bcrypt.compare(codigo, r.codigo_hash)) {
          encontrado = r;
          break;
        }
      }

      if (!encontrado && isSupabaseConfigured()) {
        try {
          const { data } = await supabaseAdmin
            .from("cejas_redefinicoes_senha")
            .select("*")
            .eq("email", email)
            .eq("usado", false)
            .gte("expira_em", new Date().toISOString())
            .order("criado_em", { ascending: false })
            .limit(5);

          for (const r of data || []) {
            if (await bcrypt.compare(codigo, r.codigo_hash)) {
              encontrado = r;
              break;
            }
          }
        } catch {}
      }

      if (!encontrado) return res.status(400).json({ ok: false, message: "Código inválido ou expirado." });

      const hash = await bcrypt.hash(novaSenha, 10);
      const resultado = await atualizarSenha(email, hash);

      if (!resultado.ok) return res.status(400).json(resultado);

      registros = registros.map((r) => r.email === email ? { ...r, usado: true } : r);
      salvarJson(RESET_FILE, registros);

      if (isSupabaseConfigured()) {
        try {
          await supabaseAdmin
            .from("cejas_redefinicoes_senha")
            .update({ usado: true })
            .eq("email", email);
        } catch {}
      }

      res.json({ ok: true, message: "Senha redefinida com sucesso." });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  console.log("✅ Login CEJAS carregado.");
}

module.exports = { registrarLoginCejas };
