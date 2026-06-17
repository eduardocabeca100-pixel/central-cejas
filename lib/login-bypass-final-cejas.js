require("dotenv").config();

const bcrypt = require("bcryptjs");
const crypto = require("crypto");
const path = require("path");
const fs = require("fs");

function getSecret() {
  return process.env.SESSION_SECRET || "cejas-secret-local";
}

function assinar(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = crypto.createHmac("sha256", getSecret()).update(body).digest("base64url");
  return `${body}.${sig}`;
}

function verificar(token) {
  try {
    if (!token || !token.includes(".")) return null;

    const [body, sig] = token.split(".");
    const esperado = crypto.createHmac("sha256", getSecret()).update(body).digest("base64url");

    if (sig !== esperado) return null;

    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));

    if (!payload.exp || Date.now() > payload.exp) return null;

    return payload;
  } catch {
    return null;
  }
}

function cookies(req) {
  const raw = req.headers.cookie || "";
  const out = {};

  raw.split(";").forEach((p) => {
    const i = p.indexOf("=");
    if (i === -1) return;

    const k = p.slice(0, i).trim();
    const v = p.slice(i + 1).trim();

    out[decodeURIComponent(k)] = decodeURIComponent(v);
  });

  return out;
}

function usuarioEduardo() {
  return {
    email: "marcel@cejas.com.br",
    nome: "Eduardo",
    cargo: "Superadmin",
    area: "Administração",
    permissoes: ["*"],
    permissions: ["*"],
    superadmin: true,
    admin: true
  };
}

function aplicarSessao(req) {
  if (!req.session) return;

  const usuario = usuarioEduardo();

  req.session.usuario = usuario;
  req.session.user = usuario;
  req.session.currentUser = usuario;
  req.session.authUser = usuario;
  req.session.usuarioAtual = usuario;
  req.session.usuarioLogado = usuario;

  req.session.logado = true;
  req.session.loggedIn = true;
  req.session.isLoggedIn = true;
  req.session.autenticado = true;
  req.session.authenticated = true;
  req.session.isAuthenticated = true;

  req.session.email = usuario.email;
  req.session.nome = usuario.nome;
  req.session.name = usuario.nome;
  req.session.cargo = usuario.cargo;
  req.session.role = usuario.cargo;
  req.session.area = usuario.area;

  req.session.permissoes = usuario.permissoes;
  req.session.permissions = usuario.permissoes;

  req.session.superadmin = true;
  req.session.isSuperAdmin = true;
  req.session.admin = true;
  req.session.isAdmin = true;
  req.session.tipo = "superadmin";
}

function registrarLoginBypassFinalCejas(app) {
  app.post("/entrar-master-cejas", (req, res) => {
    let body = "";

    req.on("data", (chunk) => {
      body += chunk.toString();
    });

    req.on("end", async () => {
      try {
        const params = new URLSearchParams(body);

        const email = String(params.get("email") || "").trim().toLowerCase();
        const senha = String(params.get("senha") || "");
        const lembrar = Boolean(params.get("lembrar"));

        const adminEmail = String(process.env.ADMIN_EMAIL || "marcel@cejas.com.br").trim().toLowerCase();
        const adminHash = String(process.env.ADMIN_PASSWORD_HASH || "").trim();

        if (!email.endsWith("@cejas.com.br")) {
          return res.redirect("/login.html?erro=" + encodeURIComponent("Use apenas e-mail institucional @cejas.com.br."));
        }

        if (email !== adminEmail) {
          return res.redirect("/login.html?erro=" + encodeURIComponent("Acesso liberado somente para o Superadmin principal."));
        }

        if (!adminHash) {
          return res.redirect("/login.html?erro=" + encodeURIComponent("Senha do Superadmin não configurada."));
        }

        const senhaOk = await bcrypt.compare(senha, adminHash);

        if (!senhaOk) {
          return res.redirect("/login.html?erro=" + encodeURIComponent("E-mail ou senha inválidos."));
        }

        const duracao = lembrar
          ? 1000 * 60 * 60 * 24 * 30
          : 1000 * 60 * 60 * 8;

        const token = assinar({
          email: adminEmail,
          nome: "Eduardo",
          superadmin: true,
          exp: Date.now() + duracao
        });

        res.setHeader("Set-Cookie", `cejas_master_auth=${encodeURIComponent(token)}; Path=/; Max-Age=${Math.floor(duracao / 1000)}; HttpOnly; SameSite=Lax`);

        return res.redirect("/dashboard.html?login=ok");
      } catch (error) {
        return res.redirect("/login.html?erro=" + encodeURIComponent(error.message || "Erro ao entrar."));
      }
    });
  });

  console.log("✅ Login bypass final CEJAS carregado.");
}

function registrarSessaoBypassFinalCejas(app) {
  app.use((req, res, next) => {
    const token = cookies(req).cejas_master_auth;
    const payload = verificar(token);

    if (payload && payload.superadmin) {
      aplicarSessao(req);
      req.cejasBypassAdmin = true;
    }

    next();
  });

  const paginas = [
    "/dashboard.html",
    "/agenda.html",
    "/painel-dia.html",
    "/chat.html",
    "/orcamentos.html",
    "/tarefas.html",
    "/servidor.html",
    "/usuarios.html",
    "/configuracoes.html",
    "/importar-relatorio.html",
    "/contratos.html"
  ];

  app.get(paginas, (req, res, next) => {
    const token = cookies(req).cejas_master_auth;
    const payload = verificar(token);

    if (!payload || !payload.superadmin) return next();

    aplicarSessao(req);

    const arquivo = path.join(__dirname, "..", req.path.replace("/", ""));

    if (!fs.existsSync(arquivo)) return next();

    return res.sendFile(arquivo);
  });

  console.log("✅ Sessão bypass final CEJAS carregada.");
}

module.exports = {
  registrarLoginBypassFinalCejas,
  registrarSessaoBypassFinalCejas
};
