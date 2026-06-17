const express = require("express");
const bcrypt = require("bcryptjs");

function registrarLoginNovoCejas(app) {
  app.post("/entrar", express.urlencoded({ extended: true }), async (req, res) => {
    try {
      const email = String(req.body.email || "").trim().toLowerCase();
      const senha = String(req.body.senha || "");
      const lembrar = Boolean(req.body.lembrar);

      const adminEmail = String(process.env.ADMIN_EMAIL || "").trim().toLowerCase();
      const adminHash = String(process.env.ADMIN_PASSWORD_HASH || "").trim();

      if (!email.endsWith("@cejas.com.br")) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("Use apenas e-mail institucional @cejas.com.br."));
      }

      if (email !== adminEmail) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("Este acesso está liberado apenas para o Superadmin principal neste login novo."));
      }

      if (!adminHash) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("Senha do administrador não configurada no servidor."));
      }

      const senhaOk = await bcrypt.compare(senha, adminHash);

      if (!senhaOk) {
        return res.redirect("/login.html?erro=" + encodeURIComponent("E-mail ou senha inválidos."));
      }

      const usuario = {
        email: adminEmail,
        nome: "Eduardo",
        cargo: "Superadmin",
        area: "Administração",
        permissoes: ["*"],
        permissions: ["*"],
        superadmin: true,
        admin: true
      };

      // Sessão nova
      req.session.usuario = usuario;

      // Compatibilidade com tudo que já existe no sistema
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

      if (req.session.cookie) {
        req.session.cookie.maxAge = lembrar
          ? 1000 * 60 * 60 * 24 * 30
          : 1000 * 60 * 60 * 8;
      }

      req.session.save((erro) => {
        if (erro) {
          return res.redirect("/login.html?erro=" + encodeURIComponent("Erro ao salvar sessão. Tente novamente."));
        }

        return res.redirect("/dashboard.html?login=ok");
      });
    } catch (error) {
      return res.redirect("/login.html?erro=" + encodeURIComponent(error.message || "Erro ao entrar."));
    }
  });

  app.get("/sair", (req, res) => {
    req.session.destroy(() => {
      res.redirect("/login.html");
    });
  });

  console.log("✅ Login novo CEJAS carregado.");
}

module.exports = { registrarLoginNovoCejas };
