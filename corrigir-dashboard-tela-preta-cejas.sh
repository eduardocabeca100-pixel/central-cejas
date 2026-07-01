#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "dashboard.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/dashboard-tela-preta-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js dashboard.html "$BACKUP_DIR/"

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("server.js")
s = p.read_text()

# Remove rota pública antiga, se existir
s = re.sub(
    r'\n?// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_START[\s\S]*?// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_END\n?',
    '\n',
    s
)

require_line = 'const { montarDashboard: montarDashboardRelatorioOficialCejasPublico } = require("./lib/dashboard-relatorio-oficial-cejas");'

if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace(
            'const path = require("path");',
            'const path = require("path");\n' + require_line,
            1
        )
    elif 'const express = require("express");' in s:
        s = s.replace(
            'const express = require("express");',
            'const express = require("express");\n' + require_line,
            1
        )
    else:
        s = require_line + "\n" + s

bloco = '''
// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_START
// Rota pública interna para o dashboard carregar o resumo oficial.
// Precisa ficar antes das travas de sessão.
app.get("/api/dashboard/relatorio-oficial", (req, res) => {
  try {
    res.set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
    res.set("Pragma", "no-cache");
    res.set("Expires", "0");
    return res.json(montarDashboardRelatorioOficialCejasPublico());
  } catch (error) {
    return res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_END

'''

marker = "const app = express();"

if marker not in s:
    raise SystemExit("❌ Não encontrei const app = express(); no server.js")

s = s.replace(marker, marker + "\n" + bloco, 1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("dashboard.html")
s = p.read_text()

# Remove script perigoso anterior
s = re.sub(
    r'\s*<script>\s*// CEJAS_DASHBOARD_OFICIAL_START[\s\S]*?// CEJAS_DASHBOARD_OFICIAL_END\s*</script>',
    '',
    s
)

# Remove painel seguro antigo, se existir
s = re.sub(
    r'\s*<script>\s*// CEJAS_DASHBOARD_OFICIAL_SEGURO_START[\s\S]*?// CEJAS_DASHBOARD_OFICIAL_SEGURO_END\s*</script>',
    '',
    s
)

js = r'''
<script>
// CEJAS_DASHBOARD_OFICIAL_SEGURO_START
(function () {
  if (window.__CEJAS_DASHBOARD_OFICIAL_SEGURO__) return;
  window.__CEJAS_DASHBOARD_OFICIAL_SEGURO__ = true;

  function brl(valor) {
    return Number(valor || 0).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });
  }

  async function buscarJson(url) {
    const res = await fetch(url + (url.includes("?") ? "&" : "?") + "_ts=" + Date.now(), {
      cache: "no-store"
    });

    return await res.json();
  }

  async function carregarDados() {
    let dados = await buscarJson("/api/dashboard/relatorio-oficial");

    if (!dados || dados.ok === false) {
      const status = await buscarJson("/api/sistema/relatorio-oficial-status");

      if (status && status.ok) {
        dados = {
          ok: true,
          nomeArquivo: status.nomeArquivo,
          totalEventos: status.totalEventos,
          eventosConfirmados: status.eventosConfirmados,
          eventosEmEspera: status.eventosEmEspera,
          eventosNaLista: status.eventosNaLista,
          faturamentoPrevisto: 0,
          receitaConfirmada: 0,
          descontosAplicados: 0,
          fluxoCaixa: 0,
          origemEscolhida: status.origemEscolhida
        };
      }
    }

    return dados;
  }

  function criarOuAtualizarPainel(dados) {
    let painel = document.getElementById("cejas-dashboard-oficial-seguro");

    if (!painel) {
      painel = document.createElement("section");
      painel.id = "cejas-dashboard-oficial-seguro";

      const alvo =
        document.querySelector("main") ||
        document.querySelector(".main") ||
        document.querySelector(".content") ||
        document.body;

      alvo.insertBefore(painel, alvo.firstChild);
    }

    painel.style.cssText = `
      margin:16px;
      padding:18px;
      border-radius:18px;
      border:1px solid rgba(168,85,247,.35);
      background:linear-gradient(135deg,rgba(17,17,24,.98),rgba(22,10,38,.96));
      box-shadow:0 18px 60px rgba(0,0,0,.35);
      color:white;
      font-family:Inter,Arial,sans-serif;
      position:relative;
      z-index:20;
    `;

    painel.innerHTML = `
      <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:16px;flex-wrap:wrap;margin-bottom:14px;">
        <div>
          <div style="font-size:11px;letter-spacing:.22em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">
            Relatório oficial carregado do Supabase
          </div>
          <h2 style="margin:6px 0 0;font-size:24px;line-height:1.1;">Dashboard de Resultados</h2>
          <p style="margin:8px 0 0;color:rgba(255,255,255,.68);font-size:13px;">
            Fonte: ${dados.origemEscolhida || "relatório oficial"} • ${dados.nomeArquivo || "relatorio-supera.json"}
          </p>
        </div>
        <button id="cejas-dashboard-oficial-atualizar" type="button" style="
          border:0;
          border-radius:12px;
          padding:11px 14px;
          font-weight:900;
          color:white;
          cursor:pointer;
          background:linear-gradient(135deg,#a855f7,#d946ef);
        ">Atualizar painel</button>
      </div>

      <div style="display:grid;grid-template-columns:repeat(4,minmax(160px,1fr));gap:12px;">
        <div style="padding:14px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);">
          <div style="font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">Total de eventos</div>
          <div style="font-size:28px;font-weight:950;margin-top:8px;">${dados.totalEventos || 0}</div>
          <div style="font-size:12px;color:#22c55e;font-weight:800;">${dados.eventosNaLista || 0} eventos na lista</div>
        </div>

        <div style="padding:14px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);">
          <div style="font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">Confirmados</div>
          <div style="font-size:28px;font-weight:950;margin-top:8px;">${dados.eventosConfirmados || 0}</div>
          <div style="font-size:12px;color:#22c55e;font-weight:800;">eventos confirmados</div>
        </div>

        <div style="padding:14px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);">
          <div style="font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">Em espera</div>
          <div style="font-size:28px;font-weight:950;margin-top:8px;">${dados.eventosEmEspera || 0}</div>
          <div style="font-size:12px;color:#fbbf24;font-weight:800;">eventos em espera</div>
        </div>

        <div style="padding:14px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);">
          <div style="font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">Receita confirmada</div>
          <div style="font-size:28px;font-weight:950;margin-top:8px;">${brl(dados.receitaConfirmada || 0)}</div>
          <div style="font-size:12px;color:#22c55e;font-weight:800;">fluxo: ${brl(dados.fluxoCaixa || dados.receitaConfirmada || 0)}</div>
        </div>
      </div>
    `;

    const btn = document.getElementById("cejas-dashboard-oficial-atualizar");
    if (btn) {
      btn.onclick = async function () {
        btn.textContent = "Atualizando...";
        try {
          const novo = await carregarDados();
          if (novo && novo.ok !== false) criarOuAtualizarPainel(novo);
        } finally {
          btn.textContent = "Atualizar painel";
        }
      };
    }
  }

  async function iniciar() {
    try {
      const dados = await carregarDados();

      if (!dados || dados.ok === false) {
        console.warn("Dashboard oficial não carregou:", dados);
        return;
      }

      criarOuAtualizarPainel(dados);
      console.log("✅ Painel oficial seguro carregado:", dados);
    } catch (error) {
      console.warn("⚠️ Erro no painel oficial seguro:", error);
    }
  }

  document.addEventListener("DOMContentLoaded", iniciar);
  setTimeout(iniciar, 800);
  setTimeout(iniciar, 2200);

  window.cejasAtualizarDashboardOficialSeguro = iniciar;
})();
// CEJAS_DASHBOARD_OFICIAL_SEGURO_END
</script>
'''

if "</body>" in s:
    s = s.replace("</body>", js + "\n</body>", 1)
else:
    s += js

p.write_text(s)
PY

echo ""
echo "🔎 Verificando sintaxe..."
node --check server.js
node --check lib/dashboard-relatorio-oficial-cejas.js

echo ""
echo "✅ Corrigido: removido script que apagava o dashboard e liberada API oficial."
echo ""
echo "Agora rode:"
echo "npm start"
