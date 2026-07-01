#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "dashboard.html" ] || [ ! -f "server.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/dashboard-status-oficial-$STAMP"
mkdir -p "$BACKUP_DIR"

cp dashboard.html server.js "$BACKUP_DIR/"

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

# Remove a rota nova quebrada do server.js, porque não vamos mais depender dela.
p = Path("server.js")
s = p.read_text()

s = re.sub(
    r'\n?// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_START[\s\S]*?// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_END\n?',
    '\n',
    s
)

p.write_text(s)

# Limpa scripts antigos do dashboard e coloca um painel seguro usando a rota que já funciona.
p = Path("dashboard.html")
s = p.read_text()

for marker in [
    "CEJAS_DASHBOARD_OFICIAL_START",
    "CEJAS_DASHBOARD_OFICIAL_SEGURO_START",
    "CEJAS_DASHBOARD_STATUS_OFICIAL_START"
]:
    s = re.sub(
        rf'\s*<script>\s*// {marker}[\s\S]*?// {marker.replace("_START", "_END")}\s*</script>',
        '',
        s
    )

js = r'''
<script>
// CEJAS_DASHBOARD_STATUS_OFICIAL_START
(function () {
  if (window.__CEJAS_DASHBOARD_STATUS_OFICIAL__) return;
  window.__CEJAS_DASHBOARD_STATUS_OFICIAL__ = true;

  function brl(valor) {
    return Number(valor || 0).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });
  }

  async function carregarStatusOficial() {
    const res = await fetch("/api/sistema/relatorio-oficial-status?_ts=" + Date.now(), {
      cache: "no-store"
    });

    return await res.json();
  }

  function criarPainel(status) {
    let painel = document.getElementById("cejas-painel-oficial-status");

    if (!painel) {
      painel = document.createElement("section");
      painel.id = "cejas-painel-oficial-status";

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
      border:1px solid rgba(168,85,247,.38);
      background:linear-gradient(135deg,rgba(16,16,22,.98),rgba(34,13,54,.96));
      color:white;
      font-family:Inter,Arial,sans-serif;
      box-shadow:0 18px 70px rgba(0,0,0,.42);
      position:relative;
      z-index:999;
    `;

    painel.innerHTML = `
      <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:16px;flex-wrap:wrap;margin-bottom:14px;">
        <div>
          <div style="font-size:11px;letter-spacing:.22em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">
            Relatório oficial carregado do Supabase
          </div>
          <h2 style="margin:6px 0 0;font-size:24px;line-height:1.1;">Dashboard de Resultados</h2>
          <p style="margin:8px 0 0;color:rgba(255,255,255,.68);font-size:13px;">
            Fonte: ${status.origemEscolhida || "Supabase"} • ${status.nomeArquivo || "relatorio-supera.json"}
          </p>
        </div>

        <button id="cejas-atualizar-status-oficial" type="button" style="
          border:0;
          border-radius:12px;
          padding:11px 14px;
          font-weight:900;
          color:white;
          cursor:pointer;
          background:linear-gradient(135deg,#a855f7,#d946ef);
        ">Atualizar dados</button>
      </div>

      <div style="display:grid;grid-template-columns:repeat(4,minmax(160px,1fr));gap:12px;">
        <div style="padding:14px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);">
          <div style="font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">Total de eventos</div>
          <div style="font-size:30px;font-weight:950;margin-top:8px;">${status.totalEventos || 0}</div>
          <div style="font-size:12px;color:#22c55e;font-weight:800;">${status.eventosNaLista || 0} eventos na lista</div>
        </div>

        <div style="padding:14px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);">
          <div style="font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">Confirmados</div>
          <div style="font-size:30px;font-weight:950;margin-top:8px;">${status.eventosConfirmados || 0}</div>
          <div style="font-size:12px;color:#22c55e;font-weight:800;">eventos confirmados</div>
        </div>

        <div style="padding:14px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);">
          <div style="font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">Em espera</div>
          <div style="font-size:30px;font-weight:950;margin-top:8px;">${status.eventosEmEspera || 0}</div>
          <div style="font-size:12px;color:#fbbf24;font-weight:800;">eventos em espera</div>
        </div>

        <div style="padding:14px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);">
          <div style="font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.55);font-weight:900;">Status</div>
          <div style="font-size:18px;font-weight:950;margin-top:12px;color:#22c55e;">Supabase OK</div>
          <div style="font-size:12px;color:rgba(255,255,255,.65);font-weight:800;">dados restaurados no deploy</div>
        </div>
      </div>
    `;

    const btn = document.getElementById("cejas-atualizar-status-oficial");
    if (btn) {
      btn.onclick = async function () {
        btn.textContent = "Atualizando...";
        try {
          const novo = await carregarStatusOficial();
          if (novo && novo.ok) criarPainel(novo);
        } finally {
          btn.textContent = "Atualizar dados";
        }
      };
    }
  }

  async function iniciar() {
    try {
      const status = await carregarStatusOficial();

      if (!status || !status.ok) {
        console.warn("Relatório oficial não carregou:", status);
        return;
      }

      criarPainel(status);
      console.log("✅ Dashboard oficial carregado pelo status:", status);
    } catch (error) {
      console.warn("⚠️ Erro ao carregar dashboard oficial:", error);
    }
  }

  document.addEventListener("DOMContentLoaded", iniciar);
  setTimeout(iniciar, 700);
  setTimeout(iniciar, 1800);
  setTimeout(iniciar, 3500);

  window.cejasAtualizarDashboardOficial = iniciar;
})();
// CEJAS_DASHBOARD_STATUS_OFICIAL_END
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

echo ""
echo "✅ Dashboard corrigido para usar /api/sistema/relatorio-oficial-status."
echo ""
echo "Agora rode:"
echo "npm start"
