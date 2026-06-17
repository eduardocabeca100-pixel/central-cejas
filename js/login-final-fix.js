(function () {
  if (window.__CEJAS_LOGIN_FINAL_FIX__) return;
  window.__CEJAS_LOGIN_FINAL_FIX__ = true;

  function mostrarMensagem(texto, tipo = "err") {
    const msg = document.getElementById("mensagem");
    if (!msg) return;

    msg.textContent = texto || "";
    msg.className = texto ? "msg " + tipo : "msg";
  }

  function limparMensagemInicial() {
    const msg = document.getElementById("mensagem");
    if (!msg) return;

    const texto = String(msg.textContent || "").toLowerCase();

    if (
      texto.includes("sessão expirada") ||
      texto.includes("sessao expirada")
    ) {
      mostrarMensagem("");
    }
  }

  function ligarLoginFinal() {
    const form = document.getElementById("formLogin");
    const btn = document.getElementById("btnEntrar");

    if (!form || form.dataset.loginFinalFix === "true") return;

    form.dataset.loginFinalFix = "true";

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      mostrarMensagem("");

      const email = document.getElementById("email")?.value.trim().toLowerCase() || "";
      const senha = document.getElementById("senha")?.value || "";
      const lembrar = document.getElementById("lembrar")?.checked || false;

      if (!email.endsWith("@cejas.com.br")) {
        mostrarMensagem("Use apenas e-mail institucional @cejas.com.br.");
        return;
      }

      if (!senha) {
        mostrarMensagem("Digite sua senha.");
        return;
      }

      if (btn) {
        btn.disabled = true;
        btn.textContent = "Entrando...";
      }

      try {
        const resposta = await fetch("/api/auth/login-cejas", {
          method: "POST",
          credentials: "same-origin",
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            email,
            senha,
            lembrar
          })
        });

        let dados = null;

        try {
          dados = await resposta.json();
        } catch {
          throw new Error("O servidor não retornou uma resposta válida.");
        }

        if (!resposta.ok || !dados.ok) {
          throw new Error(dados.message || "Não foi possível entrar.");
        }

        if (dados.trocarSenha) {
          const modal = document.getElementById("modalPrimeiro");
          if (modal) {
            modal.classList.add("active");
            return;
          }
        }

        mostrarMensagem("Login confirmado. Abrindo painel...", "ok");

        setTimeout(() => {
          window.location.replace("/dashboard.html?ts=" + Date.now());
        }, 300);
      } catch (error) {
        mostrarMensagem(error.message || "Erro ao fazer login.");
      } finally {
        if (btn) {
          btn.disabled = false;
          btn.textContent = "Entrar no sistema";
        }
      }
    }, true);
  }

  document.addEventListener("DOMContentLoaded", () => {
    limparMensagemInicial();
    ligarLoginFinal();

    setTimeout(limparMensagemInicial, 200);
    setTimeout(ligarLoginFinal, 500);
  });
})();
