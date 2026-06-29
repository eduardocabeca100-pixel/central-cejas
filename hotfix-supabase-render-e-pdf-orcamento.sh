#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/hotfix-render-supabase-pdf-$STAMP"
mkdir -p "$BACKUP_DIR" scripts

cp server.js package.json orcamentos.html "$BACKUP_DIR/" 2>/dev/null || true
[ -d lib ] && cp -R lib "$BACKUP_DIR/lib" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

echo "🔧 Corrigindo compatibilidade de variáveis Supabase..."

python3 <<'PY'
from pathlib import Path

p = Path("lib/supabase.js")

if not p.exists():
    raise SystemExit("❌ Não encontrei lib/supabase.js.")

s = p.read_text()

alias_block = r'''
// CEJAS_SUPABASE_ENV_COMPAT_START
process.env.SUPABASE_URL =
  process.env.SUPABASE_URL ||
  process.env.NEXT_PUBLIC_SUPABASE_URL ||
  process.env.PUBLIC_SUPABASE_URL ||
  "";

process.env.SUPABASE_SERVICE_ROLE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_SERVICE_KEY ||
  process.env.SUPABASE_SERVICE_ROLE ||
  "";

process.env.SUPABASE_STORAGE_BUCKET =
  process.env.SUPABASE_STORAGE_BUCKET ||
  process.env.SUPABASE_BUCKET ||
  "servidor-cejas";
// CEJAS_SUPABASE_ENV_COMPAT_END

'''

if "CEJAS_SUPABASE_ENV_COMPAT_START" not in s:
    if 'require("dotenv").config();' in s:
        s = s.replace('require("dotenv").config();', 'require("dotenv").config();\n' + alias_block, 1)
    elif "require('dotenv').config();" in s:
        s = s.replace("require('dotenv').config();", "require('dotenv').config();\n" + alias_block, 1)
    else:
        s = alias_block + s

p.write_text(s)
PY

cat > scripts/check-env-render.js <<'EOF'
require("dotenv").config();

const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRole = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE;
const bucket = process.env.SUPABASE_STORAGE_BUCKET || process.env.SUPABASE_BUCKET || "servidor-cejas";

console.log("");
console.log("🔎 Check de ambiente Supabase/Render");
console.log("");

console.log("SUPABASE_URL / NEXT_PUBLIC_SUPABASE_URL:", url ? "✅ configurado" : "❌ faltando");
console.log("SUPABASE_SERVICE_ROLE_KEY:", serviceRole ? "✅ configurado" : "❌ faltando");
console.log("SUPABASE_STORAGE_BUCKET:", bucket ? `✅ ${bucket}` : "❌ faltando");

console.log("");

if (!url || !serviceRole || !bucket) {
  console.error("❌ Ambiente incompleto. Corrija no Render > Environment.");
  process.exit(1);
}

console.log("✅ Ambiente mínimo configurado.");
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["env:check"] = "node scripts/check-env-render.js"
p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

echo "🔧 Corrigindo PDF do orçamento..."

python3 <<'PY'
from pathlib import Path
import re

p = Path("orcamentos.html")

if not p.exists():
    raise SystemExit("❌ Não encontrei orcamentos.html.")

s = p.read_text()

# Remove patches antigos de PDF que podem estar brigando entre si.
s = re.sub(
    r"\s*/\* CEJAS_ORCAMENTO_[A-Z0-9_]*START \*/[\s\S]*?/\* CEJAS_ORCAMENTO_[A-Z0-9_]*END \*/",
    "",
    s
)

s = re.sub(
    r"\s*<script>\s*// CEJAS_ORCAMENTO_[A-Z0-9_]*JS_START[\s\S]*?// CEJAS_ORCAMENTO_[A-Z0-9_]*JS_END\s*</script>",
    "",
    s
)

css = r'''
    /* CEJAS_ORCAMENTO_PDF_LIMPO_START */
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

    .cejas-pdf-clean-root {
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

    .cejas-pdf-clean-root .document,
    .cejas-pdf-clean-root .cejas-orcamento-folha,
    .cejas-pdf-clean-document {
      width: 210mm !important;
      height: auto !important;
      min-height: 297mm !important;
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

    .cejas-pdf-clean-document * {
      box-sizing: border-box !important;
    }

    .cejas-pdf-clean-document .topbar,
    .cejas-pdf-clean-document .toolbar,
    .cejas-pdf-clean-document .actions,
    .cejas-pdf-clean-document .editor,
    .cejas-pdf-clean-document .sidebar,
    .cejas-pdf-clean-document .modal,
    .cejas-pdf-clean-document button,
    .cejas-pdf-clean-document .btn,
    .cejas-pdf-clean-document [data-no-pdf] {
      display: none !important;
      visibility: hidden !important;
    }

    .cejas-pdf-clean-document .doc-header {
      display: grid !important;
      grid-template-columns: 35mm 1fr !important;
      gap: 8mm !important;
      align-items: start !important;
      padding-bottom: 8mm !important;
      border-bottom: 1.4px solid #111827 !important;
      margin-bottom: 4mm !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document .cejas-logo img {
      width: 24mm !important;
      height: auto !important;
      display: block !important;
    }

    .cejas-pdf-clean-document .doc-company {
      text-align: right !important;
      font-size: 8.3px !important;
      line-height: 1.22 !important;
      color: #374151 !important;
    }

    .cejas-pdf-clean-document .doc-company h1 {
      font-size: 10.8px !important;
      line-height: 1.1 !important;
      margin: 0 0 4px !important;
      color: #111827 !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
    }

    .cejas-pdf-clean-document .doc-meta {
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      gap: 8px !important;
      margin: 0 0 4mm !important;
      font-size: 9px !important;
      color: #374151 !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document .doc-title {
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
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document .doc-fields {
      border: 1px solid #d1d5db !important;
      padding: 4mm !important;
      margin: 0 0 4.5mm !important;
      font-size: 9.3px !important;
      line-height: 1.65 !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document .doc-fields p {
      display: grid !important;
      grid-template-columns: 25mm 1fr !important;
      gap: 4mm !important;
      margin: 0 !important;
    }

    .cejas-pdf-clean-document .doc-period-title {
      border-left: 4px solid #64748b !important;
      padding-left: 8px !important;
      margin: 0 0 2.7mm !important;
      font-size: 9px !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
      color: #111827 !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document .period {
      margin: 0 0 4mm !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document table {
      width: 100% !important;
      border-collapse: collapse !important;
      table-layout: fixed !important;
      font-size: 8px !important;
      margin: 0 !important;
    }

    .cejas-pdf-clean-document th,
    .cejas-pdf-clean-document td {
      border: 1px solid #d1d5db !important;
      padding: 3.5px 4px !important;
      color: #111827 !important;
      line-height: 1.16 !important;
      vertical-align: top !important;
      overflow-wrap: break-word !important;
      word-break: normal !important;
    }

    .cejas-pdf-clean-document th {
      background: #f3f4f6 !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-clean-document tr {
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document th:nth-child(1),
    .cejas-pdf-clean-document td:nth-child(1) {
      width: 8mm !important;
      text-align: center !important;
    }

    .cejas-pdf-clean-document th:nth-child(2),
    .cejas-pdf-clean-document td:nth-child(2) {
      width: 32mm !important;
    }

    .cejas-pdf-clean-document th:nth-child(3),
    .cejas-pdf-clean-document td:nth-child(3) {
      width: 10mm !important;
      text-align: center !important;
    }

    .cejas-pdf-clean-document th:nth-child(5),
    .cejas-pdf-clean-document td:nth-child(5),
    .cejas-pdf-clean-document th:nth-child(6),
    .cejas-pdf-clean-document td:nth-child(6) {
      width: 23mm !important;
      text-align: right !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-clean-document .subtotal td {
      background: #f8fafc !important;
      font-weight: 900 !important;
      font-style: italic !important;
    }

    .cejas-pdf-clean-document .total-general {
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
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document .total-general strong {
      font-size: 13px !important;
      color: #111827 !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-clean-document .conditions {
      display: block !important;
      visibility: visible !important;
      margin-top: 8mm !important;
      margin-bottom: 5mm !important;
      border: 1px solid #d1d5db !important;
      background: #f8fafc !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document .conditions h4 {
      background: #e5e7eb !important;
      padding: 2.7mm 4mm !important;
      font-size: 7.5px !important;
      letter-spacing: .18em !important;
      color: #111827 !important;
      text-transform: uppercase !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-clean-document .conditions div {
      padding: 3.5mm 4mm !important;
      font-size: 8.2px !important;
      line-height: 1.38 !important;
      color: #374151 !important;
    }

    .cejas-pdf-clean-document .signature {
      display: flex !important;
      justify-content: space-between !important;
      align-items: flex-end !important;
      gap: 18px !important;
      font-size: 8.6px !important;
      line-height: 1.28 !important;
      color: #374151 !important;
      margin-top: 5mm !important;
      page-break-inside: avoid !important;
      break-inside: avoid !important;
    }

    .cejas-pdf-clean-document .signature strong {
      display: block !important;
      color: #111827 !important;
      font-size: 9.5px !important;
      margin: 4px 0 1px !important;
    }

    .cejas-pdf-clean-document .system-mark {
      font-size: 6.7px !important;
      color: #9ca3af !important;
      text-transform: uppercase !important;
      white-space: nowrap !important;
    }
    /* CEJAS_ORCAMENTO_PDF_LIMPO_END */
'''

s = s.replace("</style>", css + "\n  </style>", 1)

def replace_async_function(source, name, replacement):
    marker = f"async function {name}("
    start = source.find(marker)

    if start == -1:
        return source, False

    brace = source.find("{", start)
    depth = 0
    i = brace

    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[:start] + replacement + source[i + 1:], True
        i += 1

    return source, False

new_fn = r'''async function gerarPdfBlob() {
    async function carregarScriptCejas(src) {
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

    if (!window.html2canvas) {
      await carregarScriptCejas("https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js");
    }

    if (!window.jspdf || !window.jspdf.jsPDF) {
      await carregarScriptCejas("https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js");
    }

    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }

    const candidatos = [
      ".cejas-orcamento-folha",
      ".document",
      "#orcamentoDocumento",
      "#document",
      "#orcamentoPreview",
      "[data-orcamento-documento]"
    ];

    let folhaOriginal = null;

    for (const seletor of candidatos) {
      const lista = [...document.querySelectorAll(seletor)];

      folhaOriginal = lista.find((el) => {
        const texto = String(el.innerText || "").toUpperCase();

        return texto.includes("DOCUMENTO AUXILIAR DE VENDA") ||
          texto.includes("ORÇAMENTO LOCAÇÃO") ||
          texto.includes("ORCAMENTO LOCACAO") ||
          texto.includes("SOLICITANTE:");
      });

      if (folhaOriginal) break;
    }

    if (!folhaOriginal) {
      throw new Error("Não encontrei a folha do orçamento.");
    }

    const root = document.createElement("div");
    root.className = "cejas-pdf-clean-root";

    const clone = folhaOriginal.cloneNode(true);
    clone.classList.add("cejas-pdf-clean-document");

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

    clone.style.width = "210mm";
    clone.style.height = "auto";
    clone.style.minHeight = "297mm";
    clone.style.maxHeight = "none";
    clone.style.overflow = "visible";
    clone.style.transform = "none";
    clone.style.margin = "0";
    clone.style.boxShadow = "none";
    clone.style.background = "#ffffff";

    root.appendChild(clone);
    document.body.appendChild(root);

    await new Promise((resolve) => setTimeout(resolve, 300));

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
      scale: 2.25,
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
  }'''

s, ok = replace_async_function(s, "gerarPdfBlob", new_fn)

if not ok:
    s = s.replace("</body>", f"<script>\n{new_fn}\nwindow.gerarPdfBlob = gerarPdfBlob;\n</script>\n</body>", 1)

# Garante que cliques de PDF usem a função nova.
if "CEJAS_ORCAMENTO_CLICK_PDF_LIMPO" not in s:
    click_js = r'''
<script>
// CEJAS_ORCAMENTO_CLICK_PDF_LIMPO
(function () {
  async function baixarPdfCejas() {
    const blob = await window.gerarPdfBlob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");

    a.href = url;
    a.download = `orcamento-${new Date().toISOString().slice(0, 10)}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();

    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

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
      baixarPdfCejas().catch((error) => {
        alert("Erro ao gerar PDF: " + error.message);
      });
    }
  }, true);
})();
</script>
'''
    s = s.replace("</body>", click_js + "\n</body>", 1)

p.write_text(s)
PY

node --check lib/supabase.js
node --check scripts/check-env-render.js
[ -f orcamentos.html ] && node <<'NODE'
const fs = require("fs");
const html = fs.readFileSync("orcamentos.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-pdf-limpo", { recursive: true });
scripts.forEach((code, i) => fs.writeFileSync(`.cejas-local-backups/check-pdf-limpo/script-${i + 1}.js`, code));
NODE

for f in .cejas-local-backups/check-pdf-limpo/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-pdf-limpo

echo ""
echo "✅ Hotfix aplicado."
echo ""
echo "Agora rode:"
echo "npm run env:check"
echo "npm run dev"
