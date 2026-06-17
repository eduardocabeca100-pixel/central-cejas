require("dotenv").config();

const express = require("express");
const bcrypt = require("bcryptjs");
const crypto = require("crypto");

function secret() {
  return process.env.SESSION_SECRET || "cejas-master-local-secret";
}

function parseCookies(req) {
  const header = req.headers.cookie || "";
  const cookies = {};

  header.split(";").forEach((part) => {
    const [key, ...rest] = part.trim().split("=");
    if (!key) return;
    cookies[decodeURIComponent(key)] = decodeURIComponent(rest.join("=") || "");
  });

  return cookies;
}

function assinar(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = crypto.createHmac("sha256", secret()).update(body).digest("base64url");
  return `${body}.${sig}`;
}

function verificar(token) {
  try {
    if (!token || !token.includes(".")) return null;

    const [body, sig] = token.split(".");
    const expected = crypto.createHmac("sha256", secret()).update(body).digest("base64url");

    if (sig !== expected) return null;

    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));

    if (!payload.exp || Date.now() > payload.exp) return null;

    return payload;
  } catch {
    return null;
  }
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

function registrarLoginMasterUltraCejas(app) {
  app.post("/entrar-master-cejas", express.urlencoded({ extended: true }), async (req, res) => {
    try {
      const email = String(req.body.email || "").trim().toLowerCase();
      const senha = String(req.body.senha || "");
      const lembrar = Boolean(req.body.lembrar);

      const adminEmail = String(process.env.ADMIN_EMAIL || "marcel@cejas.com.br").trim().toLowerCase();
      const adminHash = String(process.env.ADMIN_PASSWORD_HASH || "").trim();

      if (!email.endsWith("@cejas.com.br")) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("Use apenas e-mail institucional @cejas.com.br."));
      }

      if (email !== adminEmail) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("Acesso liberado somente para o Superadmin principal."));
      }

      if (!adminHash) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("Senha do Superadmin não configurada no servidor."));
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

      res.cookie("cejas_master_auth", token, {
        httpOnly: true,
        sameSite: "lax",
        maxAge: duracao,
        path: "/"
      });

      return res.redirect("/dashboard.html?login=ok");
    } catch (error) {
      return res.redirect("/login.html?erro=" + encodeURIComponent(error.message || "Erro ao entrar."));
    }
  });

  app.get("/sair", (req, res) => {
    res.clearCookie("cejas_master_auth", { path: "/" });

    if (req.session) {
      req.session.destroy(() => res.redirect("/login.html"));
    } else {
      res.redirect("/login.html");
    }
  });

  app.use((req, res, next) => {
    const cookies = parseCookies(req);
    const payload = verificar(cookies.cejas_master_auth);

    if (payload && payload.superadmin) {
      req.cejasMasterAuth = true;
    }

    next();
  });

  console.log("✅ Login Master Ultra CEJAS carregado.");
}

function registrarSessaoMasterUltraCejas(app) {
  app.use((req, res, next) => {
    if (req.cejasMasterAuth) {
      aplicarSessao(req);
    }

    next();
  });

  console.log("✅ Sessão Master Ultra CEJAS carregada.");
}

module.exports = {
  registrarLoginMasterUltraCejas,
  registrarSessaoMasterUltraCejas
};
