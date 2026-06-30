#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "dashboard.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e dashboard.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/restaurar-painel-receita-real-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js dashboard.html package.json "$BACKUP_DIR/" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("server.js")
s = p.read_text()

route = r'''
// CEJAS_RECEITA_MENSAL_API_START
app.get("/api/cejas/receita-mensal", async (_req, res) => {
  try {
    const fs = require("fs");
    const path = require("path");

    const DATA_DIR = path.join(__dirname, "data");

    function numeroBR(valor) {
      if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

      const texto = String(valor || "")
        .replace(/R\$/gi, "")
        .replace(/\s/g, "")
        .replace(/\./g, "")
        .replace(",", ".");

      const numero = Number(texto);
      return Number.isFinite(numero) ? numero : 0;
    }

    function dataISO(valor) {
      const texto = String(valor || "").trim();

      if (/^\d{4}-\d{2}-\d{2}/.test(texto)) return texto.slice(0, 10);

      let m = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/);
      if (m) return `${m[3]}-${String(m[2]).padStart(2, "0")}-${String(m[1]).padStart(2, "0")}`;

      m = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2})\b/);
      if (m) return `20${m[3]}-${String(m[2]).padStart(2, "0")}-${String(m[1]).padStart(2, "0")}`;

      return "";
    }

    function statusConfirmado(item) {
      const status = String(
        item.status ||
        item.situacao ||
        item.estado ||
        item.confirmacao ||
        item.statusEvento ||
        ""
      ).toUpperCase();

      if (!status) return false;

      return status.includes("CONFIRM") ||
        status.includes("LIBERAD") ||
        status.includes("REALIZAD") ||
        status.includes("APROVAD");
    }

    function valorEvento(item) {
      const campos = [
        item.receitaConfirmada,
        item.valorConfirmado,
        item.valorPago,
        item.valorFinal,
        item.valorTotal,
        item.total,
        item.valor,
        item.preco
      ];

      for (const campo of campos) {
        const n = numeroBR(campo);
        if (n > 0) return n;
      }

      return 0;
    }

    function dataEvento(item) {
      return dataISO(
        item.dataISO ||
        item.data ||
        item.dataEvento ||
        item.inicio ||
        item.start ||
        item.date ||
        ""
      );
    }

    function pareceEvento(item) {
      if (!item || typeof item !== "object" || Array.isArray(item)) return false;

      return Boolean(
        item.evento ||
        item.nomeEvento ||
        item.titulo ||
        item.title ||
        item.sala ||
        item.local ||
        item.data ||
        item.dataEvento ||
        item.valorTotal ||
        item.receitaConfirmada ||
        item.valorConfirmado
      );
    }

    function extrairEventos(obj, lista = []) {
      if (!obj) return lista;

      if (Array.isArray(obj)) {
        obj.forEach(item => extrairEventos(item, lista));
        return lista;
      }

      if (typeof obj !== "object") return lista;

      if (pareceEvento(obj)) lista.push(obj);

      Object.values(obj).forEach(value => {
        if (value && typeof value === "object") extrairEventos(value, lista);
      });

      return lista;
    }

    function listarJson(dir, result = []) {
      if (!fs.existsSync(dir)) return result;

      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);

        if (entry.isDirectory()) listarJson(full, result);
        else if (entry.isFile() && entry.name.endsWith(".json")) result.push(full);
      }

      return result;
    }

    const arquivos = listarJson(DATA_DIR);
    const eventos = [];

    for (const file of arquivos) {
      try {
        const json = JSON.parse(fs.readFileSync(file, "utf8"));
        extrairEventos(json, eventos);
      } catch {}
    }

    const porMes = {};
    let totalConfirmado = 0;
    let qtdConfirmados = 0;

    for (const ev of eventos) {
      if (!statusConfirmado(ev)) continue;

      const iso = dataEvento(ev);
      const valor = valorEvento(ev);

      if (!iso || !valor) continue;

      const key = iso.slice(0, 7);

      porMes[key] = porMes[key] || {
        key,
        valor: 0,
        quantidade: 0
      };

      porMes[key].valor += valor;
      porMes[key].quantidade += 1;

      totalConfirmado += valor;
      qtdConfirmados += 1;
    }

    const nomes = [
      "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
      "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    ];

    let meses = Object.values(porMes)
      .sort((a, b) => a.key.localeCompare(b.key))
      .map(item => {
        const [ano, mes] = item.key.split("-");
        return {
          ...item,
          mes: nomes[Number(mes) - 1] || item.key,
          mesCurto: (nomes[Number(mes) - 1] || item.key).slice(0, 3),
          ano
        };
      });

    res.set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");

    res.json({
      ok: true,
      meses,
      totalConfirmado,
      qtdConfirmados,
      arquivosLidos: arquivos.length,
      eventosEncontrados: eventos.length,
      atualizadoEm: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_RECEITA_MENSAL_API_END
'''

if "CEJAS_RECEITA_MENSAL_API_START" not in s:
    marker = "const app = express();"
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express(); no server.js.")
    s = s.replace(marker, marker + "\n" + route, 1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("dashboard.html")
s = p.read_text()

s = re.sub(
    r'\s*<script>\s*// CEJAS_RECEITA_MENSAL_TOP_REAL_START[\s\S]*?// CEJAS_RECEITA_MENSAL_TOP_REAL_END\s*</script>',
    '',
    s
)

s = re.sub(
    r'\s*/\* CEJAS_RECEITA_MENSAL_TOP_REAL_CSS_START \*/[\s\S]*?/\* CEJAS_RECEITA_MENSAL_TOP_REAL_CSS_END \*/',
    '',
    s
)

css = r'''
    /* CEJAS_RECEITA_MENSAL_TOP_REAL_CSS_START */
    .cejas-receita-mensal-top {
      margin-top: 14px;
      padding: 16px;
      border: 1px solid rgba(34,197,94,.22);
      border-radius: 18px;
      background: rgba(34,197,94,.07);
    }

    .cejas-receita-mensal-top-head {
      display: flex;
      justify-content: space-between;
      gap: 18px;
      align-items: flex-start;
      margin-bottom: 14px;
    }

    .cejas-receita-mensal-top-head strong {
      display: block;
      color: #fff;
      font-size: 15px;
      font-weight: 950;
    }

    .cejas-receita-mensal-top-head small {
      display: block;
      margin-top: 4px;
      color: rgba(255,255,255,.62);
      font-size: 11px;
      line-height: 1.35;
    }

    .cejas-receita-mensal-total {
      color: #22c55e;
      font-size: 22px;
      font-weight: 950;
      white-space: nowrap;
      text-align: right;
    }

    .cejas-receita-mensal-grid {
      display: grid;
      grid-template-columns: repeat(6, minmax(110px, 1fr));
      gap: 10px;
    }

    .cejas-receita-mes-card {
      padding: 12px;
      border-radius: 14px;
      background: rgba(0,0,0,.22);
      border: 1px solid rgba(255,255,255,.08);
    }

    .cejas-receita-mes-card span {
      display: block;
      color: rgba(255,255,255,.62);
      font-size: 10px;
      letter-spacing: .13em;
      text-transform: uppercase;
      font-weight: 900;
      margin-bottom: 5px;
    }

    .cejas-receita-mes-card strong {
      color: #22c55e;
      font-size: 16px;
      font-weight: 950;
    }

    .cejas-receita-mes-card small {
      display: block;
      margin-top: 4px;
      color: rgba(255,255,255,.52);
      font-size: 10px;
    }

    .cejas-receita-mensal-bars {
      margin-top: 14px;
      height: 150px;
      display: flex;
      align-items: flex-end;
      gap: 12px;
      padding: 14px 6px 0;
      border-radius: 14px;
      background:
        linear-gradient(to top, rgba(255,255,255,.045) 1px, transparent 1px);
      background-size: 100% 36px;
      overflow-x: auto;
    }

    .cejas-receita-bar-item {
      min-width: 54px;
      flex: 1;
      max-width: 90px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: flex-end;
      height: 100%;
      gap: 7px;
    }

    .cejas-receita-bar-real {
      width: 100%;
      min-height: 8px;
      border-radius: 12px 12px 5px 5px;
      background: linear-gradient(180deg, #4ade80, #16a34a);
      box-shadow: 0 12px 30px rgba(34,197,94,.22);
    }

    .cejas-receita-bar-label {
      color: rgba(255,255,255,.72);
      font-size: 10px;
      font-weight: 900;
      text-transform: uppercase;
    }

    @media (max-width: 900px) {
      .cejas-receita-mensal-grid {
        grid-template-columns: repeat(2, minmax(120px, 1fr));
      }

      .cejas-receita-mensal-top-head {
        flex-direction: column;
      }

      .cejas-receita-mensal-total {
        text-align: left;
      }
    }
    /* CEJAS_RECEITA_MENSAL_TOP_REAL_CSS_END */
'''

if "</style>" in s:
    s = s.replace("</style>", css + "\n</style>", 1)
elif "</head>" in s:
    s = s.replace("</head>", "<style>\n" + css + "\n</style>\n</head>", 1)
else:
    s = "<style>\n" + css + "\n</style>\n" + s

js = r'''
<script>
// CEJAS_RECEITA_MENSAL_TOP_REAL_START
(function () {
  if (window.__CEJAS_RECEITA_MENSAL_TOP_REAL__) return;
  window.__CEJAS_RECEITA_MENSAL_TOP_REAL__ = true;

  function dinheiroBR(valor) {
    return Number(valor || 0).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });
  }

  function encontrarPainelReceitaMensal() {
    const blocos = [...document.querySelectorAll("section, article, div")];

    return blocos.find(el => {
      const txt = String(el.textContent || "").toLowerCase();
      return txt.includes("receita mensal confirmada") &&
        txt.includes("valores calculados somente com eventos confirmados");
    });
  }

  function limparMensagemErro(bloco) {
    [...bloco.querySelectorAll("p,span,small,div")].forEach(el => {
      const txt = String(el.textContent || "").toLowerCase();

      if (
        txt.includes("não foi possível carregar a receita mensal") ||
        txt.includes("nenhuma receita confirmada encontrada")
      ) {
        el.remove();
      }
    });
  }

  async function carregarReceitaMensal() {
    const response = await fetch(`/api/cejas/receita-mensal?_ts=${Date.now()}`, {
      cache: "no-store"
    });

    const data = await response.json();

    if (!response.ok || data.ok === false) {
      throw new Error(data.message || "Falha ao carregar receita mensal.");
    }

    return data;
  }

  function renderizar(bloco, data) {
    limparMensagemErro(bloco);

    let box = bloco.querySelector("#cejasReceitaMensalTopReal");

    if (!box) {
      box = document.createElement("div");
      box.id = "cejasReceitaMensalTopReal";
      box.className = "cejas-receita-mensal-top";
      bloco.appendChild(box);
    }

    const meses = Array.isArray(data.meses) ? data.meses : [];
    const total = meses.reduce((acc, item) => acc + Number(item.valor || 0), 0) || Number(data.totalConfirmado || 0);
    const max = Math.max(...meses.map(item => Number(item.valor || 0)), 1);

    box.innerHTML = `
      <div class="cejas-receita-mensal-top-head">
        <div>
          <strong>Receita confirmada por mês</strong>
          <small>${data.qtdConfirmados || 0} eventos confirmados encontrados no relatório. Atualizado automaticamente pelo PDF importado.</small>
        </div>
        <div class="cejas-receita-mensal-total">${dinheiroBR(total)}</div>
      </div>

      <div class="cejas-receita-mensal-grid">
        ${
          meses.length
            ? meses.map(item => `
              <div class="cejas-receita-mes-card">
                <span>${item.mes} ${item.ano || ""}</span>
                <strong>${dinheiroBR(item.valor)}</strong>
                <small>${item.quantidade || 0} evento(s)</small>
              </div>
            `).join("")
            : `
              <div class="cejas-receita-mes-card">
                <span>Sem meses</span>
                <strong>R$ 0,00</strong>
                <small>Importe ou atualize o relatório</small>
              </div>
            `
        }
      </div>

      ${
        meses.length
          ? `
            <div class="cejas-receita-mensal-bars">
              ${meses.map(item => {
                const h = Math.max(8, Math.round((Number(item.valor || 0) / max) * 125));
                return `
                  <div class="cejas-receita-bar-item" title="${item.mes}: ${dinheiroBR(item.valor)}">
                    <div class="cejas-receita-bar-real" style="height:${h}px"></div>
                    <div class="cejas-receita-bar-label">${item.mesCurto || String(item.mes).slice(0,3)}</div>
                  </div>
                `;
              }).join("")}
            </div>
          `
          : ""
      }
    `;
  }

  async function iniciar() {
    const bloco = encontrarPainelReceitaMensal();

    if (!bloco) return;

    try {
      const data = await carregarReceitaMensal();
      renderizar(bloco, data);
    } catch (error) {
      console.warn("Receita mensal CEJAS:", error);
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    setTimeout(iniciar, 400);
    setTimeout(iniciar, 1500);
    setTimeout(iniciar, 3500);
  });

  document.addEventListener("click", event => {
    const btn = event.target.closest("button,a");
    if (!btn) return;

    const txt = String(btn.textContent || "").toLowerCase();

    if (txt.includes("atualizar dados") || txt.includes("importar")) {
      setTimeout(iniciar, 1500);
      setTimeout(iniciar, 4000);
    }
  });

  window.restaurarReceitaMensalTopCejas = iniciar;
})();
// CEJAS_RECEITA_MENSAL_TOP_REAL_END
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

node <<'NODE'
const fs = require("fs");
const html = fs.readFileSync("dashboard.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-receita-real", { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-receita-real/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-receita-real/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-receita-real

echo ""
echo "✅ Painel mensal real restaurado."
echo ""
echo "Agora rode:"
echo "npm start"
echo ""
echo "Teste a API:"
echo "http://localhost:5500/api/cejas/receita-mensal"
