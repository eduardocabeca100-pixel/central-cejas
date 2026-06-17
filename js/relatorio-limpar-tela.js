(function () {
  if (window.__CEJAS_RELATORIO_LIMPAR_TELA__) return;
  window.__CEJAS_RELATORIO_LIMPAR_TELA__ = true;

  function zerarTextoVisivel() {
    document.querySelectorAll("body *").forEach((el) => {
      if (el.children.length > 0) return;

      const txt = String(el.textContent || "").trim();

      if (/^R\$\s*[\d.]+,\d{2}$/.test(txt)) {
        el.textContent = "R$ 0,00";
      }

      if (["319", "221", "24", "74"].includes(txt)) {
        el.textContent = "0";
      }
    });
  }

  function limparCaches() {
    Object.keys(localStorage).forEach((key) => {
      const k = key.toLowerCase();

      if (
        k.includes("relatorio") ||
        k.includes("supera") ||
        k.includes("ultimo-pdf") ||
        k.includes("dashboard")
      ) {
        localStorage.removeItem(key);
      }
    });

    Object.keys(sessionStorage).forEach((key) => {
      const k = key.toLowerCase();

      if (
        k.includes("relatorio") ||
        k.includes("supera") ||
        k.includes("ultimo-pdf") ||
        k.includes("dashboard")
      ) {
        sessionStorage.removeItem(key);
      }
    });
  }

  function mostrarVazio() {
    zerarTextoVisivel();

    const avisoId = "cejasRelatorioVazioAviso";

    if (!document.getElementById(avisoId)) {
      const aviso = document.createElement("div");
      aviso.id = avisoId;
      aviso.style.margin = "18px 0";
      aviso.style.padding = "18px";
      aviso.style.borderRadius = "18px";
      aviso.style.border = "1px solid rgba(255,255,255,.12)";
      aviso.style.background = "rgba(239,68,68,.12)";
      aviso.style.color = "white";
      aviso.style.fontWeight = "900";
      aviso.textContent = "Relatório apagado. Nenhum dado carregado no momento.";

      const main = document.querySelector("main") || document.body;
      const upload = Array.from(document.querySelectorAll("h1,h2,div")).find((el) =>
        String(el.textContent || "").toLowerCase().includes("importar relatório")
      );

      if (upload) {
        upload.insertAdjacentElement("afterend", aviso);
      } else {
        main.prepend(aviso);
      }
    }

    document.querySelectorAll("table tbody").forEach((tbody) => {
      tbody.innerHTML = `<tr><td colspan="20" style="text-align:center;padding:22px;color:rgba(255,255,255,.65);">Nenhum relatório carregado.</td></tr>`;
    });
  }

  async function apagarRelatorio(event) {
    event.preventDefault();
    event.stopPropagation();

    if (!confirm("Apagar o relatório atual? Os dados do relatório serão removidos da tela, do servidor local e do Supabase.")) {
      return;
    }

    const btn = event.currentTarget;
    const original = btn.textContent;

    btn.disabled = true;
    btn.textContent = "Apagando...";

    try {
      const resposta = await fetch("/api/relatorio-atual", {
        method: "DELETE"
      });

      const dados = await resposta.json();

      if (!dados.ok) {
        throw new Error(dados.message || "Erro ao apagar relatório.");
      }

      limparCaches();
      mostrarVazio();

      alert("Relatório atual apagado com sucesso.");
    } catch (error) {
      alert("Erro: " + error.message);
    } finally {
      btn.disabled = false;
      btn.textContent = original;
    }
  }

  function conectarBotao() {
    const botoes = Array.from(document.querySelectorAll("button, a"));

    botoes.forEach((btn) => {
      const texto = String(btn.textContent || "").toLowerCase();

      if (texto.includes("apagar relatório atual") || texto.includes("apagar relatorio atual")) {
        if (btn.dataset.cejasDeleteRelatorio === "true") return;

        btn.dataset.cejasDeleteRelatorio = "true";
        btn.addEventListener("click", apagarRelatorio, true);
      }
    });
  }

  async function checarSeEstaVazio() {
    try {
      const resposta = await fetch("/api/relatorio-atual?ts=" + Date.now());
      const dados = await resposta.json();

      if (dados.vazio === true || dados.ok === false && dados.eventos && dados.eventos.length === 0) {
        limparCaches();
        mostrarVazio();
      }
    } catch {}
  }

  document.addEventListener("DOMContentLoaded", () => {
    conectarBotao();
    setTimeout(conectarBotao, 500);
    setTimeout(conectarBotao, 1500);

    if (location.pathname.includes("importar-relatorio")) {
      setTimeout(checarSeEstaVazio, 500);
    }
  });
})();
