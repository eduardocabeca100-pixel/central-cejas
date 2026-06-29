#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "orcamentos.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde fica orcamentos.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/orcamento-pdf-definitivo-$STAMP"
mkdir -p "$BACKUP_DIR"
cp orcamentos.html "$BACKUP_DIR/orcamentos.html"

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("orcamentos.html")
s = p.read_text()

# Remove versões anteriores do patch, se existirem.
s = re.sub(
    r"\s*/\* CEJAS_ORCAMENTO_PDF_DEFINITIVO_START \*/[\s\S]*?/\* CEJAS_ORCAMENTO_PDF_DEFINITIVO_END \*/",
    "",
    s
)

s = re.sub(
    r"\s*<script>\s*// CEJAS_ORCAMENTO_PDF_DEFINITIVO_JS_START[\s\S]*?// CEJAS_ORCAMENTO_PDF_DEFINITIVO_JS_END\s*</script>",
    "",
    s
)

css = r'''
    /* CEJAS_ORCAMENTO_PDF_DEFINITIVO_START */

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

    .cejas-pdf-export-root {
      position: fixed !important;
      left: -100000px !important;
      top: 0 !important;
      width: 210mm !important;
      background: #ffffff !important;
      padding: 0 !important;
      margin: 0 !important;
      z-index: -1 !important;
      pointer-events: none !important;
      overflow: visible !important;
    }

    .cejas-pdf-export-root .document,
    .cejas-pdf-export-root .cejas-orcamento-folha,
    .cejas-pdf-export-document {
      width: 210mm !important;
      min-height: auto !important;
      height: auto !important;
      max-height: none !important;
      overflow: visible !important;
      background: #ffffff !important;
      color: #111827 !important;
      padding: 27mm 12mm 18mm !important;
      margin: 0 !important;
      box-shadow: none !important;
      border-radius: 0 !important;
      transform: none !important;
      transform-origin: top left !important;
      display: block !important;
      font-size: 10px !important;
      line-height: 1.28 !important;
    }

    .cejas-pdf-export-root .topbar,
    .cejas-pdf-export-root .toolbar,
    .cejas-pdf-export-root .actions,
    .cejas-pdf-export-root .editor,
    .cejas-pdf-export-root .sidebar,
    .cejas-pdf-export-root button,
    .cejas-pdf-export-root .btn,
    .cejas-pdf-export-root .modal,
    .cejas-pdf-export-root .preview-actions,
    .cejas-pdf-export-root [data-no-pdf],
    .cejas-pdf-export-root [contenteditable="true"] {
      display: none !important;
      visibility: hidden !important;
    }

    .cejas-pdf-export-root .doc-header {
      display: grid !important;
      grid-template-columns: 35mm 1fr !important;
      align-items: start !important;
      gap: 8mm !important;
      padding-bottom: 8mm !important;
      border-bottom: 1.4px solid #111827 !important;
      margin-bottom: 5mm !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root .cejas-logo img {
      max-width: 24mm !important;
      height: auto !important;
      display: block !important;
    }

    .cejas-pdf-export-root .doc-company {
      text-align: right !important;
      font-size: 8.5px !important;
      line-height: 1.25 !important;
      color: #374151 !important;
    }

    .cejas-pdf-export-root .doc-company h1 {
      font-size: 11px !important;
      line-height: 1.1 !important;
      margin: 0 0 4px !important;
      color: #111827 !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
    }

    .cejas-pdf-export-root .doc-meta {
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      gap: 10px !important;
      margin: 0 0 5mm !important;
      font-size: 9.5px !important;
      color: #374151 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root .doc-title {
      background: #f3f4f6 !important;
      border: 1px solid #d1d5db !important;
      padding: 3mm 4mm !important;
      margin: 0 0 5mm !important;
      text-align: center !important;
      text-transform: uppercase !important;
      letter-spacing: .25em !important;
      font-size: 10.5px !important;
      font-weight: 900 !important;
      color: #111827 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root .doc-fields {
      border: 1px solid #d1d5db !important;
      padding: 4mm !important;
      margin: 0 0 5mm !important;
      font-size: 10px !important;
      line-height: 1.7 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root .doc-fields p {
      display: grid !important;
      grid-template-columns: 27mm 1fr !important;
      gap: 4mm !important;
      margin: 0 !important;
    }

    .cejas-pdf-export-root .doc-period-title {
      border-left: 4px solid #64748b !important;
      padding-left: 8px !important;
      margin: 0 0 3mm !important;
      font-size: 9.5px !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
      color: #111827 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root .period {
      margin: 0 0 5mm !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root table {
      width: 100% !important;
      border-collapse: collapse !important;
      table-layout: fixed !important;
      font-size: 8.8px !important;
      margin: 0 !important;
    }

    .cejas-pdf-export-root th,
    .cejas-pdf-export-root td {
      border: 1px solid #d1d5db !important;
      padding: 4px 5px !important;
      color: #111827 !important;
      line-height: 1.2 !important;
      vertical-align: top !important;
      word-break: normal !important;
      overflow-wrap: break-word !important;
    }

    .cejas-pdf-export-root th {
      background: #f3f4f6 !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-export-root tr {
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root th:nth-child(1),
    .cejas-pdf-export-root td:nth-child(1) {
      width: 8mm !important;
      text-align: center !important;
    }

    .cejas-pdf-export-root th:nth-child(2),
    .cejas-pdf-export-root td:nth-child(2) {
      width: 31mm !important;
    }

    .cejas-pdf-export-root th:nth-child(3),
    .cejas-pdf-export-root td:nth-child(3) {
      width: 10mm !important;
      text-align: center !important;
    }

    .cejas-pdf-export-root th:nth-child(5),
    .cejas-pdf-export-root td:nth-child(5),
    .cejas-pdf-export-root th:nth-child(6),
    .cejas-pdf-export-root td:nth-child(6) {
      width: 24mm !important;
      text-align: right !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-export-root .subtotal td {
      background: #f8fafc !important;
      font-weight: 900 !important;
      font-style: italic !important;
    }

    .cejas-pdf-export-root .total-general {
      width: 68mm !important;
      margin: 4mm 0 6mm auto !important;
      border: 1.5px solid #111827 !important;
      padding: 4mm !important;
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      font-size: 10px !important;
      font-weight: 900 !important;
      color: #111827 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root .total-general strong {
      font-size: 14px !important;
      color: #111827 !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-export-root .conditions {
      margin-top: 7mm !important;
      margin-bottom: 6mm !important;
      border: 1px solid #d1d5db !important;
      background: #f8fafc !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root .conditions h4 {
      background: #e5e7eb !important;
      padding: 3mm 4mm !important;
      font-size: 8px !important;
      letter-spacing: .18em !important;
      color: #111827 !important;
      text-transform: uppercase !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-export-root .conditions div {
      padding: 4mm !important;
      font-size: 8.5px !important;
      line-height: 1.42 !important;
      color: #374151 !important;
    }

    .cejas-pdf-export-root .warning {
      font-weight: 900 !important;
      color: #111827 !important;
      border-top: 1px solid #e5e7eb !important;
      border-bottom: 1px solid #e5e7eb !important;
      padding: 5px 0 !important;
      margin: 5px 0 !important;
      text-transform: uppercase !important;
    }

    .cejas-pdf-export-root .signature {
      display: flex !important;
      justify-content: space-between !important;
      align-items: flex-end !important;
      gap: 18px !important;
      font-size: 9.4px !important;
      line-height: 1.35 !important;
      color: #374151 !important;
      margin-top: 5mm !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-root .signature strong {
      display: block !important;
      color: #111827 !important;
      font-size: 10px !important;
      margin: 5px 0 2px !important;
    }

    .cejas-pdf-export-root .system-mark {
      font-size: 7px !important;
      color: #9ca3af !important;
      text-transform: uppercase !important;
      white-space: nowrap !important;
    }

    @media print {
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
      }

      @page {
        size: A4;
        margin: 0;
      }
    }

    /* CEJAS_ORCAMENTO_PDF_DEFINITIVO_END */
'''

if "</style>" not in s:
    raise SystemExit("❌ Não encontrei </style> no orcamentos.html.")

s = s.replace("</style>", css + "\n  </style>", 1)

js = r'''
<script>
// CEJAS_ORCAMENTO_PDF_DEFINITIVO_JS_START
(function () {
  if (window.__CEJAS_ORCAMENTO_PDF_DEFINITIVO__) return;
  window.__CEJAS_ORCAMENTO_PDF_DEFINITIVO__ = true;

  function carregarScriptCEJAS(src) {
    return new Promise((resolve, reject) => {
      const existente = [...document.scripts].find((s) => s.src && s.src.includes(src));
      if (existente) return resolve();

      const script = document.createElement("script");
      script.src = src;
      script.onload = resolve;
      script.onerror = () => reject(new Error("Não foi possível carregar " + src));
      document.head.appendChild(script);
    });
  }

  async function garantirBibliotecasPDFCEJAS() {
    if (!window.html2canvas) {
      await carregarScriptCEJAS("https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js");
    }

    if (!window.jspdf || !window.jspdf.jsPDF) {
      await carregarScriptCEJAS("https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js");
    }
  }

  function contemDocumentoOrcamentoCEJAS(el) {
    const texto = String(el && el.innerText || "").toUpperCase();

    return texto.includes("DOCUMENTO AUXILIAR DE VENDA") ||
      texto.includes("ORÇAMENTO LOCAÇÃO") ||
      texto.includes("ORCAMENTO LOCACAO") ||
      texto.includes("SOLICITANTE:");
  }

  function localizarFolhaOrcamentoCEJAS() {
    const seletores = [
      ".cejas-orcamento-folha",
      ".document",
      "#document",
      "#orcamentoDocumento",
      "#orcamentoPreview",
      "[data-orcamento-documento]"
    ];

    for (const seletor of seletores) {
      const candidatos = [...document.querySelectorAll(seletor)];

      for (const candidato of candidatos) {
        if (contemDocumentoOrcamentoCEJAS(candidato)) {
          return candidato;
        }
      }
    }

    const todos = [...document.body.querySelectorAll("main *")]
      .filter((el) => el.children.length > 0 && contemDocumentoOrcamentoCEJAS(el))
      .sort((a, b) => a.getBoundingClientRect().width - b.getBoundingClientRect().width);

    if (todos.length) return todos[0];

    throw new Error("Não encontrei a folha do orçamento. A tela abriu, mas o documento não foi localizado.");
  }

  function limparCloneParaPDFCEJAS(clone) {
    const remover = [];

    [...clone.querySelectorAll("*")].forEach((el) => {
      const idClass = `${el.id || ""} ${el.className || ""}`.toLowerCase();
      const texto = String(el.textContent || "").trim();

      const ehControle =
        idClass.includes("timer") ||
        idClass.includes("countdown") ||
        idClass.includes("cronometro") ||
        idClass.includes("cronômetro") ||
        idClass.includes("toolbar") ||
        idClass.includes("actions") ||
        idClass.includes("modal") ||
        idClass.includes("btn") ||
        el.tagName === "BUTTON";

      const textoControle =
        /conectado\s+\d/i.test(texto) ||
        /voltar ao painel/i.test(texto) ||
        /cadastro de itens/i.test(texto) ||
        /salvar pdf/i.test(texto) ||
        /imprimir/i.test(texto) ||
        /(\d{1,3}:){1,2}\d{2}/.test(texto);

      if (ehControle || textoControle) {
        remover.push(el);
      }
    });

    remover.forEach((el) => el.remove());

    clone.classList.add("cejas-pdf-export-document");
    clone.style.transform = "none";
    clone.style.width = "210mm";
    clone.style.height = "auto";
    clone.style.minHeight = "auto";
    clone.style.maxHeight = "none";
    clone.style.overflow = "visible";
    clone.style.margin = "0";
    clone.style.boxShadow = "none";
    clone.style.background = "#ffffff";
  }

  function canvasSliceTemConteudoCEJAS(canvas, y, h) {
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    const stepX = Math.max(20, Math.floor(canvas.width / 30));
    const stepY = Math.max(20, Math.floor(h / 30));

    for (let yy = y; yy < Math.min(canvas.height, y + h); yy += stepY) {
      for (let xx = 0; xx < canvas.width; xx += stepX) {
        const pixel = ctx.getImageData(xx, yy, 1, 1).data;
        const branco = pixel[0] > 248 && pixel[1] > 248 && pixel[2] > 248;
        if (!branco) return true;
      }
    }

    return false;
  }

  async function gerarPdfBlobCejasDefinitivo() {
    await garantirBibliotecasPDFCEJAS();

    const folha = localizarFolhaOrcamentoCEJAS();

    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }

    const wrapper = document.createElement("div");
    wrapper.className = "cejas-pdf-export-root";

    const clone = folha.cloneNode(true);
    limparCloneParaPDFCEJAS(clone);

    wrapper.appendChild(clone);
    document.body.appendChild(wrapper);

    await new Promise((resolve) => setTimeout(resolve, 250));

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
      scale: 2.15,
      useCORS: true,
      allowTaint: true,
      backgroundColor: "#ffffff",
      scrollX: 0,
      scrollY: 0,
      windowWidth: clone.scrollWidth,
      windowHeight: clone.scrollHeight,
      width: clone.scrollWidth,
      height: clone.scrollHeight
    });

    document.body.removeChild(wrapper);

    const { jsPDF } = window.jspdf;
    const pdf = new jsPDF("p", "mm", "a4", true);

    const pageWidthMm = 210;
    const pageHeightMm = 297;
    const pageCanvasHeight = Math.floor(canvas.width * pageHeightMm / pageWidthMm);

    let y = 0;
    let pageIndex = 0;

    while (y < canvas.height) {
      const remaining = canvas.height - y;
      const sliceHeight = Math.min(pageCanvasHeight, remaining);

      if (!canvasSliceTemConteudoCEJAS(canvas, y, sliceHeight) && y > 0) {
        break;
      }

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

      const imgData = pageCanvas.toDataURL("image/jpeg", 0.98);
      const imgHeightMm = sliceHeight * pageWidthMm / canvas.width;

      if (pageIndex > 0) pdf.addPage();

      pdf.addImage(imgData, "JPEG", 0, 0, pageWidthMm, imgHeightMm, undefined, "FAST");

      y += sliceHeight;
      pageIndex += 1;
    }

    return pdf.output("blob");
  }

  function nomeArquivoOrcamentoCEJAS() {
    const texto = document.body.innerText || "";
    const eventoMatch = texto.match(/Evento:\s*([^\n\r]+)/i);
    const evento = eventoMatch && eventoMatch[1]
      ? eventoMatch[1].replace(/[_\W]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "")
      : "orcamento";

    const hoje = new Date().toISOString().slice(0, 10);

    return `${evento || "orcamento"}-${hoje}.pdf`;
  }

  async function baixarPdfOrcamentoCEJAS() {
    try {
      const blob = await gerarPdfBlobCejasDefinitivo();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");

      a.href = url;
      a.download = nomeArquivoOrcamentoCEJAS();
      document.body.appendChild(a);
      a.click();
      a.remove();

      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error) {
      alert("Erro ao gerar PDF do orçamento: " + error.message);
      throw error;
    }
  }

  window.gerarPdfBlob = gerarPdfBlobCejasDefinitivo;
  window.gerarPDFBlob = gerarPdfBlobCejasDefinitivo;
  window.gerarPdfBlobCejasDefinitivo = gerarPdfBlobCejasDefinitivo;

  window.gerarPdf = baixarPdfOrcamentoCEJAS;
  window.gerarPDF = baixarPdfOrcamentoCEJAS;
  window.imprimirOrcamento = baixarPdfOrcamentoCEJAS;
  window.baixarPdfOrcamento = baixarPdfOrcamentoCEJAS;

  document.addEventListener("click", function (event) {
    const botao = event.target.closest("button, a");
    if (!botao) return;

    const texto = String(botao.textContent || "").toLowerCase();

    const ehBotaoPdf =
      texto.includes("imprimir") ||
      texto.includes("pdf a4") ||
      texto.includes("gerar pdf");

    const ehSalvarServidor = texto.includes("salvar pdf no servidor");

    if (ehBotaoPdf && !ehSalvarServidor) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      baixarPdfOrcamentoCEJAS();
    }
  }, true);

  console.log("✅ CEJAS: exportação definitiva de orçamento A4 ativa.");
})();
// CEJAS_ORCAMENTO_PDF_DEFINITIVO_JS_END
</script>
'''

if "</body>" not in s:
    raise SystemExit("❌ Não encontrei </body> no orcamentos.html.")

s = s.replace("</body>", js + "\n</body>", 1)

p.write_text(s)
PY

echo "🔎 Verificando JavaScript do orcamentos.html..."

node <<'NODE'
const fs = require("fs");

const html = fs.readFileSync("orcamentos.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-orcamento-pdf-definitivo", { recursive: true });

scripts.forEach((code, index) => {
  fs.writeFileSync(`.cejas-local-backups/check-orcamento-pdf-definitivo/script-${index + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-orcamento-pdf-definitivo/script-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-orcamento-pdf-definitivo

echo ""
echo "✅ Orçamento/PDF corrigido."
echo ""
echo "O que este patch faz:"
echo "- Não captura mais a interface do sistema como página 1."
echo "- Exporta somente a folha do orçamento."
echo "- Remove cronômetro/contador do PDF."
echo "- Evita página em branco no final."
echo "- Mantém quebra A4 para orçamentos com mais de uma página."
echo ""
echo "Agora rode:"
echo "npm run dev"
echo ""
echo "Teste em:"
echo "http://localhost:5500/orcamentos.html"
