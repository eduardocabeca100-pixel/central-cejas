const fs = require("fs");
const path = require("path");

const {
  supabaseAdmin,
  isSupabaseConfigured,
  SUPABASE_BUCKET
} = require("./supabase");

const BUCKET = process.env.SUPABASE_STORAGE_BUCKET || SUPABASE_BUCKET || "servidor-cejas";
const PREFIX_DATA = "_SISTEMA/data";

let syncRunning = false;
let restoreRunning = false;
let lastSyncAt = 0;

function ativo() {
  return Boolean(isSupabaseConfigured && isSupabaseConfigured() && supabaseAdmin && BUCKET);
}

function normalizarStoragePath(value = "") {
  return String(value || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => part && part !== "." && part !== "..")
    .join("/");
}

function contentType(filePath = "") {
  const ext = path.extname(String(filePath)).toLowerCase();

  const map = {
    ".json": "application/json",
    ".txt": "text/plain; charset=utf-8",
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".csv": "text/csv",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  };

  return map[ext] || "application/octet-stream";
}

async function garantirBucket() {
  if (!ativo()) {
    throw new Error("Supabase Storage não configurado. Confira SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e SUPABASE_STORAGE_BUCKET.");
  }

  const { data, error } = await supabaseAdmin.storage.listBuckets();

  if (error) {
    throw new Error("Erro ao listar buckets: " + error.message);
  }

  const existe = (data || []).some(bucket => bucket.name === BUCKET);

  if (!existe) {
    const created = await supabaseAdmin.storage.createBucket(BUCKET, {
      public: false,
      fileSizeLimit: null
    });

    if (created.error && !String(created.error.message || "").toLowerCase().includes("already")) {
      throw new Error("Erro ao criar bucket " + BUCKET + ": " + created.error.message);
    }
  }

  return true;
}

function listarArquivosLocais(rootDir, dir = rootDir, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;
    if (entry.name === ".DS_Store") continue;

    const full = path.join(dir, entry.name);
    const rel = path.relative(rootDir, full).replace(/\\/g, "/");

    if (entry.isDirectory()) {
      listarArquivosLocais(rootDir, full, result);
    } else if (entry.isFile()) {
      const stat = fs.statSync(full);
      result.push({
        full,
        rel,
        size: stat.size,
        updatedAt: stat.mtime.toISOString()
      });
    }
  }

  return result;
}

async function uploadArquivo(localPath, storagePath) {
  await garantirBucket();

  if (!fs.existsSync(localPath) || !fs.statSync(localPath).isFile()) {
    return { ok: false, skipped: true };
  }

  const buffer = fs.readFileSync(localPath);
  const cleanPath = normalizarStoragePath(storagePath);

  const { error } = await supabaseAdmin.storage.from(BUCKET).upload(cleanPath, buffer, {
    upsert: true,
    contentType: contentType(cleanPath),
    cacheControl: "3600"
  });

  if (error) {
    throw new Error(`Erro ao enviar ${cleanPath}: ${error.message}`);
  }

  return { ok: true, path: cleanPath };
}

async function downloadArquivo(storagePath) {
  await garantirBucket();

  const cleanPath = normalizarStoragePath(storagePath);
  const { data, error } = await supabaseAdmin.storage.from(BUCKET).download(cleanPath);

  if (error || !data) return null;

  const arrayBuffer = await data.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

async function listarStorage(prefix = "") {
  await garantirBucket();

  const folder = normalizarStoragePath(prefix);
  const result = [];
  let offset = 0;
  const limit = 1000;

  while (true) {
    const { data, error } = await supabaseAdmin.storage.from(BUCKET).list(folder, {
      limit,
      offset,
      sortBy: { column: "name", order: "asc" }
    });

    if (error) {
      throw new Error("Erro ao listar Storage: " + error.message);
    }

    const batch = data || [];

    for (const item of batch) {
      if (!item || !item.name || item.name === ".emptyFolderPlaceholder") continue;

      const itemPath = folder ? `${folder}/${item.name}` : item.name;
      const isFile = item.metadata && typeof item.metadata.size === "number";

      if (isFile) {
        result.push({
          type: "file",
          path: itemPath,
          name: item.name,
          size: Number(item.metadata.size || 0),
          updatedAt: item.updated_at || item.created_at || ""
        });
      } else {
        result.push({
          type: "folder",
          path: itemPath,
          name: item.name,
          children: await listarStorage(itemPath)
        });
      }
    }

    if (batch.length < limit) break;
    offset += limit;
  }

  return result;
}

function achatarArquivosStorage(tree, result = []) {
  for (const item of tree || []) {
    if (item.type === "file") result.push(item);
    if (item.children) achatarArquivosStorage(item.children, result);
  }

  return result;
}

async function listarArquivosStorage(prefix = "") {
  const tree = await listarStorage(prefix);
  return achatarArquivosStorage(tree);
}

async function syncDataParaSupabase() {
  const root = path.join(process.cwd(), "data");
  fs.mkdirSync(root, { recursive: true });

  const arquivos = listarArquivosLocais(root)
    .filter(item => item.rel.endsWith(".json") || item.rel.endsWith(".txt"));

  let enviados = 0;

  for (const item of arquivos) {
    await uploadArquivo(item.full, `${PREFIX_DATA}/${item.rel}`);
    enviados += 1;
  }

  return { ok: true, enviados };
}

async function restoreDataDoSupabase() {
  const root = path.join(process.cwd(), "data");
  fs.mkdirSync(root, { recursive: true });

  const arquivos = await listarArquivosStorage(PREFIX_DATA);
  let restaurados = 0;

  for (const item of arquivos) {
    const rel = item.path.replace(`${PREFIX_DATA}/`, "");
    const destino = path.join(root, rel);

    const buffer = await downloadArquivo(item.path);
    if (!buffer) continue;

    fs.mkdirSync(path.dirname(destino), { recursive: true });
    fs.writeFileSync(destino, buffer);
    restaurados += 1;
  }

  return { ok: true, restaurados, totalStorage: arquivos.length };
}

async function syncServidorParaSupabase() {
  const root = path.join(process.cwd(), "uploads", "servidor");
  fs.mkdirSync(root, { recursive: true });

  const arquivos = listarArquivosLocais(root);
  let enviados = 0;

  for (const item of arquivos) {
    if (item.rel.startsWith("_SISTEMA/")) continue;
    await uploadArquivo(item.full, item.rel);
    enviados += 1;
  }

  return { ok: true, enviados };
}

async function restoreServidorDoSupabase() {
  const root = path.join(process.cwd(), "uploads", "servidor");
  fs.mkdirSync(root, { recursive: true });

  const arquivos = (await listarArquivosStorage(""))
    .filter(item => !item.path.startsWith("_SISTEMA/"));

  let restaurados = 0;

  for (const item of arquivos) {
    const destino = path.join(root, item.path);

    if (fs.existsSync(destino)) continue;

    const buffer = await downloadArquivo(item.path);
    if (!buffer) continue;

    fs.mkdirSync(path.dirname(destino), { recursive: true });
    fs.writeFileSync(destino, buffer);
    restaurados += 1;
  }

  return { ok: true, restaurados, totalStorage: arquivos.length };
}

async function syncTudoCejas(motivo = "manual") {
  if (!ativo()) {
    return {
      ok: false,
      skipped: true,
      motivo,
      message: "Supabase Storage não configurado."
    };
  }

  if (syncRunning) {
    return {
      ok: true,
      skipped: true,
      motivo,
      message: "Sync já em andamento."
    };
  }

  const now = Date.now();

  if (motivo === "auto" && now - lastSyncAt < 8000) {
    return {
      ok: true,
      skipped: true,
      motivo,
      message: "Sync ignorado por intervalo curto."
    };
  }

  syncRunning = true;
  lastSyncAt = now;

  try {
    await garantirBucket();

    const data = await syncDataParaSupabase();
    const servidor = await syncServidorParaSupabase();

    return {
      ok: true,
      motivo,
      bucket: BUCKET,
      data,
      servidor,
      syncedAt: new Date().toISOString()
    };
  } finally {
    syncRunning = false;
  }
}

async function restoreTudoCejas(motivo = "startup") {
  if (!ativo()) {
    return {
      ok: false,
      skipped: true,
      motivo,
      message: "Supabase Storage não configurado."
    };
  }

  if (restoreRunning) {
    return {
      ok: true,
      skipped: true,
      motivo,
      message: "Restore já em andamento."
    };
  }

  restoreRunning = true;

  try {
    await garantirBucket();

    const data = await restoreDataDoSupabase();
    const servidor = await restoreServidorDoSupabase();

    return {
      ok: true,
      motivo,
      bucket: BUCKET,
      data,
      servidor,
      restoredAt: new Date().toISOString()
    };
  } finally {
    restoreRunning = false;
  }
}

async function statusPersistenciaCejas() {
  if (!ativo()) {
    return {
      ok: false,
      bucket: BUCKET,
      ativo: false,
      message: "Supabase Storage não configurado."
    };
  }

  await garantirBucket();

  const dataFiles = await listarArquivosStorage(PREFIX_DATA);
  const servidorFiles = (await listarArquivosStorage(""))
    .filter(item => !item.path.startsWith("_SISTEMA/"));

  const localData = listarArquivosLocais(path.join(process.cwd(), "data"));
  const localServidor = listarArquivosLocais(path.join(process.cwd(), "uploads", "servidor"));

  return {
    ok: true,
    ativo: true,
    bucket: BUCKET,
    storage: {
      data: dataFiles.length,
      servidor: servidorFiles.length
    },
    local: {
      data: localData.length,
      servidor: localServidor.length
    },
    checkedAt: new Date().toISOString()
  };
}

module.exports = {
  BUCKET,
  PREFIX_DATA,
  ativo,
  garantirBucket,
  syncTudoCejas,
  restoreTudoCejas,
  statusPersistenciaCejas,
  syncDataParaSupabase,
  restoreDataDoSupabase,
  syncServidorParaSupabase,
  restoreServidorDoSupabase
};
