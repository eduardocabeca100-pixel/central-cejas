#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/storage-rest-supabase-$STAMP"
mkdir -p "$BACKUP_DIR" lib
cp server.js package.json lib/servidor-supabase-definitivo.js lib/supabase-runtime-cejas.js "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

cat > lib/servidor-supabase-definitivo.js <<'EOF'
require("dotenv").config();

const fs = require("fs");
const path = require("path");
const express = require("express");
const multer = require("multer");

const LOCAL_ROOT = path.join(process.cwd(), "uploads", "servidor");
const TMP_ROOT = path.join(process.cwd(), "uploads", "tmp-servidor-supabase");

fs.mkdirSync(LOCAL_ROOT, { recursive: true });
fs.mkdirSync(TMP_ROOT, { recursive: true });

const uploadServidorSupabase = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, TMP_ROOT),
    filename: (_req, file, cb) => {
      const safe = Date.now() + "-" + Math.random().toString(16).slice(2) + "-" + String(file.originalname || "arquivo").replace(/[^a-zA-Z0-9._-]/g, "-");
      cb(null, safe);
    }
  }),
  limits: {
    fileSize: 900 * 1024 * 1024,
    files: 10000
  }
});

function cleanEnv(value) {
  return String(value || "").trim().replace(/^["']|["']$/g, "");
}

function getRuntimeEnv() {
  const url =
    cleanEnv(process.env.SUPABASE_URL) ||
    cleanEnv(process.env.NEXT_PUBLIC_SUPABASE_URL) ||
    cleanEnv(process.env.PUBLIC_SUPABASE_URL);

  const serviceRole =
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.CEJAS_SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE) ||
    cleanEnv(process.env.SUPABASE_SECRET_KEY);

  const bucket =
    cleanEnv(process.env.SUPABASE_STORAGE_BUCKET) ||
    cleanEnv(process.env.SUPABASE_BUCKET) ||
    "servidor-cejas";

  return { url, serviceRole, bucket };
}

function getSupabaseRuntimeStatus() {
  const env = getRuntimeEnv();

  return {
    ok: Boolean(env.url && env.serviceRole && env.bucket),
    has_SUPABASE_URL: Boolean(process.env.SUPABASE_URL),
    has_NEXT_PUBLIC_SUPABASE_URL: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    has_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    has_CEJAS_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.CEJAS_SUPABASE_SERVICE_ROLE_KEY),
    has_SUPABASE_STORAGE_BUCKET: Boolean(process.env.SUPABASE_STORAGE_BUCKET),
    resolvedUrl: Boolean(env.url),
    resolvedServiceRole: Boolean(env.serviceRole),
    resolvedBucket: Boolean(env.bucket),
    bucket: env.bucket,
    keyType: env.serviceRole.startsWith("eyJ") && env.serviceRole.split(".").length === 3
      ? "legacy-jwt"
      : env.serviceRole.startsWith("sb_secret_")
        ? "new-secret-key"
        : "unknown",
    lengths: {
      url: env.url ? env.url.length : 0,
      serviceRole: env.serviceRole ? env.serviceRole.length : 0,
      bucket: env.bucket ? env.bucket.length : 0
    }
  };
}

function assertStorageEnv() {
  const status = getSupabaseRuntimeStatus();

  if (!status.ok) {
    throw new Error("Supabase Storage não configurado no runtime. Status: " + JSON.stringify(status));
  }

  return getRuntimeEnv();
}

function encodeStoragePath(value = "") {
  return limparPath(value)
    .split("/")
    .map(encodeURIComponent)
    .join("/");
}

function storageHeaders(extra = {}) {
  const env = assertStorageEnv();
  const headers = {
    apikey: env.serviceRole,
    ...extra
  };

  // Legacy service_role é JWT. Chave nova sb_secret NÃO pode ir como Bearer JWT.
  if (env.serviceRole.startsWith("eyJ") && env.serviceRole.split(".").length === 3) {
    headers.Authorization = `Bearer ${env.serviceRole}`;
  }

  return headers;
}

async function storageRequest(route, options = {}) {
  const env = assertStorageEnv();
  const url = `${env.url.replace(/\/$/, "")}/storage/v1${route}`;
  const response = await fetch(url, {
    ...options,
    headers: storageHeaders(options.headers || {})
  });

  const contentType = response.headers.get("content-type") || "";
  const isJson = contentType.includes("application/json");

  if (!response.ok) {
    const body = isJson ? await response.json().catch(() => null) : await response.text().catch(() => "");
    const msg = body?.message || body?.error || body?.msg || body || `HTTP ${response.status}`;
    throw new Error(String(msg));
  }

  if (options.raw) {
    const arrayBuffer = await response.arrayBuffer();
    return Buffer.from(arrayBuffer);
  }

  if (response.status === 204) return null;
  return isJson ? response.json() : response.text();
}

function storageAtivo() {
  return getSupabaseRuntimeStatus().ok;
}

// Não usa listBuckets, porque chave nova pode falhar como JWT. Usa o bucket direto.
async function garantirBucket() {
  assertStorageEnv();
  return true;
}

function limparPath(value = "") {
  return String(value || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => part && part !== "." && part !== "..")
    .join("/");
}

function localPath(relativePath = "") {
  const clean = limparPath(relativePath);
  const full = path.join(LOCAL_ROOT, clean);
  const resolved = path.resolve(full);
  const root = path.resolve(LOCAL_ROOT);

  if (!resolved.startsWith(root)) {
    throw new Error("Caminho inválido.");
  }

  return resolved;
}

function contentType(filePath = "") {
  const ext = path.extname(String(filePath)).toLowerCase();

  const map = {
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".txt": "text/plain; charset=utf-8",
    ".json": "application/json",
    ".csv": "text/csv",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  };

  return map[ext] || "application/octet-stream";
}

async function uploadBuffer(relativePath, buffer) {
  await garantirBucket();

  const env = getRuntimeEnv();
  const clean = limparPath(relativePath);

  if (!clean) throw new Error("Caminho vazio para upload.");

  await storageRequest(`/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(clean)}`, {
    method: "POST",
    headers: {
      "Content-Type": contentType(clean),
      "Cache-Control": "3600",
      "x-upsert": "true"
    },
    body: buffer
  });

  const local = localPath(clean);
  fs.mkdirSync(path.dirname(local), { recursive: true });
  fs.writeFileSync(local, buffer);

  return { ok: true, path: clean, bucket: env.bucket };
}

async function uploadLocal(localFile, relativePath) {
  const buffer = fs.readFileSync(localFile);
  return uploadBuffer(relativePath, buffer);
}

async function downloadBuffer(relativePath) {
  await garantirBucket();

  const env = getRuntimeEnv();
  const clean = limparPath(relativePath);

  try {
    return await storageRequest(`/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(clean)}`, {
      method: "GET",
      raw: true
    });
  } catch {
    return null;
  }
}

async function listarStorage(prefix = "") {
  await garantirBucket();

  const env = getRuntimeEnv();
  const folder = limparPath(prefix);
  const result = [];
  let offset = 0;
  const limit = 1000;

  while (true) {
    const batch = await storageRequest(`/object/list/${encodeURIComponent(env.bucket)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        prefix: folder,
        limit,
        offset,
        sortBy: { column: "name", order: "asc" }
      })
    });

    const items = Array.isArray(batch) ? batch : [];

    for (const item of items) {
      if (!item || !item.name || item.name === ".emptyFolderPlaceholder") continue;

      const rel = folder ? `${folder}/${item.name}` : item.name;
      const isFile = item.metadata && typeof item.metadata.size === "number";

      if (isFile) {
        result.push({
          type: "file",
          name: item.name,
          path: rel,
          size: Number(item.metadata.size || 0),
          updatedAt: item.updated_at || item.created_at || new Date().toISOString()
        });
      } else {
        result.push({
          type: "folder",
          name: item.name,
          path: rel,
          size: 0,
          updatedAt: item.updated_at || item.created_at || new Date().toISOString(),
          children: await listarStorage(rel)
        });
      }
    }

    if (items.length < limit) break;
    offset += limit;
  }

  return result.sort((a, b) => {
    if (a.type !== b.type) return a.type === "folder" ? -1 : 1;
    return a.name.localeCompare(b.name, "pt-BR");
  });
}

function achatarArquivos(items, result = []) {
  for (const item of items || []) {
    if (item.type === "file") result.push(item.path);
    if (item.children) achatarArquivos(item.children, result);
  }

  return result;
}

async function listarArquivos(prefix = "") {
  return achatarArquivos(await listarStorage(prefix));
}

async function deletarItem(relativePath) {
  await garantirBucket();

  const env = getRuntimeEnv();
  const clean = limparPath(relativePath);
  if (!clean) throw new Error("Caminho vazio.");

  const arquivos = await listarArquivos(clean);
  const targets = arquivos.length ? arquivos : [clean];

  for (let i = 0; i < targets.length; i += 100) {
    const chunk = targets.slice(i, i + 100);

    await storageRequest(`/object/${encodeURIComponent(env.bucket)}`, {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prefixes: chunk })
    });
  }

  const local = localPath(clean);
  if (fs.existsSync(local)) {
    fs.rmSync(local, { recursive: true, force: true });
  }

  return { ok: true, deleted: targets.length, paths: targets };
}

async function moverArquivo(origem, destino) {
  await garantirBucket();

  const env = getRuntimeEnv();

  await storageRequest("/object/move", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      bucketId: env.bucket,
      sourceKey: limparPath(origem),
      destinationKey: limparPath(destino)
    })
  });
}

async function moverItem(origem, destinoPasta) {
  const origemClean = limparPath(origem);
  const destinoDir = limparPath(destinoPasta);

  if (!origemClean || !destinoDir) throw new Error("Origem e destino são obrigatórios.");

  const arquivos = await listarArquivos(origemClean);
  const destinoBase = limparPath(path.posix.join(destinoDir, path.posix.basename(origemClean)));

  if (arquivos.length) {
    let movidos = 0;

    for (const arquivo of arquivos) {
      const relDentro = arquivo.replace(origemClean, "").replace(/^\/+/, "");
      const destinoArquivo = limparPath(path.posix.join(destinoBase, relDentro));
      await moverArquivo(arquivo, destinoArquivo);
      movidos += 1;
    }

    return { ok: true, destino: destinoBase, movidos };
  }

  const destino = limparPath(path.posix.join(destinoDir, path.posix.basename(origemClean)));
  await moverArquivo(origemClean, destino);

  return { ok: true, destino, movidos: 1 };
}

const MESES = [
  ["01", "JANEIRO", ["JAN", "JANEIRO"]],
  ["02", "FEVEREIRO", ["FEV", "FEVEREIRO"]],
  ["03", "MARÇO", ["MAR", "MARCO", "MARÇO"]],
  ["04", "ABRIL", ["ABR", "ABRIL"]],
  ["05", "MAIO", ["MAI", "MAIO"]],
  ["06", "JUNHO", ["JUN", "JUNHO"]],
  ["07", "JULHO", ["JUL", "JULHO"]],
  ["08", "AGOSTO", ["AGO", "AGOSTO"]],
  ["09", "SETEMBRO", ["SET", "SETEMBRO"]],
  ["10", "OUTUBRO", ["OUT", "OUTUBRO"]],
  ["11", "NOVEMBRO", ["NOV", "NOVEMBRO"]],
  ["12", "DEZEMBRO", ["DEZ", "DEZEMBRO"]]
];

function normalizar(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function slug(texto, fallback = "VERIFICAR") {
  const clean = normalizar(texto)
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  return clean || fallback;
}

function nomeArquivoSeguro(fileName) {
  return String(fileName || "arquivo")
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^\.+/, "arquivo") || "arquivo";
}

function pastaMes(mes) {
  const item = MESES.find(m => m[0] === String(mes).padStart(2, "0"));
  return item ? `${item[0]} ${item[1]}` : "MES NAO IDENTIFICADO";
}

function pastaMesVerificar(mes) {
  const item = MESES.find(m => m[0] === String(mes).padStart(2, "0"));
  return item ? item[1] : "SEM MES";
}

function detectarData(texto, anoPadrao = "2026") {
  const original = String(texto || "");

  let m = original.match(/\b(20\d{2})[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ](\d{1,2})\b/);
  if (m) return { ok: true, ano: m[1], mes: String(m[2]).padStart(2, "0"), dia: String(m[3]).padStart(2, "0") };

  m = original.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})[.\-_/ ](20\d{2}|\d{2})\b/);
  if (m) return { ok: true, ano: String(m[3]).length === 2 ? `20${m[3]}` : m[3], mes: String(m[2]).padStart(2, "0"), dia: String(m[1]).padStart(2, "0") };

  m = original.match(/(?:^|[^\d])(\d{1,2})\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?(?:[^\d]|$)/i);
  if (m) return { ok: true, ano: m[3] ? (String(m[3]).length === 2 ? `20${m[3]}` : m[3]) : anoPadrao, mes: String(m[2]).padStart(2, "0"), dia: String(m[1]).padStart(2, "0") };

  return { ok: false, ano: anoPadrao, mes: "", dia: "" };
}

function limparNomeEvento(originalPath, fileName) {
  let base = path.basename(String(fileName || originalPath || "arquivo"), path.extname(String(fileName || originalPath || "")));

  base = base
    .replace(/\b20\d{2}[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ]\d{1,2}\b/g, " ")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}[.\-_/ ](20\d{2}|\d{2})\b/g, " ")
    .replace(/(^|[^\d])\d{1,2}\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?($|[^\d])/gi, " ")
    .replace(/\b(CONTRATO|BOLETO|DEMONSTRATIVO|ORCAMENTO|ORÇAMENTO|RELATORIO|RELATÓRIO|PDF|DOCX?|XLSX?)\b/gi, " ")
    .replace(/[_\-.]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  return slug(base || "VERIFICAR");
}

function destinoInteligente(originalPath, fileName, anoPadrao = "2026") {
  const texto = `${originalPath || ""} ${fileName || ""}`;
  const data = detectarData(texto, anoPadrao);
  const titulo = limparNomeEvento(originalPath, fileName);
  const nomeArquivo = nomeArquivoSeguro(fileName || path.basename(originalPath || "arquivo"));

  if (data.ok && data.dia && data.mes && titulo) {
    const destino = `${pastaMes(data.mes)}/${slug(`${titulo} ${data.dia}.${data.mes}`)}/${nomeArquivo}`;
    return limparPath(data.ano && data.ano !== String(anoPadrao) ? `${data.ano}/${destino}` : destino);
  }

  return limparPath(`VERIFICAR/${data.mes ? pastaMesVerificar(data.mes) : "SEM MES"}/${nomeArquivo}`);
}

function listarPastas(tree, result = []) {
  for (const item of tree || []) {
    if (item.type === "folder") {
      result.push(item.path);
      listarPastas(item.children || [], result);
    }
  }
  return result;
}

function listarVerificar(tree, result = []) {
  for (const item of tree || []) {
    if (item.type === "file" && item.path.startsWith("VERIFICAR/")) {
      result.push({
        path: item.path,
        nome: item.name,
        pasta: path.posix.dirname(item.path),
        mes: item.path.split("/")[1] || "SEM MES"
      });
    }
    if (item.children) listarVerificar(item.children, result);
  }
  return result;
}

function registrarRotasServidorSupabaseDefinitivo(app) {
  app.get("/api/debug/storage-runtime", (_req, res) => {
    res.json({ ok: true, storage: getSupabaseRuntimeStatus() });
  });

  app.get("/api/servidor/tree", async (_req, res) => {
    try {
      const root = await listarStorage();
      res.json({ ok: true, origem: "supabase-storage-rest", bucket: getRuntimeEnv().bucket, root });
    } catch (error) {
      res.status(500).json({ ok: false, message: "Erro ao carregar servidor: " + error.message });
    }
  });

  app.get("/api/servidor/pastas", async (_req, res) => {
    try {
      const root = await listarStorage();
      res.json({ ok: true, pastas: listarPastas(root).filter(p => !p.startsWith("VERIFICAR/")) });
    } catch (error) {
      res.status(500).json({ ok: false, message: "Erro ao listar pastas: " + error.message });
    }
  });

  app.get("/api/servidor/verificar", async (_req, res) => {
    try {
      const root = await listarStorage();
      res.json({ ok: true, itens: listarVerificar(root) });
    } catch (error) {
      res.status(500).json({ ok: false, message: "Erro ao listar VERIFICAR: " + error.message });
    }
  });

  app.get("/api/servidor/arquivo", async (req, res) => {
    try {
      const relativePath = limparPath(req.query.path || "");
      const buffer = await downloadBuffer(relativePath);

      if (!buffer) return res.status(404).send("Arquivo não encontrado.");

      res.type(contentType(relativePath));
      res.send(buffer);
    } catch (error) {
      res.status(500).send("Erro ao abrir arquivo: " + error.message);
    }
  });

  app.post("/api/servidor/upload-inteligente", uploadServidorSupabase.array("arquivos"), async (req, res) => {
    try {
      const files = req.files || [];
      let paths = req.body.paths || [];
      const anoPadrao = req.body.anoPadrao || "2026";

      if (!Array.isArray(paths)) paths = [paths];

      if (!files.length) {
        return res.status(400).json({ ok: false, message: "Nenhum arquivo enviado." });
      }

      const salvos = [];
      const verificar = [];

      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const originalRelative = paths[i] || file.originalname;
        const destino = destinoInteligente(originalRelative, file.originalname, anoPadrao);

        await uploadLocal(file.path, destino);
        fs.rmSync(file.path, { force: true });

        salvos.push(destino);
        if (destino.startsWith("VERIFICAR/")) verificar.push(destino);
      }

      res.json({
        ok: true,
        saved: salvos.length,
        verificar: verificar.length,
        exemplos: salvos.slice(0, 12),
        message: `${salvos.length} arquivo(s) salvos no Supabase Storage. ${verificar.length} foram para VERIFICAR.`
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: "Erro no upload inteligente: " + error.message });
    }
  });

  app.post("/api/servidor/upload", uploadServidorSupabase.array("arquivos"), async (req, res) => {
    try {
      const files = req.files || [];
      const destinoPasta = limparPath(req.body.destino || "");
      const salvos = [];

      if (!files.length) {
        return res.status(400).json({ ok: false, message: "Nenhum arquivo enviado." });
      }

      for (const file of files) {
        const destino = limparPath(path.posix.join(destinoPasta, nomeArquivoSeguro(file.originalname)));
        await uploadLocal(file.path, destino);
        fs.rmSync(file.path, { force: true });
        salvos.push(destino);
      }

      res.json({ ok: true, saved: salvos.length, exemplos: salvos.slice(0, 12), message: `${salvos.length} arquivo(s) salvos no Supabase Storage.` });
    } catch (error) {
      res.status(500).json({ ok: false, message: "Erro ao enviar arquivo: " + error.message });
    }
  });

  app.post("/api/servidor/mover", express.json({ limit: "2mb" }), async (req, res) => {
    try {
      const result = await moverItem(req.body?.origem || "", req.body?.destinoPasta || "");
      res.json({ ok: true, ...result, message: "Item movido no Supabase Storage." });
    } catch (error) {
      res.status(500).json({ ok: false, message: "Erro ao mover item: " + error.message });
    }
  });

  app.delete("/api/servidor/item", async (req, res) => {
    try {
      const result = await deletarItem(req.query.path || "");
      res.json({ ok: true, ...result, message: `Item apagado definitivamente do Supabase Storage. Arquivos removidos: ${result.deleted}.` });
    } catch (error) {
      res.status(500).json({ ok: false, message: "Erro ao apagar definitivamente: " + error.message });
    }
  });

  app.get("/api/servidor/storage-status", async (_req, res) => {
    try {
      const arquivos = await listarArquivos();
      res.json({ ok: true, bucket: getRuntimeEnv().bucket, arquivos: arquivos.length, origem: "supabase-storage-rest" });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });
}

module.exports = {
  registrarRotasServidorSupabaseDefinitivo,
  uploadServidorSupabase,
  storageAtivo,
  garantirBucket,
  listarStorage,
  listarArquivos,
  uploadLocal,
  uploadBuffer,
  downloadBuffer,
  deletarItem,
  moverItem,
  destinoInteligente,
  getSupabaseRuntimeStatus
};
EOF

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const { registrarRotasServidorSupabaseDefinitivo } = require("./lib/servidor-supabase-definitivo");'

if require_line not in s:
    s = s.replace('const path = require("path");', 'const path = require("path");\n' + require_line, 1)

if "registrarRotasServidorSupabaseDefinitivo(app);" not in s:
    marker = "const app = express();"
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express();")
    s = s.replace(marker, marker + "\nregistrarRotasServidorSupabaseDefinitivo(app);", 1)

p.write_text(s)
PY

node --check lib/servidor-supabase-definitivo.js
node --check server.js

echo ""
echo "✅ Storage corrigido para REST API."
echo ""
echo "Agora rode localmente:"
echo "npm run dev"
echo ""
echo "Depois suba:"
echo "git add ."
echo "git commit -m \"fix: usa Storage REST API com chave secret do Supabase\""
echo "git push -u origin main"
