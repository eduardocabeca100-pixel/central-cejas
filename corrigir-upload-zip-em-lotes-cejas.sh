#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "servidor.html" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/zip-em-lotes-$STAMP"
mkdir -p "$BACKUP_DIR" lib vendor

cp server.js servidor.html package.json "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

echo "📦 Instalando JSZip para abrir ZIP no navegador..."
npm install jszip --save

cp node_modules/jszip/dist/jszip.min.js vendor/jszip.min.js

cat > lib/servidor-upload-lote-paths-cejas.js <<'EOF'
const path = require("path");
const multer = require("multer");

const uploadLote = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 80 * 1024 * 1024,
    files: 20
  }
});

function limparEnv(value) {
  return String(value || "").trim().replace(/^["']|["']$/g, "");
}

function getEnv() {
  const url =
    limparEnv(process.env.SUPABASE_URL) ||
    limparEnv(process.env.NEXT_PUBLIC_SUPABASE_URL) ||
    limparEnv(process.env.PUBLIC_SUPABASE_URL);

  const serviceRole =
    limparEnv(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    limparEnv(process.env.CEJAS_SUPABASE_SERVICE_ROLE_KEY) ||
    limparEnv(process.env.SUPABASE_SERVICE_KEY) ||
    limparEnv(process.env.SUPABASE_SERVICE_ROLE) ||
    limparEnv(process.env.SUPABASE_SECRET_KEY);

  const bucket =
    limparEnv(process.env.SUPABASE_STORAGE_BUCKET) ||
    limparEnv(process.env.SUPABASE_BUCKET) ||
    "servidor-cejas";

  return { url, serviceRole, bucket };
}

function assertEnv() {
  const env = getEnv();

  if (!env.url || !env.serviceRole || !env.bucket) {
    throw new Error("Supabase Storage não configurado.");
  }

  return env;
}

function headers(extra = {}) {
  const env = assertEnv();

  return {
    apikey: env.serviceRole,
    Authorization: `Bearer ${env.serviceRole}`,
    ...extra
  };
}

function limparPath(value = "") {
  return String(value || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => part && part !== "." && part !== "..")
    .join("/");
}

function encodeStoragePath(value = "") {
  return limparPath(value).split("/").map(encodeURIComponent).join("/");
}

function normalizarNomeArquivo(nome = "") {
  return String(nome || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[<>:"|?*\x00-\x1F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function mesPorNumero(numero) {
  const meses = {
    "01": "01 JANEIRO",
    "02": "02 FEVEREIRO",
    "03": "03 MARCO",
    "04": "04 ABRIL",
    "05": "05 MAIO",
    "06": "06 JUNHO",
    "07": "07 JULHO",
    "08": "08 AGOSTO",
    "09": "09 SETEMBRO",
    "10": "10 OUTUBRO",
    "11": "11 NOVEMBRO",
    "12": "12 DEZEMBRO"
  };

  return meses[String(numero).padStart(2, "0")] || "VERIFICAR";
}

function mimePorNome(nome = "") {
  const ext = path.extname(nome).toLowerCase();

  const map = {
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".csv": "text/csv",
    ".txt": "text/plain",
    ".json": "application/json",
    ".mp3": "audio/mpeg",
    ".mp4": "video/mp4",
    ".mov": "video/quicktime"
  };

  return map[ext] || "application/octet-stream";
}

function destinoArquivoSolto(nomeArquivo) {
  const nome = normalizarNomeArquivo(nomeArquivo);
  const semExt = nome.replace(/\.[^.]+$/, "");

  let ano = "2026";
  let mes = "VERIFICAR";
  let pastaEvento = "VERIFICAR";

  const dataCompleta =
    semExt.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})[.\-_/ ](20\d{2})\b/) ||
    semExt.match(/\b(20\d{2})[.\-_/ ](\d{1,2})[.\-_/ ](\d{1,2})\b/);

  if (dataCompleta) {
    if (dataCompleta[1].startsWith("20")) {
      ano = dataCompleta[1];
      mes = mesPorNumero(dataCompleta[2]);
    } else {
      ano = dataCompleta[3];
      mes = mesPorNumero(dataCompleta[2]);
    }
  } else {
    const dataCurta = semExt.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})\b/);
    if (dataCurta) mes = mesPorNumero(dataCurta[2]);
  }

  const candidato = semExt
    .replace(/\b(20\d{2})\b/g, "")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}[.\-_/ ]20\d{2}\b/g, "")
    .replace(/\b20\d{2}[.\-_/ ]\d{1,2}[.\-_/ ]\d{1,2}\b/g, "")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}\b/g, "")
    .replace(/\b(orcamento|orçamento|boleto|demonstrativo|comprovante|recibo|nota fiscal|nf|contrato)\b/gi, "")
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();

  if (candidato && candidato.length >= 2) {
    pastaEvento = candidato.slice(0, 80);
  }

  return limparPath(`${ano}/${mes}/${pastaEvento}/${nome}`);
}

function deveIgnorar(caminho = "") {
  const clean = limparPath(caminho);
  const base = path.posix.basename(clean);

  if (!clean) return true;
  if (clean.startsWith("__MACOSX/")) return true;
  if (clean.includes("/__MACOSX/")) return true;
  if (base === ".DS_Store") return true;
  if (base.startsWith("._")) return true;
  if (base === "Thumbs.db") return true;
  if (base === "desktop.ini") return true;

  return false;
}

function destinoDoZip(caminhoOriginal = "", nomeArquivo = "") {
  const clean = limparPath(caminhoOriginal || nomeArquivo);

  if (deveIgnorar(clean)) return "";

  const partes = clean.split("/").filter(Boolean).map(normalizarNomeArquivo);

  if (!partes.length) return "";

  if (partes.length === 1) {
    return destinoArquivoSolto(partes[0]);
  }

  return limparPath(partes.join("/"));
}

async function uploadBufferSupabase(caminho, buffer, mimeType) {
  const env = assertEnv();

  const response = await fetch(
    `${env.url.replace(/\/$/, "")}/storage/v1/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(caminho)}`,
    {
      method: "POST",
      headers: headers({
        "Content-Type": mimeType || "application/octet-stream",
        "Cache-Control": "3600",
        "x-upsert": "true"
      }),
      body: buffer
    }
  );

  const text = await response.text();

  if (!response.ok) {
    throw new Error(text || `HTTP ${response.status}`);
  }

  return true;
}

function registrarUploadLotePathsServidorCejas(app) {
  if (!app || app.__CEJAS_UPLOAD_LOTE_PATHS__) return;
  app.__CEJAS_UPLOAD_LOTE_PATHS__ = true;

  app.post("/api/servidor/upload-lote-paths", uploadLote.array("files", 20), async (req, res) => {
    try {
      const files = Array.isArray(req.files) ? req.files : [];
      const paths = JSON.parse(req.body.paths || "[]");

      if (!files.length) {
        return res.status(400).json({
          ok: false,
          message: "Nenhum arquivo recebido no lote."
        });
      }

      let enviados = 0;
      let ignorados = 0;
      const falhas = [];
      const exemplos = [];

      for (let i = 0; i < files.length; i++) {
        const file = files[i];

        try {
          const originalPath = paths[i] || file.originalname;
          const destino = destinoDoZip(originalPath, file.originalname);

          if (!destino) {
            ignorados += 1;
            continue;
          }

          await uploadBufferSupabase(destino, file.buffer, file.mimetype || mimePorNome(destino));

          enviados += 1;

          if (exemplos.length < 12) exemplos.push(destino);
        } catch (error) {
          falhas.push({
            arquivo: file.originalname,
            erro: error.message
          });
        }
      }

      res.set("Cache-Control", "no-store");

      res.json({
        ok: falhas.length === 0,
        partial: falhas.length > 0 && enviados > 0,
        enviados,
        ignorados,
        falhas,
        exemplos
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro no upload em lote: " + error.message
      });
    }
  });
}

module.exports = {
  registrarUploadLotePathsServidorCejas
};
EOF

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const { registrarUploadLotePathsServidorCejas } = require("./lib/servidor-upload-lote-paths-cejas");'

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

call_line = 'registrarUploadLotePathsServidorCejas(app);'

if call_line not in s:
    marker = "const app = express();"
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express();")
    s = s.replace(marker, marker + "\n" + call_line, 1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("servidor.html")
s = p.read_text()

# Remove patch antigo do upload ZIP para não chamar /api/servidor/upload-zip.
s = re.sub(
    r'\s*<script>\s*// CEJAS_UPLOAD_ZIP_SERVIDOR_START[\s\S]*?// CEJAS_UPLOAD_ZIP_SERVIDOR_END\s*</script>',
    '',
    s
)

s = re.sub(
    r'\s*<script>\s*// CEJAS_UPLOAD_ZIP_LOTES_BROWSER_START[\s\S]*?// CEJAS_UPLOAD_ZIP_LOTES_BROWSER_END\s*</script>',
    '',
    s
)

if 'vendor/jszip.min.js' not in s:
    if '</head>' in s:
        s = s.replace('</head>', '<script src="/vendor/jszip.min.js"></script>\n</head>', 1)
    elif '<body' in s:
        s = s.replace('<body', '<script src="/vendor/jszip.min.js"></script>\n<body', 1)

js = r'''
<script>
// CEJAS_UPLOAD_ZIP_LOTES_BROWSER_START
(function () {
  if (window.__CEJAS_UPLOAD_ZIP_LOTES_BROWSER__) return;
  window.__CEJAS_UPLOAD_ZIP_LOTES_BROWSER__ = true;

  const MAX_ARQUIVOS_LOTE = 5;
  const MAX_BYTES_LOTE = 25 * 1024 * 1024;

  function criarBotaoZip() {
    if (document.getElementById("cejasZipServidorInput")) return;

    const area =
      document.querySelector(".actions") ||
      document.querySelector(".topbar") ||
      document.querySelector("main") ||
      document.body;

    const wrap = document.createElement("div");
    wrap.id = "cejasZipServidorWrap";
    wrap.style.cssText = "display:inline-flex;align-items:center;gap:8px;margin-left:8px;flex-wrap:wrap;";

    const input = document.createElement("input");
    input.id = "cejasZipServidorInput";
    input.type = "file";
    input.accept = ".zip,application/zip,application/x-zip-compressed";
    input.style.display = "none";

    const btn = document.createElement("button");
    btn.id = "cejasZipServidorBtn";
    btn.type = "button";
    btn.textContent = "Enviar ZIP em lotes";
    btn.style.cssText = `
      border:1px solid rgba(168,85,247,.42);
      background:linear-gradient(135deg,rgba(168,85,247,.95),rgba(217,70,239,.90));
      color:white;
      border-radius:12px;
      padding:11px 14px;
      font-weight:950;
      cursor:pointer;
      box-shadow:0 12px 32px rgba(168,85,247,.22);
    `;

    const status = document.createElement("span");
    status.id = "cejasZipServidorStatus";
    status.style.cssText = "font-size:12px;color:rgba(255,255,255,.70);font-weight:800;";

    btn.addEventListener("click", () => input.click());

    input.addEventListener("change", async () => {
      const file = input.files && input.files[0];

      if (!file) return;

      if (!file.name.toLowerCase().endsWith(".zip")) {
        alert("Selecione um arquivo .zip.");
        input.value = "";
        return;
      }

      const ok = confirm(
        `Enviar o ZIP "${file.name}" em lotes?\n\nO ZIP será aberto no seu navegador e enviado em partes menores para evitar erro 502.`
      );

      if (!ok) {
        input.value = "";
        return;
      }

      await processarZipEmLotes(file, btn, status);
      input.value = "";
    });

    wrap.appendChild(input);
    wrap.appendChild(btn);
    wrap.appendChild(status);
    area.appendChild(wrap);
  }

  function deveIgnorar(nome) {
    const clean = String(nome || "").replace(/\\/g, "/");
    const base = clean.split("/").pop();

    return !clean ||
      clean.endsWith("/") ||
      clean.includes("__MACOSX/") ||
      base === ".DS_Store" ||
      base === "Thumbs.db" ||
      base === "desktop.ini" ||
      base.startsWith("._");
  }

  async function respostaJsonSegura(response) {
    const text = await response.text();

    try {
      return JSON.parse(text);
    } catch {
      throw new Error(text.slice(0, 500) || `Resposta inválida HTTP ${response.status}`);
    }
  }

  async function enviarLote(lote, numero, total, status) {
    const form = new FormData();
    const paths = [];

    lote.forEach(item => {
      form.append("files", item.file, item.name.split("/").pop());
      paths.push(item.name);
    });

    form.append("paths", JSON.stringify(paths));

    status.textContent = `Enviando lote ${numero}/${total} (${lote.length} arquivo(s))...`;

    const response = await fetch(`/api/servidor/upload-lote-paths?_ts=${Date.now()}`, {
      method: "POST",
      cache: "no-store",
      body: form
    });

    const data = await respostaJsonSegura(response);

    if (!response.ok || data.ok === false) {
      throw new Error(data.message || `Falha no lote ${numero}.`);
    }

    return data;
  }

  async function processarZipEmLotes(zipFile, btn, status) {
    if (!window.JSZip) {
      alert("JSZip não carregou. Atualize a página com Command + Shift + R e tente novamente.");
      return;
    }

    btn.disabled = true;
    btn.textContent = "Abrindo ZIP...";
    status.textContent = "Lendo ZIP no navegador. Não feche a página.";

    try {
      const zip = await window.JSZip.loadAsync(zipFile);
      const entries = Object.values(zip.files).filter(entry => !deveIgnorar(entry.name));

      if (!entries.length) {
        alert("Nenhum arquivo válido encontrado dentro do ZIP.");
        return;
      }

      const lotes = [];
      let loteAtual = [];
      let bytesAtual = 0;

      for (const entry of entries) {
        const blob = await entry.async("blob");
        const file = new File([blob], entry.name.split("/").pop(), {
          type: blob.type || "application/octet-stream"
        });

        if (
          loteAtual.length >= MAX_ARQUIVOS_LOTE ||
          bytesAtual + file.size > MAX_BYTES_LOTE
        ) {
          if (loteAtual.length) lotes.push(loteAtual);
          loteAtual = [];
          bytesAtual = 0;
        }

        loteAtual.push({
          name: entry.name,
          file
        });

        bytesAtual += file.size;
      }

      if (loteAtual.length) lotes.push(loteAtual);

      btn.textContent = "Enviando ZIP...";
      let enviados = 0;
      let falhas = 0;

      for (let i = 0; i < lotes.length; i++) {
        const data = await enviarLote(lotes[i], i + 1, lotes.length, status);
        enviados += Number(data.enviados || 0);
        falhas += Array.isArray(data.falhas) ? data.falhas.length : 0;
      }

      alert(`ZIP enviado.\n\nArquivos enviados: ${enviados}\nFalhas: ${falhas}`);

      status.textContent = `${enviados} arquivo(s) enviados.`;

      setTimeout(() => {
        if (typeof window.carregarServidor === "function") {
          window.carregarServidor();
        } else {
          location.reload();
        }
      }, 1000);
    } catch (error) {
      console.error(error);
      alert("Erro ao enviar ZIP: " + error.message);
      status.textContent = "Erro no envio.";
    } finally {
      btn.disabled = false;
      btn.textContent = "Enviar ZIP em lotes";
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    criarBotaoZip();
    setTimeout(criarBotaoZip, 1000);
    setTimeout(criarBotaoZip, 2500);
  });
})();
// CEJAS_UPLOAD_ZIP_LOTES_BROWSER_END
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

node --check lib/servidor-upload-lote-paths-cejas.js
node --check server.js

node <<'NODE'
const fs = require("fs");
const html = fs.readFileSync("servidor.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-zip-lotes", { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-zip-lotes/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-zip-lotes/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-zip-lotes

echo ""
echo "✅ Upload ZIP corrigido para envio em lotes menores."
echo ""
echo "Agora rode:"
echo "npm start"
