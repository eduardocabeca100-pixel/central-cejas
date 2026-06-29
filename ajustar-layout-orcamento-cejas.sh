#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "orcamentos.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde fica orcamentos.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/layout-orcamento-cejas-$STAMP"
mkdir -p "$BACKUP_DIR"
cp orcamentos.html "$BACKUP_DIR/orcamentos.html"

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("orcamentos.html")
s = p.read_text()

# Remove versões antigas deste ajuste.
s = re.sub(
    r"\s*/\* CEJAS_LAYOUT_ORCAMENTO_FINAL_START \*/[\s\S]*?/\* CEJAS_LAYOUT_ORCAMENTO_FINAL_END \*/",
    "",
    s
)

s = re.sub(
    r"\s*<script>\s*// CEJAS_LAYOUT_ORCAMENTO_FINAL_JS_START[\s\S]*?// CEJAS_LAYOUT_ORCAMENTO_FINAL_JS_END\s*</script>",
    "",
    s
)

css = r'''
    /* CEJAS_LAYOUT_ORCAMENTO_FINAL_START */

    /*
      Cabeçalho correto:
      - Logo pequena à esquerda
      - Dados da empresa à direita
      - Sem CEJAS duplicado abaixo da logo
      - Título da direita em uma linha quando houver espaço
    */

    .document .doc-header,
    .cejas-orcamento-folha .doc-header,
    .cejas-pdf-real-doc .doc-header,
    .cejas-pdf-clean-document .doc-header,
    .cejas-pdf-a4-page .doc-header,
    .cejas-pdf-export-root .doc-header,
    .cejas-pdf-export-wrapper .doc-header {
      display: grid !important;
      grid-template-columns: 34mm 1fr !important;
      align-items: start !important;
      gap: 12mm !important;
      padding-bottom: 8mm !important;
      margin-bottom: 5mm !important;
      border-bottom: 1.5px solid #111827 !important;
    }

    .document .cejas-logo,
    .document .doc-logo,
    .document .logo-area,
    .cejas-orcamento-folha .cejas-logo,
    .cejas-orcamento-folha .doc-logo,
    .cejas-orcamento-folha .logo-area,
    .cejas-pdf-real-doc .cejas-logo,
    .cejas-pdf-real-doc .doc-logo,
    .cejas-pdf-real-doc .logo-area,
    .cejas-pdf-clean-document .cejas-logo,
    .cejas-pdf-clean-document .doc-logo,
    .cejas-pdf-clean-document .logo-area,
    .cejas-pdf-a4-page .cejas-logo,
    .cejas-pdf-a4-page .doc-logo,
    .cejas-pdf-a4-page .logo-area,
    .cejas-pdf-export-root .cejas-logo,
    .cejas-pdf-export-root .doc-logo,
    .cejas-pdf-export-root .logo-area {
      width: 28mm !important;
      max-width: 28mm !important;
      min-width: 28mm !important;
      display: block !important;
      overflow: hidden !important;
      text-align: left !important;
    }

    .document .cejas-logo img,
    .document .doc-logo img,
    .document .logo-area img,
    .cejas-orcamento-folha .cejas-logo img,
    .cejas-orcamento-folha .doc-logo img,
    .cejas-orcamento-folha .logo-area img,
    .cejas-pdf-real-doc .cejas-logo img,
    .cejas-pdf-real-doc .doc-logo img,
    .cejas-pdf-real-doc .logo-area img,
    .cejas-pdf-clean-document .cejas-logo img,
    .cejas-pdf-clean-document .doc-logo img,
    .cejas-pdf-clean-document .logo-area img,
    .cejas-pdf-a4-page .cejas-logo img,
    .cejas-pdf-a4-page .doc-logo img,
    .cejas-pdf-a4-page .logo-area img,
    .cejas-pdf-export-root .cejas-logo img,
    .cejas-pdf-export-root .doc-logo img,
    .cejas-pdf-export-root .logo-area img {
      width: 24mm !important;
      height: 24mm !important;
      max-width: 24mm !important;
      max-height: 24mm !important;
      object-fit: contain !important;
      display: block !important;
      margin: 0 !important;
      padding: 0 !important;
    }

    /*
      Esconde textos duplicados que alguns layouts colocam abaixo da logo.
      Mantém apenas a imagem da logo no cabeçalho.
    */
    .document .cejas-logo > :not(img):not(svg),
    .document .doc-logo > :not(img):not(svg),
    .document .logo-area > :not(img):not(svg),
    .cejas-orcamento-folha .cejas-logo > :not(img):not(svg),
    .cejas-orcamento-folha .doc-logo > :not(img):not(svg),
    .cejas-orcamento-folha .logo-area > :not(img):not(svg),
    .cejas-pdf-real-doc .cejas-logo > :not(img):not(svg),
    .cejas-pdf-real-doc .doc-logo > :not(img):not(svg),
    .cejas-pdf-real-doc .logo-area > :not(img):not(svg),
    .cejas-pdf-clean-document .cejas-logo > :not(img):not(svg),
    .cejas-pdf-clean-document .doc-logo > :not(img):not(svg),
    .cejas-pdf-clean-document .logo-area > :not(img):not(svg) {
      display: none !important;
      visibility: hidden !important;
    }

    .document .doc-company,
    .cejas-orcamento-folha .doc-company,
    .cejas-pdf-real-doc .doc-company,
    .cejas-pdf-clean-document .doc-company,
    .cejas-pdf-a4-page .doc-company,
    .cejas-pdf-export-root .doc-company,
    .cejas-pdf-export-wrapper .doc-company {
      text-align: right !important;
      color: #374151 !important;
      font-size: 8.7px !important;
      line-height: 1.28 !important;
      max-width: none !important;
      width: auto !important;
    }

    .document .doc-company h1,
    .cejas-orcamento-folha .doc-company h1,
    .cejas-pdf-real-doc .doc-company h1,
    .cejas-pdf-clean-document .doc-company h1,
    .cejas-pdf-a4-page .doc-company h1,
    .cejas-pdf-export-root .doc-company h1,
    .cejas-pdf-export-wrapper .doc-company h1 {
      color: #111827 !important;
      font-size: 11px !important;
      line-height: 1.12 !important;
      margin: 0 0 4px !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
      letter-spacing: 0 !important;
      white-space: nowrap !important;
    }

    .document .doc-meta,
    .cejas-orcamento-folha .doc-meta,
    .cejas-pdf-real-doc .doc-meta,
    .cejas-pdf-clean-document .doc-meta,
    .cejas-pdf-a4-page .doc-meta,
    .cejas-pdf-export-root .doc-meta,
    .cejas-pdf-export-wrapper .doc-meta {
      margin-top: 0 !important;
      margin-bottom: 4mm !important;
      font-size: 9px !important;
    }

    .document .doc-title,
    .cejas-orcamento-folha .doc-title,
    .cejas-pdf-real-doc .doc-title,
    .cejas-pdf-clean-document .doc-title,
    .cejas-pdf-a4-page .doc-title,
    .cejas-pdf-export-root .doc-title,
    .cejas-pdf-export-wrapper .doc-title {
      font-size: 10px !important;
      letter-spacing: .30em !important;
      padding: 2.8mm 4mm !important;
      margin-bottom: 4.5mm !important;
    }

    /*
      Remove qualquer imagem solta grande dentro do orçamento, quando não estiver
      dentro do bloco oficial do cabeçalho.
    */
    .document > img:first-child,
    .cejas-orcamento-folha > img:first-child,
    .cejas-pdf-real-doc > img:first-child,
    .cejas-pdf-clean-document > img:first-child {
      max-width: 24mm !important;
      max-height: 24mm !important;
      object-fit: contain !important;
    }

    @media screen {
      .document .doc-header,
      .cejas-orcamento-folha .doc-header {
        grid-template-columns: 95px 1fr !important;
        gap: 30px !important;
      }

      .document .cejas-logo,
      .document .doc-logo,
      .document .logo-area,
      .cejas-orcamento-folha .cejas-logo,
      .cejas-orcamento-folha .doc-logo,
      .cejas-orcamento-folha .logo-area {
        width: 85px !important;
        max-width: 85px !important;
        min-width: 85px !important;
      }

      .document .cejas-logo img,
      .document .doc-logo img,
      .document .logo-area img,
      .cejas-orcamento-folha .cejas-logo img,
      .cejas-orcamento-folha .doc-logo img,
      .cejas-orcamento-folha .logo-area img {
        width: 78px !important;
        height: 78px !important;
        max-width: 78px !important;
        max-height: 78px !important;
      }
    }

    /* CEJAS_LAYOUT_ORCAMENTO_FINAL_END */
'''

if "</style>" not in s:
    raise SystemExit("❌ Não encontrei </style> no orcamentos.html.")

s = s.replace("</style>", css + "\n  </style>", 1)

js = r'''
<script>
// CEJAS_LAYOUT_ORCAMENTO_FINAL_JS_START
(function () {
  if (window.__CEJAS_LAYOUT_ORCAMENTO_FINAL__) return;
  window.__CEJAS_LAYOUT_ORCAMENTO_FINAL__ = true;

  function normalizarTexto(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toUpperCase();
  }

  function ajustarLogoOrcamento(root) {
    const base = root || document;

    const documentos = [
      ...base.querySelectorAll(".document, .cejas-orcamento-folha, .cejas-pdf-real-doc, .cejas-pdf-clean-document, .cejas-pdf-a4-page")
    ];

    documentos.forEach((doc) => {
      const header = doc.querySelector(".doc-header");
      if (!header) return;

      let logoBox =
        header.querySelector(".cejas-logo") ||
        header.querySelector(".doc-logo") ||
        header.querySelector(".logo-area");

      if (!logoBox) {
        const img = header.querySelector("img");
        if (img) {
          logoBox = img.parentElement;
          logoBox.classList.add("cejas-logo");
        }
      }

      if (!logoBox) return;

      const imgs = [...logoBox.querySelectorAll("img")];

      imgs.forEach((img) => {
        img.removeAttribute("width");
        img.removeAttribute("height");
        img.style.width = "24mm";
        img.style.height = "24mm";
        img.style.maxWidth = "24mm";
        img.style.maxHeight = "24mm";
        img.style.objectFit = "contain";
      });

      [...logoBox.children].forEach((child) => {
        if (child.tagName === "IMG" || child.tagName === "SVG") return;

        const texto = normalizarTexto(child.textContent);

        if (
          texto.includes("CEJAS") ||
          texto.includes("CENTRO EMPRESARIAL") ||
          child.className
        ) {
          child.style.display = "none";
          child.style.visibility = "hidden";
        }
      });
    });
  }

  const originalGerarPdfBlob = window.gerarPdfBlob;

  if (typeof originalGerarPdfBlob === "function" && !window.__CEJAS_LAYOUT_WRAP_PDF__) {
    window.__CEJAS_LAYOUT_WRAP_PDF__ = true;

    window.gerarPdfBlob = async function gerarPdfBlobComLayoutCorrigido() {
      ajustarLogoOrcamento(document);
      await new Promise((resolve) => setTimeout(resolve, 120));
      return originalGerarPdfBlob.apply(this, arguments);
    };
  }

  document.addEventListener("DOMContentLoaded", () => {
    ajustarLogoOrcamento(document);
    setTimeout(() => ajustarLogoOrcamento(document), 500);
    setTimeout(() => ajustarLogoOrcamento(document), 1500);
  });

  document.addEventListener("input", () => {
    setTimeout(() => ajustarLogoOrcamento(document), 80);
  });

  window.ajustarLogoOrcamentoCejas = ajustarLogoOrcamento;
})();
// CEJAS_LAYOUT_ORCAMENTO_FINAL_JS_END
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

fs.mkdirSync(".cejas-local-backups/check-layout-orcamento", { recursive: true });

scripts.forEach((code, index) => {
  fs.writeFileSync(`.cejas-local-backups/check-layout-orcamento/script-${index + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-layout-orcamento/script-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-layout-orcamento

echo ""
echo "✅ Layout do orçamento ajustado."
echo ""
echo "O que mudou:"
echo "- Logo limitada a tamanho pequeno."
echo "- CEJAS duplicado abaixo da logo escondido."
echo "- Cabeçalho voltou para logo esquerda + dados da empresa à direita."
echo "- Título da direita não deve mais quebrar daquele jeito gigante."
echo ""
echo "Agora rode:"
echo "npm run dev"
echo ""
echo "Teste:"
echo "http://localhost:5500/orcamentos.html"
