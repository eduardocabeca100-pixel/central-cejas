#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "servidor.html" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/upload-zip-servidor-$STAMP"
mkdir -p "$BACKUP_DIR" lib

cp server.js servidor.html package.json "$BACKUP_DIR/" 2>/dev/null || true
[ -f lib/servidor-supabase-definitivo.js ] && cp lib/servidor-supabase-definitivo.js "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

echo ""
echo "📦 Garantindo dependência adm-zip..."
npm install adm-zip --save

cat > lib/servidor-upload-zip-cejas.js <<'EOF'
const path = require("path");
const multer = require("multer");
const AdmZip = require("adm-zip");

const uploadZip = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 1024 * 1024 * 1024
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
    throw new Error("Supabase Storage não configurado para upload ZIP.");
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
    .filter(part => {
      if (!part) return false;
      if (part === ".") return false;
      if (part === "..") return false;
      return true;
    })
    .join("/");
}

function encodeStoragePath(value = "") {
  return limparPath(value).split("/").map(encodeURIComponent).join("/");
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

function deveIgnorarZipEntry(nome = "") {
  const clean = limparPath(nome);
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

function destinoArquivoSolto(nomeArquivo) {
  const nome = normalizarNomeArquivo(nomeArquivo);
  const semExt = nome.replace(/\.[^.]+$/, "");

  let match =
    semExt.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})[.\-_/ ](20\d{2})\b/) ||
    semExt.match(/\b(20\d{2})[.\-_/ ](\d{1,2})[.\-_/ ](\d{1,2})\b/);

  let ano = "2026";
  let mes = "VERIFICAR";
  let pastaEvento = "VERIFICAR";

  if (match) {
    if (match[1].startsWith("20")) {
      ano = match[1];
      mes = mesPorNumero(match[2]);
    } else {
      ano = match[3];
      mes = mesPorNumero(match[2]);
    }
  } else {
    const dataCurta = semExt.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})\b/);
    if (dataCurta) {
      mes = mesPorNumero(dataCurta[2]);
    }
  }

  let candidato = semExt
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

function destinoZipEntry(entryName) {
  const clean = limparPath(entryName);
  const parts = clean.split("/").filter(Boolean).map(normalizarNomeArquivo);

  if (!parts.length) return "";

  if (parts.length === 1) {
    return destinoArquivoSolto(parts[0]);
  }

  return limparPath(parts.join("/"));
}

async function uploadBufferSupabase(caminho, buffer, mimeType) {
  const env = assertEnv();
  const storagePath = encodeStoragePath(caminho);

  const response = await fetch(
    `${env.url.replace(/\/$/, "")}/storage/v1/object/${encodeURIComponent(env.bucket)}/${storagePath}`,
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

  return {
    bucket: env.bucket,
    caminho
  };
}

function registrarUploadZipServidorCejas(app) {
  if (!app || app.__CEJAS_UPLOAD_ZIP_SERVIDOR__) return;

  app.__CEJAS_UPLOAD_ZIP_SERVIDOR__ = true;

  app.post("/api/servidor/upload-zip", uploadZip.single("zip"), async (req, res) => {
    try {
      if (!req.file || !req.file.buffer) {
        return res.status(400).json({
          ok: false,
          message: "Nenhum arquivo ZIP enviado."
        });
      }

      const nomeOriginal = req.file.originalname || "arquivos.zip";

      if (!nomeOriginal.toLowerCase().endsWith(".zip")) {
        return res.status(400).json({
          ok: false,
          message: "Envie um arquivo .zip."
        });
      }

      const zip = new AdmZip(req.file.buffer);
      const entries = zip.getEntries();

      let enviados = 0;
      let ignorados = 0;
      const falhas = [];
      const exemplos = [];

      for (const entry of entries) {
        try {
          if (entry.isDirectory) {
            ignorados += 1;
            continue;
          }

          const nomeEntrada = limparPath(entry.entryName);

          if (deveIgnorarZipEntry(nomeEntrada)) {
            ignorados += 1;
            continue;
          }

          const buffer = entry.getData();

          if (!buffer || !buffer.length) {
            ignorados += 1;
            continue;
          }

          const destino = destinoZipEntry(nomeEntrada);

          if (!destino) {
            ignorados += 1;
            continue;
          }

          await uploadBufferSupabase(destino, buffer, mimePorNome(destino));

          enviados += 1;

          if (exemplos.length < 20) {
            exemplos.push(destino);
          }
        } catch (error) {
          falhas.push({
            arquivo: entry.entryName,
            erro: error.message
          });
        }
      }

      res.set("Cache-Control", "no-store");

      res.json({
        ok: falhas.length === 0,
        partial: falhas.length > 0 && enviados > 0,
        arquivoZip: nomeOriginal,
        totalNoZip: entries.length,
        enviados,
        ignorados,
        falhas,
        exemplos,
        message: falhas.length
          ? `${enviados} arquivo(s) enviados. ${falhas.length} falha(s).`
          : `${enviados} arquivo(s) enviados com sucesso pelo ZIP.`
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao processar ZIP: " + error.message
      });
    }
  });
}

module.exports = {
  registrarUploadZipServidorCejas
};
EOF

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const { registrarUploadZipServidorCejas } = require("./lib/servidor-upload-zip-cejas");'

if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace('const path = require("path");', 'const path = require("path");\n' + require_line, 1)
    elif 'const express = require("express");' in s:
        s = s.replace('const express = require("express");', 'const express = require("express");\n' + require_line, 1)
    else:
        s = require_line + "\n" + s

call_line = 'registrarUploadZipServidorCejas(app);'

if call_line not in s:
    marker = "const app = express();"
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express(); em server.js.")
    s = s.replace(marker, marker + "\n" + call_line, 1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("servidor.html")
s = p.read_text()

s = re.sub(
    r'\s*<script>\s*// CEJAS_UPLOAD_ZIP_SERVIDOR_START[\s\S]*?// CEJAS_UPLOAD_ZIP_SERVIDOR_END\s*</script>',
    '',
    s
)

js = r'''
<script>
// CEJAS_UPLOAD_ZIP_SERVIDOR_START
(function () {
  if (window.__CEJAS_UPLOAD_ZIP_SERVIDOR__) return;
  window.__CEJAS_UPLOAD_ZIP_SERVIDOR__ = true;

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
    btn.textContent = "Enviar ZIP";
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
        `Enviar o ZIP "${file.name}" para o Servidor?\n\nO sistema vai abrir o ZIP, manter as pastas e enviar os arquivos para o Supabase Storage.`
      );

      if (!ok) {
        input.value = "";
        return;
      }

      await enviarZip(file, btn, status);
      input.value = "";
    });

    wrap.appendChild(input);
    wrap.appendChild(btn);
    wrap.appendChild(status);
    area.appendChild(wrap);
  }

  async function respostaJsonSegura(response) {
    const text = await response.text();

    try {
      return JSON.parse(text);
    } catch {
      throw new Error(text.slice(0, 500) || `Resposta inválida HTTP ${response.status}`);
    }
  }

  async function enviarZip(file, btn, status) {
    const form = new FormData();
    form.append("zip", file);

    btn.disabled = true;
    btn.textContent = "Enviando ZIP...";
    status.textContent = "Processando arquivo. Não feche a página.";

    try {
      const response = await fetch(`/api/servidor/upload-zip?_ts=${Date.now()}`, {
        method: "POST",
        cache: "no-store",
        body: form
      });

      const data = await respostaJsonSegura(response);

      if (!response.ok || data.ok === false) {
        throw new Error(data.message || "Erro ao enviar ZIP.");
      }

      let msg = data.message || "ZIP enviado com sucesso.";

      if (data.falhas && data.falhas.length) {
        msg += `\n\nFalhas: ${data.falhas.length}`;
      }

      alert(msg);

      status.textContent = `${data.enviados || 0} arquivo(s) enviados.`;

      setTimeout(() => {
        if (typeof window.carregarServidor === "function") {
          window.carregarServidor();
        } else {
          location.reload();
        }
      }, 800);
    } catch (error) {
      console.error(error);
      alert("Erro ao enviar ZIP: " + error.message);
      status.textContent = "Erro no envio do ZIP.";
    } finally {
      btn.disabled = false;
      btn.textContent = "Enviar ZIP";
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    criarBotaoZip();
    setTimeout(criarBotaoZip, 1000);
    setTimeout(criarBotaoZip, 2500);
  });
})();
// CEJAS_UPLOAD_ZIP_SERVIDOR_END
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

node --check lib/servidor-upload-zip-cejas.js
node --check server.js

node <<'NODE'
const fs = require("fs");
const html = fs.readFileSync("servidor.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-upload-zip-servidor", { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-upload-zip-servidor/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-upload-zip-servidor/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-upload-zip-servidor

echo ""
echo "✅ Upload ZIP adicionado na aba Servidor."
echo ""
echo "Agora rode:"
echo "npm start"
