(function () {
  if (window.__LOGIN_CEJAS_POLIMENTO__) return;
  window.__LOGIN_CEJAS_POLIMENTO__ = true;

  function aplicarVisual() {
    const style = document.createElement("style");
    style.id = "loginCejasPolimentoCss";

    style.innerHTML = `
      body {
        background:
          radial-gradient(circle at 22% 18%, rgba(255,255,255,.22), transparent 28%),
          radial-gradient(circle at 82% 72%, rgba(0,0,0,.34), transparent 36%),
          linear-gradient(135deg, #7a7b7e, #45464a) !important;
      }

      .login {
        box-shadow: 0 45px 140px rgba(0,0,0,.38) !important;
      }

      .brand {
        justify-content: center !important;
        align-items: center !important;
        text-align: center !important;
        gap: 34px !important;
        padding: 54px !important;
      }

      .brand::before {
        width: 520px !important;
        height: 520px !important;
        right: -180px !important;
        top: -170px !important;
        background: rgba(255,255,255,.10) !important;
      }

      .logo {
        width: min(78%, 430px) !important;
        height: auto !important;
        aspect-ratio: 1 / 1 !important;
        border-radius: 0 !important;
        border: 0 !important;
        background: transparent !important;
        box-shadow: none !important;
        overflow: visible !important;
      }

      .logo img {
        width: 100% !important;
        height: 100% !important;
        object-fit: contain !important;
        border-radius: 0 !important;
      }

      .logo-fallback {
        font-size: 82px !important;
        letter-spacing: -0.09em !important;
      }

      .brand h1,
      .brand p {
        display: none !important;
      }

      .brand .kicker {
        display: block !important;
        margin: 0 !important;
        color: rgba(255,255,255,.82) !important;
        font-size: 13px !important;
        letter-spacing: .55em !important;
      }

      .brand > div:last-child {
        position: absolute !important;
        left: 40px !important;
        right: 40px !important;
        bottom: 58px !important;
        z-index: 3 !important;
      }

      .panel {
        background: rgba(19,19,23,.78) !important;
      }

      .msg:empty {
        display: none !important;
      }

      @media (max-width: 880px) {
        .logo {
          width: min(74%, 270px) !important;
        }

        .brand {
          min-height: 340px !important;
        }

        .brand > div:last-child {
          bottom: 30px !important;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function limparSessaoExpiradaParada() {
    const msg = document.getElementById("mensagem");
    if (!msg) return;

    const texto = String(msg.textContent || "").toLowerCase();

    if (texto.includes("sessão expirada") || texto.includes("sessao expirada")) {
      msg.textContent = "";
      msg.className = "msg";
    }
  }

  function corrigirSubmitLogin() {
    const form = document.getElementById("formLogin");
    if (!form) return;

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      event.stopImmediatePropagation();

      const mensagem = document.getElementById("mensagem");
      const btnEntrar = document.getElementById("btnEntrar");
      const email = document.getElementById("email")?.value.trim().toLowerCase();
      const senha = document.getElementById("senha")?.value || "";
      const lembrar = document.getElementById("lembrar")?.checked || false;

      function msg(texto, tipo = "err") {
        if (!mensagem) return;
        mensagem.textContent = texto;
        mensagem.className = "msg " + tipo;
      }

      if (!email.endsWith("@cejas.com.br")) {
        msg("Use apenas e-mail institucional @cejas.com.br.");
        return;
      }

      if (btnEntrar) {
        btnEntrar.disabled = true;
        btnEntrar.textContent = "Entrando...";
      }

      try {
        const r = await fetch("/api/auth/login-cejas", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email, senha, lembrar })
        });

        const j = await r.json();

        if (!j.ok) {
          throw new Error(j.message || "Erro ao entrar.");
        }

        if (j.trocarSenha) {
          const modal = document.getElementById("modalPrimeiro");
          if (modal) modal.classList.add("active");
          return;
        }

        window.location.href = "/dashboard.html";
      } catch (error) {
        msg(error.message);
      } finally {
        if (btnEntrar) {
          btnEntrar.disabled = false;
          btnEntrar.textContent = "Entrar no sistema";
        }
      }
    }, true);
  }

  document.addEventListener("DOMContentLoaded", () => {
    aplicarVisual();
    limparSessaoExpiradaParada();
    corrigirSubmitLogin();
  });
})();
