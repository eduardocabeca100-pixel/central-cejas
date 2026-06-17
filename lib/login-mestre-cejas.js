const express = require("express");
const bcrypt = require("bcryptjs");
const crypto = require("crypto");
const path = require("path");
const fs = require("fs");

function parseCookies(req) {
  const header = req.headers.cookie || "";
  return Object.fromEntries(
    header
      .split(";")
      .map(v => v.trim())
      .filter(Boolean)
      .map(v => {
        const i = v.indexOf("=");
        return [decodeURIComponent(v.slice(0, i)), decodeURIComponent(v.slice(i + 1))];
      })
  );
}

function segredo() {
  return process.env.SESSION_SECRET || "cejas-login-mestre-local";
}

function assinar(payload) {
  const corpo = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const assinatura = crypto
    .createHmac("sha256", segredo())
    .update(corpo)
    .digest("base64url");

  return `${corpo}.${assinatura}`;
}

function verificar(token) {
  try {
    if (!token || !token.includes(".")) return null;

    const [corpo, assinatura] = token.split(".");
    const esperado = crypto
      .createHmac("sha256", segredo())
      .update(corpo)
      .digest("base64url");

    if (assinatura !== esperado) return null;

    const payload = JSON.parse(Buffer.from(corpo, "base64url").toString("utf8"));

    if (!payload.exp || Date.now() > payload.exp) return null;

    return payload;
  } catch {
    return null;
  }
}

function usuarioAdmin() {
  const email = String(process.env.ADMIN_EMAIL || "marcel@cejas.com.br").trim().toLowerCase();

  return {
    email,
    nome: "Eduardo",
    cargo: "Superadmin",
    area: "Administração",
    permissoes: ["*"],
    permissions: ["*"],
    superadmin: true,
    admin: true
  };
}

function aplicarSessao(req, usuario = usuarioAdmin()) {
  if (!req.session) return;

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

function temLoginMestre(req) {
  const cookies = parseCookies(req);
  const payload = verificar(cookies.cejas_login_mestre);
  return Boolean(payload && payload.email);
}

function registrarLoginMestreCejas(app) {
  // Injeta o admin antes das proteções antigas sempre que o cookie mestre existir
  app.use((req, res, next) => {
    if (temLoginMestre(req)) {
      aplicarSessao(req, usuarioAdmin());
    }

    next();
  });

  app.post("/entrar", express.urlencoded({ extended: true }), async (req, res) => {
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
        return res.redirect("/login.html?erro=" + encodeURIComponent("Acesso liberado apenas para o Superadmin neste login mestre."));
      }

      if (!adminHash) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("Senha do Superadmin não configurada."));
      }

      const ok = await bcrypt.compare(senha, adminHash);

      if (!ok) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("E-mail ou senha inválidos."));
      }

      const usuario = usuarioAdmin();
      aplicarSessao(req, usuario);

      const duracao = lembrar
        ? 1000 * 60 * 60 * 24 * 30
        : 1000 * 60 * 60 * 8;

      const token = assinar({
        email: usuario.email,
        nome: usuario.nome,
        superadmin: true,
        exp: Date.now() + duracao
      });

      res.cookie("cejas_login_mestre", token, {
        httpOnly: true,
        sameSite: "lax",
        maxAge: duracao,
        path: "/"
      });

      req.session.save((erro) => {
        if (erro) {
          return res.redirect("/login.html?erro=" + encodeURIComponent("Erro ao salvar sessão."));
        }

        return res.redirect("/dashboard.html?login=ok");
      });
    } catch (error) {
      return res.redirect("/login.html?erro=" + encodeURIComponent(error.message || "Erro ao entrar."));
    }
  });

  app.get("/sair", (req, res) => {
    res.clearCookie("cejas_login_mestre", { path: "/" });

    if (req.session) {
      req.session.destroy(() => res.redirect("/login.html"));
    } else {
      res.redirect("/login.html");
    }
  });

  // Serve páginas principais com cookie mestre antes de qualquer bloqueio antigo
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
    if (!temLoginMestre(req)) return next();

    aplicarSessao(req, usuarioAdmin());

    const arquivo = path.join(__dirname, "..", req.path.replace("/", ""));

    if (!fs.existsSync(arquivo)) return next();

    return res.sendFile(arquivo);
  });

  console.log("✅ Login Mestre CEJAS carregado.");
}

module.exports = { registrarLoginMestreCejas };
