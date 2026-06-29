#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/hotfix-final-render-storage-orcamento-$STAMP"
mkdir -p "$BACKUP_DIR" lib scripts

cp server.js package.json orcamentos.html "$BACKUP_DIR/" 2>/dev/null || true
[ -d lib ] && cp -R lib "$BACKUP_DIR/lib" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

echo "🔧 Recriando lib/supabase.js com leitura correta das variáveis do Render..."

cat > lib/supabase.js <<'EOF'
require("dotenv").config();

const { createClient } = require("@supabase/supabase-js");

const SUPABASE_URL =
  process.env.SUPABASE_URL ||
  process.env.NEXT_PUBLIC_SUPABASE_URL ||
  process.env.PUBLIC_SUPABASE_URL ||
  "";

const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  process.env.SUPABASE_PUBLISHABLE_KEY ||
  "";

const SUPABASE_SERVICE_ROLE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_SERVICE_KEY ||
  process.env.SUPABASE_SERVICE_ROLE ||
  "";

const SUPABASE_BUCKET =
  process.env.SUPABASE_STORAGE_BUCKET ||
  process.env.SUPABASE_BUCKET ||
  "servidor-cejas";

function isSupabaseConfigured() {
  return Boolean(SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY);
}

const supabase = SUPABASE_URL && SUPABASE_ANON_KEY
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    })
  : null;

const supabaseAdmin = SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    })
  : null;

function getSupabaseEnvStatus() {
  return {
    ok: isSupabaseConfigured(),
    has_SUPABASE_URL: Boolean(process.env.SUPABASE_URL),
    has_NEXT_PUBLIC_SUPABASE_URL: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    has_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    has_SUPABASE_STORAGE_BUCKET: Boolean(process.env.SUPABASE_STORAGE_BUCKET),
    bucket: SUPABASE_BUCKET,
    resolvedUrl: Boolean(SUPABASE_URL),
    resolvedServiceRole: Boolean(SUPABASE_SERVICE_ROLE_KEY)
  };
}

module.exports = {
  supabase,
  supabaseAdmin,
  isSupabaseConfigured,
  getSupabaseEnvStatus,
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_BUCKET
};
EOF

echo "🔧 Ajustando módulo definitivo do Servidor para usar essa leitura..."

python3 <<'PY'
from pathlib import Path

p = Path("lib/servidor-supabase-definitivo.js")
if not p.exists():
    raise SystemExit("❌ Não encontrei lib/servidor-supabase-definitivo.js.")

s = p.read_text()

if 'const express = require("express");' not in s:
    s = s.replace('const fs = require("fs");', 'const fs = require("fs");\nconst express = require("express");', 1)

# Garante que a mensagem de erro não acuse variável errada quando NEXT_PUBLIC_SUPABASE_URL existe.
s = s.replace(
  'throw new Error("Supabase Storage não configurado. Confira SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e SUPABASE_STORAGE_BUCKET.");',
  'throw new Error("Supabase Storage não configurado no runtime. O sistema aceita NEXT_PUBLIC_SUPABASE_URL ou SUPABASE_URL, mas precisa obrigatoriamente de SUPABASE_SERVICE_ROLE_KEY e SUPABASE_STORAGE_BUCKET.");'
)

p.write_text(s)
PY

echo "🔧 Adicionando rota segura para diagnosticar o ambiente no Render..."

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const { getSupabaseEnvStatus } = require("./lib/supabase");'
if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace('const path = require("path");', 'const path = require("path");\n' + require_line, 1)
    else:
        s = require_line + "\n" + s

route = r'''
// CEJAS_SUPABASE_ENV_DEBUG_START
app.get("/api/debug/supabase-env", (_req, res) => {
  try {
    res.json({
      ok: true,
      supabase: getSupabaseEnvStatus()
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_SUPABASE_ENV_DEBUG_END
'''

if "CEJAS_SUPABASE_ENV_DEBUG_START" not in s:
    marker = "const app = express();"
    if marker in s:
        s = s.replace(marker, marker + "\n" + route, 1)
    else:
        raise SystemExit("❌ Não encontrei const app = express();")

p.write_text(s)
PY

echo "🔧 Corrigindo geração do PDF do orçamento para pegar o documento preenchido..."

python3 <<'PY'
from pathlib import Path
import re

p = Path("orcamentos.html")
if not p.exists():
    raise SystemExit("❌ Não encontrei orcamentos.html.")

s = p.read_text()

# Remove somente o patch final anterior, se existir.
s = re.sub(
    r"\s*/\* CEJAS_ORCAMENTO_PDF_FINAL_REAL_START \*/[\s\S]*?/\* CEJAS_ORCAMENTO_PDF_FINAL_REAL_END \*/",
    "",
    s
)

s = re.sub(
    r"\s*<script>\s*// CEJAS_ORCAMENTO_PDF_FINAL_REAL_JS_START[\s\S]*?// CEJAS_ORCAMENTO_PDF_FINAL_REAL_JS_END\s*</script>",
    "",
    s
)

css = r'''
    /* CEJAS_ORCAMENTO_PDF_FINAL_REAL_START */
    .cronometro,
    .countdown,
    .countdown-card,
    .timer-card,
    .timer-box,
    .budget-timer,
    .orcamento-timer,
    .validade-timer,
    #cronometro,
    #countdown,
    #budgetTimer,
    #orcamentoTimer {
      display: none !important;
      visibility: hidden !important;
    }

    .cejas-pdf-real-root {
      position: fixed !important;
      left: -100000px !important;
      top: 0 !important;
      width: 210mm !important;
      background: #ffffff !important;
      padding: 0 !important;
      margin: 0 !important;
      overflow: visible !important;
      z-index: -1 !important;
      pointer-events: none !important;
    }

    .cejas-pdf-real-doc {
      width: 210mm !important;
      min-height: 297mm !important;
      height: auto !important;
      max-height: none !important;
      overflow: visible !important;
      background: #ffffff !important;
      color: #111827 !important;
      padding: 14mm 12mm 12mm !important;
      margin: 0 !important;
      box-shadow: none !important;
      border-radius: 0 !important;
      transform: none !important;
      transform-origin: top left !important;
      display: block !important;
      font-family: Arial, Helvetica, sans-serif !important;
      font-size: 9.2px !important;
      line-height: 1.28 !important;
      box-sizing: border-box !important;
    }

    .cejas-pdf-real-doc * {
      box-sizing: border-box !important;
    }

    .cejas-pdf-real-doc .topbar,
    .cejas-pdf-real-doc .toolbar,
    .cejas-pdf-real-doc .actions,
    .cejas-pdf-real-doc .editor,
    .cejas-pdf-real-doc .sidebar,
    .cejas-pdf-real-doc .modal,
    .cejas-pdf-real-doc button,
    .cejas-pdf-real-doc .btn,
    .cejas-pdf-real-doc [data-no-pdf] {
      display: none !important;
      visibility: hidden !important;
    }

    .cejas-pdf-real-doc .doc-header {
      display: grid !important;
      grid-template-columns: 35mm 1fr !important;
      gap: 8mm !important;
      align-items: start !important;
      padding-bottom: 8mm !important;
      border-bottom: 1.4px solid #111827 !important;
      margin-bottom: 4mm !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc .cejas-logo img {
      width: 24mm !important;
      height: auto !important;
      display: block !important;
    }

    .cejas-pdf-real-doc .doc-company {
      text-align: right !important;
      font-size: 8.2px !important;
      line-height: 1.22 !important;
      color: #374151 !important;
    }

    .cejas-pdf-real-doc .doc-company h1 {
      font-size: 10.8px !important;
      line-height: 1.1 !important;
      margin: 0 0 4px !important;
      color: #111827 !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
    }

    .cejas-pdf-real-doc .doc-meta {
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      gap: 8px !important;
      margin: 0 0 4mm !important;
      font-size: 9px !important;
      color: #374151 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc .doc-title {
      background: #f3f4f6 !important;
      border: 1px solid #d1d5db !important;
      padding: 2.8mm 4mm !important;
      margin: 0 0 4.5mm !important;
      text-align: center !important;
      text-transform: uppercase !important;
      letter-spacing: .28em !important;
      font-size: 10px !important;
      font-weight: 900 !important;
      color: #111827 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc .doc-fields {
      border: 1px solid #d1d5db !important;
      padding: 4mm !important;
      margin: 0 0 4.5mm !important;
      font-size: 9.3px !important;
      line-height: 1.65 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc .doc-fields p {
      display: grid !important;
      grid-template-columns: 25mm 1fr !important;
      gap: 4mm !important;
      margin: 0 !important;
    }

    .cejas-pdf-real-doc .doc-period-title {
      border-left: 4px solid #64748b !important;
      padding-left: 8px !important;
      margin: 0 0 2.7mm !important;
      font-size: 9px !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
      color: #111827 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc .period {
      margin: 0 0 4mm !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc table {
      width: 100% !important;
      border-collapse: collapse !important;
      table-layout: fixed !important;
      font-size: 8px !important;
      margin: 0 !important;
    }

    .cejas-pdf-real-doc th,
    .cejas-pdf-real-doc td {
      border: 1px solid #d1d5db !important;
      padding: 3.5px 4px !important;
      color: #111827 !important;
      line-height: 1.16 !important;
      vertical-align: top !important;
      overflow-wrap: break-word !important;
      word-break: normal !important;
    }

    .cejas-pdf-real-doc th {
      background: #f3f4f6 !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-real-doc tr {
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc th:nth-child(1),
    .cejas-pdf-real-doc td:nth-child(1) {
      width: 8mm !important;
      text-align: center !important;
    }

    .cejas-pdf-real-doc th:nth-child(2),
    .cejas-pdf-real-doc td:nth-child(2) {
      width: 32mm !important;
    }

    .cejas-pdf-real-doc th:nth-child(3),
    .cejas-pdf-real-doc td:nth-child(3) {
      width: 10mm !important;
      text-align: center !important;
    }

    .cejas-pdf-real-doc th:nth-child(5),
    .cejas-pdf-real-doc td:nth-child(5),
    .cejas-pdf-real-doc th:nth-child(6),
    .cejas-pdf-real-doc td:nth-child(6) {
      width: 23mm !important;
      text-align: right !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-real-doc .subtotal td {
      background: #f8fafc !important;
      font-weight: 900 !important;
      font-style: italic !important;
    }

    .cejas-pdf-real-doc .total-general {
      width: 66mm !important;
      margin: 3mm 0 5mm auto !important;
      border: 1.4px solid #111827 !important;
      padding: 3mm 4mm !important;
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      font-size: 9.5px !important;
      font-weight: 900 !important;
      color: #111827 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc .conditions {
      display: block !important;
      visibility: visible !important;
      margin-top: 8mm !important;
      margin-bottom: 5mm !important;
      border: 1px solid #d1d5db !important;
      background: #f8fafc !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc .conditions h4 {
      background: #e5e7eb !important;
      padding: 2.7mm 4mm !important;
      font-size: 7.5px !important;
      letter-spacing: .18em !important;
      color: #111827 !important;
      text-transform: uppercase !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-real-doc .conditions div {
      padding: 3.5mm 4mm !important;
      font-size: 8.2px !important;
      line-height: 1.38 !important;
      color: #374151 !important;
    }

    .cejas-pdf-real-doc .conditions p {
      margin: 0 0 2mm !important;
    }

    .cejas-pdf-real-doc .warning {
      font-weight: 900 !important;
      color: #111827 !important;
      border-top: 1px solid #e5e7eb !important;
      border-bottom: 1px solid #e5e7eb !important;
      padding: 4px 0 !important;
      margin: 4px 0 !important;
      text-transform: uppercase !important;
    }

    .cejas-pdf-real-doc .signature {
      display: flex !important;
      justify-content: space-between !important;
      align-items: flex-end !important;
      gap: 18px !important;
      font-size: 8.6px !important;
      line-height: 1.28 !important;
      color: #374151 !important;
      margin-top: 5mm !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-real-doc .signature strong {
      display: block !important;
      color: #111827 !important;
      font-size: 9.5px !important;
      margin: 4px 0 1px !important;
    }

    .cejas-pdf-real-doc .system-mark {
      font-size: 6.7px !important;
      color: #9ca3af !important;
      text-transform: uppercase !important;
      white-space: nowrap !important;
    }
    /* CEJAS_ORCAMENTO_PDF_FINAL_REAL_END */
'''

if "</style>" not in s:
    raise SystemExit("❌ Não encontrei </style>.")

s = s.replace("</style>", css + "\n  </style>", 1)

js = r'''
<script>
// CEJAS_ORCAMENTO_PDF_FINAL_REAL_JS_START
(function () {
  if (window.__CEJAS_ORCAMENTO_PDF_FINAL_REAL__) return;
  window.__CEJAS_ORCAMENTO_PDF_FINAL_REAL__ = true;

  function carregarScriptCejas(src) {
    return new Promise((resolve, reject) => {
      const existente = [...document.scripts].find((script) => script.src && script.src.includes(src));
      if (existente) return resolve();

      const script = document.createElement("script");
      script.src = src;
      script.onload = resolve;
      script.onerror = () => reject(new Error("Não foi possível carregar " + src));
      document.head.appendChild(script);
    });
  }

  async function garantirLibsCejas() {
    if (!window.html2canvas) {
      await carregarScriptCejas("https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js");
    }

    if (!window.jspdf || !window.jspdf.jsPDF) {
      await carregarScriptCejas("https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js");
    }
  }

  function prepararPreviewAntesPDF() {
    const funcoes = [
      "renderPreview",
      "atualizarPreview",
      "updatePreview",
      "renderizarOrcamento",
      "renderizarDocumento",
      "updateDocument",
      "atualizarDocumento"
    ];

    for (const nome of funcoes) {
      try {
        if (typeof window[nome] === "function") {
          window[nome]();
        }
      } catch {}
    }
  }

  function scoreDocumento(el) {
    const style = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    const text = String(el.innerText || "");

    if (style.display === "none" || style.visibility === "hidden") return -99999;
    if (rect.width < 250 || rect.height < 250) return -99999;

    const upper = text.toUpperCase();

    let score = 0;

    if (upper.includes("DOCUMENTO AUXILIAR DE VENDA")) score += 200;
    if (upper.includes("ORÇAMENTO LOCAÇÃO") || upper.includes("ORCAMENTO LOCACAO")) score += 200;
    if (upper.includes("SOLICITANTE:")) score += 80;
    if (upper.includes("EVENTO:")) score += 80;
    if (upper.includes("OBSERVAÇÕES E CONDIÇÕES")) score += 80;
    if (upper.includes("FORMAS DE PAGAMENTO")) score += 60;
    if (upper.includes("SUBTOTAL DO PERÍODO") || upper.includes("SUBTOTAL DO PERIODO")) score += 60;

    const moedas = text.match(/R\$\s*[\d.]+,\d{2}/g) || [];
    score += moedas.length * 12;

    const linhasTabela = el.querySelectorAll("tbody tr, table tr").length;
    score += linhasTabela * 8;

    const controles = [
      "cadastro de itens",
      "salvar pdf no servidor",
      "voltar ao painel",
      "selecionar",
      "adicionar item"
    ];

    for (const termo of controles) {
      if (upper.includes(termo.toUpperCase())) score -= 120;
    }

    const temCampoVazio = upper.includes("DATA NÃO INFORMADA") || upper.includes("DATA NAO INFORMADA");
    if (temCampoVazio) score -= 20;

    score += Math.min(text.length / 50, 100);

    return score;
  }

  function encontrarDocumentoPreenchido() {
    prepararPreviewAntesPDF();

    const selectors = [
      ".cejas-orcamento-folha",
      ".document",
      "#orcamentoDocumento",
      "#document",
      "#orcamentoPreview",
      "[data-orcamento-documento]"
    ];

    const candidatos = [];

    for (const selector of selectors) {
      candidatos.push(...document.querySelectorAll(selector));
    }

    const unicos = [...new Set(candidatos)];

    if (!unicos.length) {
      throw new Error("Não encontrei nenhum elemento de documento do orçamento.");
    }

    const classificados = unicos
      .map((el) => ({ el, score: scoreDocumento(el) }))
      .sort((a, b) => b.score - a.score);

    if (!classificados.length || classificados[0].score < 0) {
      throw new Error("Encontrei elementos, mas nenhum parece ser a folha preenchida do orçamento.");
    }

    return classificados[0].el;
  }

  function limparClone(clone) {
    [...clone.querySelectorAll("*")].forEach((el) => {
      const idClass = `${el.id || ""} ${el.className || ""}`.toLowerCase();
      const texto = String(el.textContent || "").trim();

      const remover =
        el.tagName === "BUTTON" ||
        idClass.includes("timer") ||
        idClass.includes("countdown") ||
        idClass.includes("cronometro") ||
        idClass.includes("toolbar") ||
        idClass.includes("actions") ||
        idClass.includes("modal") ||
        idClass.includes("btn") ||
        /conectado\s+\d/i.test(texto) ||
        /voltar ao painel/i.test(texto) ||
        /cadastro de itens/i.test(texto) ||
        /salvar pdf/i.test(texto) ||
        /imprimir/i.test(texto);

      if (remover) el.remove();
    });

    clone.classList.add("cejas-pdf-real-doc");
    clone.style.width = "210mm";
    clone.style.height = "auto";
    clone.style.minHeight = "297mm";
    clone.style.maxHeight = "none";
    clone.style.overflow = "visible";
    clone.style.transform = "none";
    clone.style.margin = "0";
    clone.style.boxShadow = "none";
    clone.style.background = "#ffffff";

    garantirCondicoes(clone);
  }

  function garantirCondicoes(clone) {
    const texto = String(clone.innerText || "").toUpperCase();

    if (texto.includes("OBSERVAÇÕES E CONDIÇÕES") || texto.includes("OBSERVACOES E CONDICOES")) {
      return;
    }

    const conditions = document.createElement("section");
    conditions.className = "conditions";
    conditions.innerHTML = `
      <h4>OBSERVAÇÕES E CONDIÇÕES</h4>
      <div>
        <p>· Orçamento válido por <strong>72 horas</strong>. A pré-reserva garante o espaço por este período; após o prazo, o evento é considerado cancelado.</p>
        <p class="warning">ATENÇÃO: O HORÁRIO LIMITE PARA FECHAMENTO TOTAL DO PRÉDIO É IMPRETERIVELMENTE ÀS 22:00H.</p>
        <p><strong>FORMAS DE PAGAMENTO:</strong></p>
        <p>– Transferência/Depósito: Sicredi Norte (Ag 2602, c/c 04247-2, titular: CEJAS).</p>
        <p>– Boleto Bancário via Sicredi Norte.</p>
        <p>– PIX CNPJ: 83.784.124/0001-32</p>
      </div>
    `;

    const signature = clone.querySelector(".signature");
    if (signature && signature.parentNode) {
      signature.parentNode.insertBefore(conditions, signature);
    } else {
      clone.appendChild(conditions);
    }
  }

  async function gerarPdfBlobFinalReal() {
    await garantirLibsCejas();

    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }

    const original = encontrarDocumentoPreenchido();

    const root = document.createElement("div");
    root.className = "cejas-pdf-real-root";

    const clone = original.cloneNode(true);
    limparClone(clone);

    root.appendChild(clone);
    document.body.appendChild(root);

    await new Promise((resolve) => setTimeout(resolve, 350));

    await Promise.all(
      [...clone.querySelectorAll("img")].map((img) => {
        if (img.complete) return Promise.resolve();

        return new Promise((resolve) => {
          img.onload = resolve;
          img.onerror = resolve;
        });
      })
    );

    const canvas = await window.html2canvas(clone, {
      scale: 2.2,
      useCORS: true,
      allowTaint: true,
      backgroundColor: "#ffffff",
      scrollX: 0,
      scrollY: 0,
      width: clone.scrollWidth,
      height: clone.scrollHeight,
      windowWidth: clone.scrollWidth,
      windowHeight: clone.scrollHeight
    });

    document.body.removeChild(root);

    const { jsPDF } = window.jspdf;
    const pdf = new jsPDF("p", "mm", "a4", true);

    const pageWidthMm = 210;
    const pageHeightMm = 297;
    const pageHeightPx = Math.floor(canvas.width * pageHeightMm / pageWidthMm);

    let y = 0;
    let pageIndex = 0;

    while (y < canvas.height) {
      const sliceHeight = Math.min(pageHeightPx, canvas.height - y);

      const pageCanvas = document.createElement("canvas");
      pageCanvas.width = canvas.width;
      pageCanvas.height = sliceHeight;

      const ctx = pageCanvas.getContext("2d");
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, pageCanvas.width, pageCanvas.height);
      ctx.drawImage(
        canvas,
        0,
        y,
        canvas.width,
        sliceHeight,
        0,
        0,
        canvas.width,
        sliceHeight
      );

      if (pageIndex > 0) {
        pdf.addPage();
      }

      const imgData = pageCanvas.toDataURL("image/jpeg", 0.98);
      const imgHeightMm = sliceHeight * pageWidthMm / canvas.width;

      pdf.addImage(imgData, "JPEG", 0, 0, pageWidthMm, imgHeightMm, undefined, "FAST");

      y += sliceHeight;
      pageIndex += 1;
    }

    return pdf.output("blob");
  }

  async function baixarPdfFinalReal() {
    const blob = await gerarPdfBlobFinalReal();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");

    a.href = url;
    a.download = `orcamento-${new Date().toISOString().slice(0, 10)}.pdf`;

    document.body.appendChild(a);
    a.click();
    a.remove();

    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  window.gerarPdfBlob = gerarPdfBlobFinalReal;
  window.gerarPDFBlob = gerarPdfBlobFinalReal;
  window.gerarPdfBlobFinalReal = gerarPdfBlobFinalReal;

  window.gerarPdf = baixarPdfFinalReal;
  window.gerarPDF = baixarPdfFinalReal;
  window.imprimirOrcamento = baixarPdfFinalReal;
  window.baixarPdfOrcamento = baixarPdfFinalReal;

  document.addEventListener("click", function (event) {
    const btn = event.target.closest("button, a");
    if (!btn) return;

    const texto = String(btn.textContent || "").toLowerCase();
    const pdfNormal = texto.includes("imprimir") || texto.includes("pdf a4") || texto.includes("gerar pdf");
    const salvarServidor = texto.includes("salvar pdf no servidor");

    if (pdfNormal && !salvarServidor) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      baixarPdfFinalReal().catch((error) => {
        alert("Erro ao gerar PDF: " + error.message);
      });
    }
  }, true);

  console.log("✅ CEJAS orçamento: PDF final real ativo.");
})();
// CEJAS_ORCAMENTO_PDF_FINAL_REAL_JS_END
</script>
'''

if "</body>" not in s:
    raise SystemExit("❌ Não encontrei </body>.")

s = s.replace("</body>", js + "\n</body>", 1)

p.write_text(s)
PY

echo "🔎 Verificando arquivos..."

node --check lib/supabase.js
node --check lib/servidor-supabase-definitivo.js
node --check server.js
node --check scripts/check-env-render.js

node <<'NODE'
const fs = require("fs");

if (fs.existsSync("orcamentos.html")) {
  const html = fs.readFileSync("orcamentos.html", "utf8");
  const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

  fs.mkdirSync(".cejas-local-backups/check-orcamento-final-real", { recursive: true });

  scripts.forEach((code, i) => {
    fs.writeFileSync(`.cejas-local-backups/check-orcamento-final-real/script-${i + 1}.js`, code);
  });
}
NODE

for f in .cejas-local-backups/check-orcamento-final-real/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-orcamento-final-real

echo ""
echo "✅ Hotfix final aplicado."
echo ""
echo "Agora rode localmente:"
echo "npm run env:check"
echo "npm run dev"
echo ""
echo "Depois suba:"
echo "git add ."
echo "git commit -m \"fix: corrige leitura env Render e PDF final dos orcamentos\""
echo "git push -u origin main"
