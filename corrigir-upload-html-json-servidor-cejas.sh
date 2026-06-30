#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "servidor.html" ]; then
  echo "❌ Rode dentro da raiz do projeto, onde ficam server.js e servidor.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/upload-html-json-servidor-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js servidor.html package.json "$BACKUP_DIR/" 2>/dev/null || true
[ -f lib/servidor-supabase-definitivo.js ] && cp lib/servidor-supabase-definitivo.js "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

# ------------------------------------------------------------------
# 1) Ajusta servidor: resposta JSON para erro de upload/multer.
# ------------------------------------------------------------------
p = Path("server.js")
s = p.read_text()

middleware = r'''
// CEJAS_UPLOAD_JSON_ERROR_HANDLER_START
app.use((error, req, res, next) => {
  if (req.path && req.path.startsWith("/api/servidor/")) {
    return res.status(error.status || error.statusCode || 500).json({
      ok: false,
      message: "Erro no upload/servidor: " + (error.message || "erro desconhecido")
    });
  }

  next(error);
});
// CEJAS_UPLOAD_JSON_ERROR_HANDLER_END
'''

if "CEJAS_UPLOAD_JSON_ERROR_HANDLER_START" not in s:
    # Precisa ficar antes do app.listen, como handler de erro.
    match = re.search(r'\n(app\.listen\s*\(|server\.listen\s*\()', s)
    if match:
        s = s[:match.start()] + "\n" + middleware + "\n" + s[match.start():]
    else:
        s += "\n" + middleware + "\n"

# Rota rápida para confirmar se API do servidor está viva.
ping = r'''
// CEJAS_SERVIDOR_API_PING_START
app.get("/api/servidor/ping", (_req, res) => {
  res.set("Cache-Control", "no-store");
  res.json({
    ok: true,
    message: "API do servidor ativa",
    at: new Date().toISOString()
  });
});
// CEJAS_SERVIDOR_API_PING_END
'''

if "CEJAS_SERVIDOR_API_PING_START" not in s:
    marker = "const app = express();"
    if marker in s:
        s = s.replace(marker, marker + "\n" + ping, 1)
    else:
        s += "\n" + ping + "\n"

p.write_text(s)

# ------------------------------------------------------------------
# 2) Ajusta servidor.html: upload em lotes menores e parser seguro.
# ------------------------------------------------------------------
p = Path("servidor.html")
s = p.read_text()

# Remove patches antigos de upload em lote para evitar conflito.
s = re.sub(
    r'\s*<script>\s*// CEJAS_UPLOAD_LOTES_SERVIDOR_START[\s\S]*?// CEJAS_UPLOAD_LOTES_SERVIDOR_END\s*</script>',
    '',
    s
)

s = re.sub(
    r'\s*<script>\s*// CEJAS_UPLOAD_SEGURO_SERVIDOR_START[\s\S]*?// CEJAS_UPLOAD_SEGURO_SERVIDOR_END\s*</script>',
    '',
    s
)

js = r'''
<script>
// CEJAS_UPLOAD_SEGURO_SERVIDOR_START
(function () {
  if (window.__CEJAS_UPLOAD_SEGURO_SERVIDOR__) return;
  window.__CEJAS_UPLOAD_SEGURO_SERVIDOR__ = true;

  const MAX_ARQUIVOS_POR_LOTE = 5;
  const MAX_MB_POR_LOTE = 25;

  function obterArquivosSelecionados() {
    const inputs = [...document.querySelectorAll('input[type="file"]')];
    const arquivos = [];

    for (const input of inputs) {
      for (const file of Array.from(input.files || [])) {
        arquivos.push(file);
      }
    }

    return arquivos;
  }

  function obterAnoPadrao() {
    const el = document.querySelector("#anoPadrao, [name='anoPadrao'], select[name='anoPadrao']");
    return el && el.value ? el.value : "2026";
  }

  function atualizarStatusUpload(texto) {
    const candidatos = [...document.querySelectorAll("div,p,span,strong")];

    const status = candidatos.find((el) => {
      const t = String(el.textContent || "").toLowerCase();
      return t.includes("enviando") || t.includes("organizando") || t.includes("arquivo");
    });

    if (status) status.textContent = texto;
  }

  function montarLotes(files) {
    const lotes = [];
    let lote = [];
    let loteBytes = 0;
    const maxBytes = MAX_MB_POR_LOTE * 1024 * 1024;

    for (const file of files) {
      const grandeSozinho = file.size > maxBytes;

      if (
        lote.length &&
        (
          lote.length >= MAX_ARQUIVOS_POR_LOTE ||
          loteBytes + file.size > maxBytes ||
          grandeSozinho
        )
      ) {
        lotes.push(lote);
        lote = [];
        loteBytes = 0;
      }

      lote.push(file);
      loteBytes += file.size || 0;

      if (grandeSozinho) {
        lotes.push(lote);
        lote = [];
        loteBytes = 0;
      }
    }

    if (lote.length) lotes.push(lote);

    return lotes;
  }

  async function respostaJsonSegura(response) {
    const text = await response.text();

    try {
      return JSON.parse(text);
    } catch {
      const html = text.trim().startsWith("<!DOCTYPE") || text.trim().startsWith("<html");

      if (html) {
        throw new Error(
          "O servidor retornou HTML em vez de JSON. Isso geralmente é limite de upload, timeout do Render ou rota antiga em cache. Tente menos arquivos por vez ou faça Clear build cache & deploy."
        );
      }

      throw new Error(text.slice(0, 500) || `Resposta inválida HTTP ${response.status}`);
    }
  }

  async function enviarLoteServidor(files, loteIndex, totalLotes) {
    const form = new FormData();

    files.forEach((file) => {
      const relative = file.webkitRelativePath || file.name;
      form.append("arquivos", file, relative);
      form.append("paths", relative);
    });

    form.append("anoPadrao", obterAnoPadrao());

    atualizarStatusUpload(`Enviando lote ${loteIndex + 1}/${totalLotes} (${files.length} arquivo(s))...`);

    const response = await fetch(`/api/servidor/upload-inteligente?_ts=${Date.now()}`, {
      method: "POST",
      body: form,
      cache: "no-store"
    });

    const data = await respostaJsonSegura(response);

    if (!response.ok || data.ok === false) {
      throw new Error(data.message || `Erro HTTP ${response.status}`);
    }

    return data;
  }

  async function uploadSeguroCejas(event) {
    const botao = event.target.closest("button, a");
    if (!botao) return;

    const texto = String(botao.textContent || "").toLowerCase();
    const ehEnviar =
      texto.includes("enviar para o servidor") ||
      texto.includes("subir") ||
      texto.includes("upload");

    if (!ehEnviar) return;

    const arquivos = obterArquivosSelecionados();

    if (!arquivos.length) return;

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    const lotes = montarLotes(arquivos);
    let salvos = 0;
    let falhas = [];

    botao.disabled = true;

    try {
      for (let i = 0; i < lotes.length; i++) {
        const result = await enviarLoteServidor(lotes[i], i, lotes.length);

        salvos += Number(result.saved || 0);

        if (Array.isArray(result.falhas)) {
          falhas.push(...result.falhas);
        }
      }

      atualizarStatusUpload(`Upload finalizado: ${salvos} arquivo(s) enviado(s). ${falhas.length} falha(s).`);

      if (falhas.length) {
        console.warn("Falhas no upload CEJAS:", falhas);
        alert(`${salvos} arquivo(s) enviados. ${falhas.length} falha(s). Veja o console para detalhes.`);
      } else {
        alert(`${salvos} arquivo(s) enviados com sucesso.`);
      }

      setTimeout(() => {
        if (typeof window.carregarServidor === "function") {
          window.carregarServidor();
        } else {
          location.reload();
        }
      }, 800);
    } catch (error) {
      console.error("Erro upload CEJAS:", error);
      alert("Erro ao enviar: " + error.message);
    } finally {
      botao.disabled = false;
    }
  }

  document.addEventListener("click", uploadSeguroCejas, true);
})();
// CEJAS_UPLOAD_SEGURO_SERVIDOR_END
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
const html = fs.readFileSync("servidor.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-upload-html-json", { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-upload-html-json/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-upload-html-json/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-upload-html-json

echo ""
echo "✅ Upload ajustado."
echo ""
echo "O que mudou:"
echo "- Upload em lotes menores: até 5 arquivos ou 25MB por lote."
echo "- Se o Render devolver HTML, aparece erro claro."
echo "- Erros de /api/servidor voltam como JSON."
echo "- Criada rota /api/servidor/ping para teste."
echo ""
echo "Agora rode:"
echo "npm run dev"
