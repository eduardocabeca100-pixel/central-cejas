#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "orcamentos.html" ]; then
  echo "❌ Rode este comando dentro da pasta raiz do projeto, onde fica orcamentos.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/layout-orcamento-a4-$STAMP"
mkdir -p "$BACKUP_DIR"
cp orcamentos.html "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

p = Path('orcamentos.html')
s = p.read_text()

s = s.replace('<article class="document">', '<article class="document cejas-orcamento-folha">', 1)
s = s.replace('<article class="document cejas-orcamento-folha cejas-orcamento-folha">', '<article class="document cejas-orcamento-folha">')

old_logo = '''              <div class="cejas-logo">
                <strong>CEJAS</strong>
                <span>Centro Empresarial<br>de Jaraguá do Sul</span>
              </div>'''

new_logo = '''              <div class="cejas-logo">
                <img src="/assets/cejas-login-logo.png" alt="CEJAS" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                <div class="cejas-logo-fallback">
                  <strong>CEJAS</strong>
                  <span>Centro Empresarial<br>de Jaraguá do Sul</span>
                </div>
              </div>'''

if old_logo in s:
    s = s.replace(old_logo, new_logo, 1)

css_marker = '/* CEJAS_ORCAMENTO_LAYOUT_A4_START */'

css_block = r'''
    /* CEJAS_ORCAMENTO_LAYOUT_A4_START */
    .preview {
      overflow: auto !important;
      display: flex !important;
      justify-content: center !important;
      align-items: flex-start !important;
      padding: 26px 18px 48px !important;
      background: #e5e7eb !important;
    }

    .document.cejas-orcamento-folha {
      width: 210mm !important;
      min-height: 297mm !important;
      background: #ffffff !important;
      color: #1f2937 !important;
      padding: 30px 30px 26px !important;
      box-shadow: 0 22px 52px rgba(15,23,42,.22) !important;
      transform: scale(.82) !important;
      transform-origin: top center !important;
      display: flex !important;
      flex-direction: column !important;
      font-size: 11px !important;
      line-height: 1.35 !important;
      letter-spacing: 0 !important;
    }

    .doc-header {
      display: grid !important;
      grid-template-columns: 150px 1fr !important;
      align-items: start !important;
      gap: 20px !important;
      padding-bottom: 16px !important;
      border-bottom: 2px solid #1f2937 !important;
      margin-bottom: 14px !important;
    }

    .cejas-logo {
      min-height: 74px !important;
      display: flex !important;
      align-items: center !important;
      justify-content: flex-start !important;
    }

    .cejas-logo img {
      width: 78px !important;
      height: auto !important;
      object-fit: contain !important;
      filter: grayscale(1) contrast(.86) opacity(.82) !important;
      display: block !important;
    }

    .cejas-logo-fallback {
      display: none;
    }

    .cejas-logo-fallback strong,
    .cejas-logo strong {
      font-size: 30px !important;
      color: #6b7280 !important;
      letter-spacing: -2px !important;
      line-height: .9 !important;
    }

    .cejas-logo-fallback span,
    .cejas-logo span {
      display: block !important;
      color: #6b7280 !important;
      font-size: 8px !important;
      font-weight: 800 !important;
      line-height: 1.08 !important;
      margin-top: 3px !important;
    }

    .doc-company {
      text-align: right !important;
      color: #4b5563 !important;
      font-size: 10.2px !important;
      line-height: 1.35 !important;
    }

    .doc-company h1 {
      color: #111827 !important;
      font-size: 13px !important;
      line-height: 1.15 !important;
      text-transform: uppercase !important;
      letter-spacing: .01em !important;
      margin: 0 0 6px !important;
      font-weight: 900 !important;
    }

    .doc-company p {
      margin: 0 0 2px !important;
    }

    .doc-meta {
      display: flex !important;
      align-items: center !important;
      justify-content: space-between !important;
      font-size: 11px !important;
      color: #374151 !important;
      margin: 0 0 14px !important;
      font-weight: 500 !important;
    }

    .doc-meta strong {
      font-weight: 900 !important;
      color: #374151 !important;
    }

    .doc-title {
      background: #f0f1f3 !important;
      border: 1px solid #d7dbe1 !important;
      color: #1f2937 !important;
      padding: 10px 12px !important;
      text-align: center !important;
      text-transform: uppercase !important;
      letter-spacing: .36em !important;
      font-size: 13px !important;
      line-height: 1.1 !important;
      font-weight: 900 !important;
      margin: 0 0 16px !important;
    }

    .doc-fields {
      border: 1px solid #d7dbe1 !important;
      background: #ffffff !important;
      padding: 12px 13px !important;
      margin: 0 0 15px !important;
      line-height: 1.9 !important;
      font-size: 13px !important;
    }

    .doc-fields p {
      margin: 0 !important;
      display: grid !important;
      grid-template-columns: 92px 1fr !important;
      align-items: center !important;
      column-gap: 8px !important;
    }

    .doc-fields strong {
      display: block !important;
      width: auto !important;
      color: #111827 !important;
      font-weight: 900 !important;
    }

    .doc-fields span {
      display: inline-block !important;
      color: #111827 !important;
      font-weight: 500 !important;
      min-height: 18px !important;
    }

    .doc-period-title {
      border-left: 4px solid #64748b !important;
      padding-left: 8px !important;
      font-size: 11px !important;
      line-height: 1.25 !important;
      margin: 0 0 8px !important;
      text-transform: uppercase !important;
      color: #1f2937 !important;
      font-weight: 900 !important;
      letter-spacing: .03em !important;
    }

    .period {
      margin: 0 0 14px !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .period table {
      width: 100% !important;
      border-collapse: collapse !important;
      table-layout: fixed !important;
      font-size: 10.6px !important;
      margin: 0 0 12px !important;
    }

    .period th,
    .period td {
      border: 1px solid #d4d8df !important;
      padding: 6px 7px !important;
      text-align: left !important;
      vertical-align: top !important;
      color: #1f2937 !important;
      line-height: 1.28 !important;
    }

    .period th {
      background: #f0f1f3 !important;
      font-weight: 900 !important;
      color: #1f2937 !important;
    }

    .period th:nth-child(1),
    .period td:nth-child(1) {
      width: 32px !important;
      text-align: center !important;
    }

    .period th:nth-child(2),
    .period td:nth-child(2) {
      width: 29% !important;
    }

    .period th:nth-child(3),
    .period td:nth-child(3) {
      width: 40px !important;
      text-align: center !important;
    }

    .period th:nth-child(4),
    .period td:nth-child(4) {
      width: auto !important;
    }

    .period th:nth-child(5),
    .period td:nth-child(5),
    .period th:nth-child(6),
    .period td:nth-child(6) {
      width: 96px !important;
      text-align: right !important;
      white-space: nowrap !important;
    }

    .num {
      text-align: right !important;
      white-space: nowrap !important;
    }

    .subtotal td {
      background: #f8fafc !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
      font-style: italic !important;
    }

    .total-general {
      width: 270px !important;
      margin: 8px 0 22px auto !important;
      border: 2px solid #1f2937 !important;
      background: #fff !important;
      padding: 10px 14px !important;
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      gap: 14px !important;
      font-size: 12px !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
    }

    .total-general strong {
      font-size: 18px !important;
      color: #111827 !important;
      white-space: nowrap !important;
    }

    .infos-box {
      border: 1px solid #d7dbe1 !important;
      background: #ffffff !important;
      padding: 10px 12px !important;
      margin: 0 0 14px !important;
      font-size: 10.8px !important;
      line-height: 1.45 !important;
    }

    .conditions {
      margin-top: auto !important;
      border: 1px solid #d7dbe1 !important;
      background: #f8fafc !important;
      margin-bottom: 22px !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .conditions h4 {
      background: #e6e8ec !important;
      padding: 8px 12px !important;
      font-size: 9px !important;
      letter-spacing: .22em !important;
      color: #111827 !important;
      text-transform: uppercase !important;
      font-weight: 900 !important;
    }

    .conditions div {
      padding: 12px 12px 10px !important;
      font-size: 10px !important;
      line-height: 1.55 !important;
      color: #374151 !important;
    }

    .conditions p {
      margin: 0 0 6px !important;
    }

    .warning {
      font-weight: 900 !important;
      color: #111827 !important;
      border-top: 1px solid #e1e5eb !important;
      border-bottom: 1px solid #e1e5eb !important;
      padding: 7px 0 !important;
      margin: 7px 0 !important;
      text-transform: uppercase !important;
    }

    .signature {
      display: flex !important;
      justify-content: space-between !important;
      align-items: flex-end !important;
      gap: 18px !important;
      font-size: 10.8px !important;
      line-height: 1.45 !important;
      color: #374151 !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .signature p {
      margin: 0 !important;
    }

    .signature strong {
      display: block !important;
      font-size: 12px !important;
      color: #111827 !important;
      margin: 8px 0 2px !important;
      font-weight: 900 !important;
    }

    .system-mark {
      font-size: 8px !important;
      color: #9ca3af !important;
      text-transform: uppercase !important;
      white-space: nowrap !important;
      letter-spacing: .03em !important;
    }

    .cejas-pdf-render-wrapper .document,
    .document.cejas-exportando-pdf {
      transform: none !important;
      box-shadow: none !important;
      margin: 0 !important;
      width: 210mm !important;
      min-height: 297mm !important;
      padding: 30px 30px 26px !important;
    }

    @media screen and (max-width: 1180px) {
      .document.cejas-orcamento-folha {
        transform: scale(.72) !important;
      }
    }

    @media screen and (max-width: 760px) {
      .preview {
        justify-content: flex-start !important;
        padding: 16px 0 38px !important;
      }

      .document.cejas-orcamento-folha {
        transform: scale(.52) !important;
        transform-origin: top left !important;
      }
    }

    @media print {
      .sidebar,
      .topbar,
      .editor,
      .modal,
      .cejas-mobile-menu-btn,
      .cejas-mobile-drawer,
      .cejas-mobile-overlay {
        display: none !important;
      }

      html,
      body {
        width: 210mm !important;
        min-height: 297mm !important;
        background: #fff !important;
        margin: 0 !important;
        padding: 0 !important;
        overflow: visible !important;
      }

      body,
      .app,
      .main,
      .workspace,
      .preview {
        display: block !important;
        width: 210mm !important;
        height: auto !important;
        min-height: 297mm !important;
        overflow: visible !important;
        background: #fff !important;
        padding: 0 !important;
        margin: 0 !important;
      }

      .document.cejas-orcamento-folha {
        transform: none !important;
        width: 210mm !important;
        min-height: 297mm !important;
        box-shadow: none !important;
        margin: 0 !important;
        padding: 30px 30px 26px !important;
        page-break-after: always !important;
      }

      @page {
        size: A4;
        margin: 0;
      }
    }
    /* CEJAS_ORCAMENTO_LAYOUT_A4_END */
'''

if css_marker not in s:
    if '</style>' not in s:
        raise SystemExit('❌ Não encontrei </style> no orcamentos.html.')
    s = s.replace('</style>', css_block + '\n  </style>', 1)

s = s.replace('${rows || `<tr><td colspan="6" style="text-align:center;color:#94a3b8;padding:14px;">Nenhum item adicionado neste período.</td></tr>`}', '${rows}')

old_total = '''  if (docPeriods) {
    docPeriods.innerHTML = `
      ${periodsHTML}
      <div class="total-general">
        <span>Total Geral:</span>
        <strong>${money(totalGeral)}</strong>
      </div>
    `;
  }'''

new_total = '''  if (docPeriods) {
    const totalHTML = totalGeral > 0
      ? `
      <div class="total-general">
        <span>Total Geral:</span>
        <strong>${money(totalGeral)}</strong>
      </div>`
      : "";

    docPeriods.innerHTML = `${periodsHTML}${totalHTML}`;
  }'''

if old_total in s:
    s = s.replace(old_total, new_total, 1)

start = s.find('  async function gerarPdfBlob() {')
end = s.find('  async function gerarPdfSalvarServidor()', start)

if start != -1 and end != -1:
    pdf_fn = r'''  async function gerarPdfBlob() {
    await garantirBibliotecasPDF();

    const folhaOriginal = encontrarFolhaDoOrcamento();
    const { jsPDF } = window.jspdf;

    const wrapper = document.createElement("div");
    wrapper.className = "cejas-pdf-render-wrapper";
    wrapper.style.position = "fixed";
    wrapper.style.left = "-100000px";
    wrapper.style.top = "0";
    wrapper.style.width = "210mm";
    wrapper.style.background = "#ffffff";
    wrapper.style.padding = "0";
    wrapper.style.margin = "0";
    wrapper.style.zIndex = "-1";
    wrapper.style.pointerEvents = "none";

    const clone = folhaOriginal.cloneNode(true);
    clone.classList.add("cejas-exportando-pdf");
    clone.style.transform = "none";
    clone.style.margin = "0";
    clone.style.boxShadow = "none";
    clone.style.background = "#ffffff";
    clone.style.width = "210mm";
    clone.style.minHeight = "297mm";

    wrapper.appendChild(clone);
    document.body.appendChild(wrapper);

    await new Promise((resolve) => setTimeout(resolve, 120));

    const canvas = await window.html2canvas(clone, {
      scale: 3,
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

    const imgData = canvas.toDataURL("image/jpeg", 0.98);
    const pdf = new jsPDF("p", "mm", "a4");

    const pageWidth = 210;
    const pageHeight = 297;
    const imgWidth = pageWidth;
    const imgHeight = (canvas.height * imgWidth) / canvas.width;

    let heightLeft = imgHeight;
    let position = 0;

    pdf.addImage(imgData, "JPEG", 0, position, imgWidth, imgHeight);
    heightLeft -= pageHeight;

    while (heightLeft > 2) {
      position = heightLeft - imgHeight;
      pdf.addPage();
      pdf.addImage(imgData, "JPEG", 0, position, imgWidth, imgHeight);
      heightLeft -= pageHeight;
    }

    return pdf.output("blob");
  }

'''
    s = s[:start] + pdf_fn + s[end:]

s = s.replace('🖨 Imprimir / Gerar PDF', '🖨 Imprimir / PDF A4')

p.write_text(s)
PY

node <<'NODE'
const fs = require('fs');
const html = fs.readFileSync('orcamentos.html', 'utf8');
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync('.cejas-local-backups/check-orcamento-layout', {
  recursive: true
});

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-orcamento-layout/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-orcamento-layout/script-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-orcamento-layout

echo ""
echo "✅ Layout da folha de orçamento ajustado para A4 no padrão do modelo enviado."
echo ""
echo "Agora rode: npm run dev"
echo "Abra: http://localhost:5500/orcamentos.html"
echo "Depois clique em: Imprimir / PDF A4 ou Salvar PDF no Servidor"
