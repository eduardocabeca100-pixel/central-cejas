#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "orcamentos.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde fica orcamentos.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/pdf-orcamento-a4-final-$STAMP"
mkdir -p "$BACKUP_DIR"
cp orcamentos.html "$BACKUP_DIR/orcamentos.html"

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("orcamentos.html")
s = p.read_text()

# Remove correção anterior, se existir.
s = re.sub(
    r"\s*/\* CEJAS_ORCAMENTO_PDF_FIX_FINAL_START \*/[\s\S]*?/\* CEJAS_ORCAMENTO_PDF_FIX_FINAL_END \*/",
    "",
    s
)

css = r'''
    /* CEJAS_ORCAMENTO_PDF_FIX_FINAL_START */

    /* Remove cronômetro/contador da tela de orçamento e da exportação */
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

    .document.cejas-orcamento-folha {
      background: #fff !important;
      color: #1f2937 !important;
    }

    .document.cejas-orcamento-folha table {
      border-collapse: collapse !important;
      table-layout: fixed !important;
      width: 100% !important;
    }

    .document.cejas-orcamento-folha th,
    .document.cejas-orcamento-folha td {
      word-break: normal !important;
      overflow-wrap: break-word !important;
      vertical-align: top !important;
    }

    .document.cejas-orcamento-folha tr,
    .document.cejas-orcamento-folha .period,
    .document.cejas-orcamento-folha .conditions,
    .document.cejas-orcamento-folha .signature,
    .document.cejas-orcamento-folha .total-general {
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-wrapper {
      position: fixed !important;
      left: -100000px !important;
      top: 0 !important;
      width: 210mm !important;
      min-height: 297mm !important;
      background: #ffffff !important;
      padding: 0 !important;
      margin: 0 !important;
      overflow: visible !important;
      z-index: -1 !important;
      pointer-events: none !important;
    }

    .cejas-pdf-export-wrapper .document.cejas-exportando-pdf,
    .document.cejas-exportando-pdf {
      width: 210mm !important;
      min-height: 297mm !important;
      height: auto !important;
      max-height: none !important;
      overflow: visible !important;
      background: #ffffff !important;
      color: #1f2937 !important;
      padding: 28px 30px 26px !important;
      margin: 0 !important;
      box-shadow: none !important;
      border-radius: 0 !important;
      transform: none !important;
      transform-origin: top left !important;
      display: block !important;
      font-size: 10.5px !important;
      line-height: 1.32 !important;
    }

    .cejas-pdf-export-wrapper .doc-header {
      display: grid !important;
      grid-template-columns: 145px 1fr !important;
      gap: 18px !important;
      align-items: start !important;
      padding-bottom: 14px !important;
      border-bottom: 2px solid #1f2937 !important;
      margin-bottom: 12px !important;
    }

    .cejas-pdf-export-wrapper .doc-company {
      text-align: right !important;
      font-size: 9.5px !important;
      line-height: 1.28 !important;
      color: #374151 !important;
    }

    .cejas-pdf-export-wrapper .doc-company h1 {
      font-size: 12.2px !important;
      line-height: 1.12 !important;
      margin-bottom: 5px !important;
      color: #111827 !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-export-wrapper .doc-meta {
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      gap: 10px !important;
      margin: 0 0 12px !important;
      font-size: 10.5px !important;
      color: #374151 !important;
    }

    .cejas-pdf-export-wrapper .doc-title {
      background: #f0f1f3 !important;
      border: 1px solid #d7dbe1 !important;
      padding: 9px 12px !important;
      margin: 0 0 14px !important;
      text-align: center !important;
      text-transform: uppercase !important;
      letter-spacing: .28em !important;
      font-size: 11.8px !important;
      font-weight: 900 !important;
      color: #111827 !important;
    }

    .cejas-pdf-export-wrapper .doc-fields {
      border: 1px solid #d7dbe1 !important;
      padding: 10px 12px !important;
      margin: 0 0 13px !important;
      font-size: 11.5px !important;
      line-height: 1.7 !important;
    }

    .cejas-pdf-export-wrapper .doc-fields p {
      display: grid !important;
      grid-template-columns: 86px 1fr !important;
      gap: 8px !important;
      margin: 0 !important;
    }

    .cejas-pdf-export-wrapper .doc-period-title {
      border-left: 4px solid #64748b !important;
      padding-left: 8px !important;
      margin: 0 0 7px !important;
      font-size: 10.2px !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
      color: #111827 !important;
    }

    .cejas-pdf-export-wrapper .period {
      margin: 0 0 12px !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-wrapper .period table {
      width: 100% !important;
      border-collapse: collapse !important;
      table-layout: fixed !important;
      font-size: 9.5px !important;
      margin-bottom: 10px !important;
    }

    .cejas-pdf-export-wrapper .period th,
    .cejas-pdf-export-wrapper .period td {
      border: 1px solid #d4d8df !important;
      padding: 5px 6px !important;
      color: #111827 !important;
      line-height: 1.24 !important;
      vertical-align: top !important;
    }

    .cejas-pdf-export-wrapper .period th {
      background: #f0f1f3 !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-export-wrapper .period th:nth-child(1),
    .cejas-pdf-export-wrapper .period td:nth-child(1) {
      width: 30px !important;
      text-align: center !important;
    }

    .cejas-pdf-export-wrapper .period th:nth-child(2),
    .cejas-pdf-export-wrapper .period td:nth-child(2) {
      width: 29% !important;
    }

    .cejas-pdf-export-wrapper .period th:nth-child(3),
    .cejas-pdf-export-wrapper .period td:nth-child(3) {
      width: 38px !important;
      text-align: center !important;
    }

    .cejas-pdf-export-wrapper .period th:nth-child(5),
    .cejas-pdf-export-wrapper .period td:nth-child(5),
    .cejas-pdf-export-wrapper .period th:nth-child(6),
    .cejas-pdf-export-wrapper .period td:nth-child(6) {
      width: 86px !important;
      text-align: right !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-export-wrapper .subtotal td {
      background: #f8fafc !important;
      font-weight: 900 !important;
      font-style: italic !important;
    }

    .cejas-pdf-export-wrapper .total-general {
      width: 250px !important;
      margin: 8px 0 20px auto !important;
      border: 2px solid #1f2937 !important;
      padding: 9px 12px !important;
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      font-size: 11px !important;
      font-weight: 900 !important;
      color: #111827 !important;
    }

    .cejas-pdf-export-wrapper .total-general strong {
      font-size: 17px !important;
      color: #111827 !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-export-wrapper .conditions {
      margin-top: 18px !important;
      margin-bottom: 18px !important;
      border: 1px solid #d7dbe1 !important;
      background: #f8fafc !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-wrapper .conditions h4 {
      background: #e6e8ec !important;
      padding: 8px 12px !important;
      font-size: 8.5px !important;
      letter-spacing: .2em !important;
      color: #111827 !important;
      text-transform: uppercase !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-export-wrapper .conditions div {
      padding: 10px 12px !important;
      font-size: 9.3px !important;
      line-height: 1.48 !important;
      color: #374151 !important;
    }

    .cejas-pdf-export-wrapper .warning {
      font-weight: 900 !important;
      color: #111827 !important;
      border-top: 1px solid #e1e5eb !important;
      border-bottom: 1px solid #e1e5eb !important;
      padding: 6px 0 !important;
      margin: 6px 0 !important;
      text-transform: uppercase !important;
    }

    .cejas-pdf-export-wrapper .signature {
      display: flex !important;
      justify-content: space-between !important;
      align-items: flex-end !important;
      gap: 18px !important;
      font-size: 10px !important;
      line-height: 1.42 !important;
      color: #374151 !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
    }

    .cejas-pdf-export-wrapper .signature strong {
      display: block !important;
      color: #111827 !important;
      font-size: 11px !important;
      margin: 7px 0 2px !important;
    }

    .cejas-pdf-export-wrapper .system-mark {
      font-size: 7.5px !important;
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

    /* CEJAS_ORCAMENTO_PDF_FIX_FINAL_END */
'''

if "</style>" not in s:
    raise SystemExit("❌ Não encontrei </style> no orcamentos.html.")

s = s.replace("</style>", css + "\n  </style>", 1)

def replace_function(source, name, replacement):
    marker = f"async function {name}("
    start = source.find(marker)
    if start == -1:
        return source, False

    brace = source.find("{", start)
    if brace == -1:
        return source, False

    depth = 0
    i = brace

    while i < len(source):
        ch = source[i]

        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                return source[:start] + replacement + source[end:], True

        i += 1

    return source, False

new_pdf_function = r'''async function gerarPdfBlob() {
    await garantirBibliotecasPDF();

    const folhaOriginal = typeof encontrarFolhaDoOrcamento === "function"
      ? encontrarFolhaDoOrcamento()
      : document.querySelector(".cejas-orcamento-folha, .document");

    if (!folhaOriginal) {
      throw new Error("Não encontrei a folha do orçamento para gerar o PDF.");
    }

    const { jsPDF } = window.jspdf;

    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }

    const wrapper = document.createElement("div");
    wrapper.className = "cejas-pdf-export-wrapper";

    const clone = folhaOriginal.cloneNode(true);
    clone.classList.add("cejas-exportando-pdf");
    clone.style.transform = "none";
    clone.style.margin = "0";
    clone.style.boxShadow = "none";
    clone.style.width = "210mm";
    clone.style.minHeight = "297mm";
    clone.style.height = "auto";
    clone.style.maxHeight = "none";
    clone.style.overflow = "visible";

    // Remove cronômetro/contador da cópia que será exportada.
    [...clone.querySelectorAll("*")].forEach((el) => {
      const idClass = `${el.id || ""} ${el.className || ""}`.toLowerCase();
      const text = String(el.textContent || "").trim();

      const pareceTimer =
        idClass.includes("timer") ||
        idClass.includes("countdown") ||
        idClass.includes("cronometro") ||
        idClass.includes("cronômetro");

      const textoTimer =
        /(\d{1,2}:){1,2}\d{2}/.test(text) ||
        /cron[oô]metro/i.test(text) ||
        /contador/i.test(text);

      if (pareceTimer || textoTimer) {
        el.remove();
      }
    });

    wrapper.appendChild(clone);
    document.body.appendChild(wrapper);

    await new Promise((resolve) => setTimeout(resolve, 220));

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
      scale: 2.35,
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

    const pdf = new jsPDF("p", "mm", "a4", true);

    const pageWidthMm = 210;
    const pageHeightMm = 297;
    const pageCanvasHeight = Math.floor(canvas.width * pageHeightMm / pageWidthMm);

    let y = 0;
    let pageIndex = 0;

    while (y < canvas.height) {
      const sliceHeight = Math.min(pageCanvasHeight, canvas.height - y);

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

      if (pageIndex > 0) {
        pdf.addPage();
      }

      pdf.addImage(imgData, "JPEG", 0, 0, pageWidthMm, imgHeightMm, undefined, "FAST");

      y += sliceHeight;
      pageIndex += 1;
    }

    return pdf.output("blob");
  }'''

s, ok = replace_function(s, "gerarPdfBlob", new_pdf_function)

if not ok:
    marker = "</script>"
    if marker not in s:
        raise SystemExit("❌ Não consegui localizar a função gerarPdfBlob nem </script>.")
    s = s.replace(marker, f"<script>\n{new_pdf_function}\n</script>\n{marker}", 1)

# Ajusta rótulos de botões, se existirem.
s = s.replace("🖨 Imprimir / Gerar PDF", "🖨 Imprimir / PDF A4")
s = s.replace("Gerar PDF", "PDF A4")

# Remove ícones de relógio de títulos do documento, se existirem.
s = s.replace("⏱", "")
s = s.replace("⏰", "")
s = s.replace("🕒", "")
s = s.replace("🕘", "")

p.write_text(s)
PY

echo ""
echo "🔎 Verificando JavaScript dentro de orcamentos.html..."

node <<'NODE'
const fs = require("fs");

const html = fs.readFileSync("orcamentos.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-orcamento-pdf-final", { recursive: true });

scripts.forEach((code, index) => {
  fs.writeFileSync(`.cejas-local-backups/check-orcamento-pdf-final/script-${index + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-orcamento-pdf-final/script-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-orcamento-pdf-final

echo ""
echo "✅ PDF do orçamento corrigido."
echo ""
echo "O que foi ajustado:"
echo "- PDF A4 não fica mais encolhido."
echo "- Remove cronômetro/contador da folha."
echo "- Corrige página em branco no final."
echo "- Faz quebra em múltiplas páginas sem sobrepor conteúdo."
echo "- Mantém margens padrão A4."
echo ""
echo "Agora rode:"
echo "npm run dev"
echo ""
echo "Teste em:"
echo "http://localhost:5500/orcamentos.html"
