const fs = require("fs");
const path = require("path");
const {
  supabaseAdmin,
  isSupabaseConfigured,
  SUPABASE_BUCKET
} = require("./supabase");

const BUCKET = process.env.SUPABASE_STORAGE_BUCKET || SUPABASE_BUCKET || "servidor-cejas";
let bucketReady = false;
let syncRunning = false;
let lastSyncStartedAt = 0;

function storageAtivoServidor() {
  return Boolean(isSupabaseConfigured && isSupabaseConfigured() && supabaseAdmin && BUCKET);
}

function limparStoragePathServidor(relativePath = "") {
  return String(relativePath || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => part && part !== "." && part !== "..")
    .join("/");
}

function contentTypeServidor(filePath = "") {
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

async function garantirBucketServidor() {
  if (!storageAtivoServidor()) return false;
  if (bucketReady) return true;

  const { data: buckets, error: listError } = await supabaseAdmin.storage.listBuckets();
  if (listError) throw new Error("Erro ao listar buckets do Supabase: " + listError.message);

  const existe = (buckets || []).some(bucket => bucket.name === BUCKET);

  if (!existe) {
    const { error: createError } = await supabaseAdmin.storage.createBucket(BUCKET, {
      public: false,
      fileSizeLimit: null
    });

    if (createError && !String(createError.message || "").toLowerCase().includes("already")) {
      throw new Error("Erro ao criar bucket " + BUCKET + ": " + createError.message);
    }
  }

  bucketReady = true;
  return true;
}

async function uploadBufferSupabaseServidor(relativePath, buffer, contentType) {
  if (!(await garantirBucketServidor())) {
    return { ok: false, skipped: true, message: "Supabase Storage não configurado." };
  }

  const storagePath = limparStoragePathServidor(relativePath);
  if (!storagePath) throw new Error("Caminho inválido para Storage.");

  const { error } = await supabaseAdmin.storage
    .from(BUCKET)
    .upload(storagePath, buffer, {
      contentType: contentType || contentTypeServidor(storagePath),
      upsert: true,
      cacheControl: "3600"
    });

  if (error) throw new Error("Erro ao enviar para Supabase Storage: " + error.message);

  return { ok: true, path: storagePath, bucket: BUCKET };
}

async function uploadLocalFileSupabaseServidor(localPath, relativePath) {
  if (!fs.existsSync(localPath) || !fs.statSync(localPath).isFile()) {
    return { ok: false, skipped: true, message: "Arquivo local não encontrado." };
  }

  const buffer = fs.readFileSync(localPath);
  return uploadBufferSupabaseServidor(relativePath, buffer, contentTypeServidor(relativePath));
}

async function downloadBufferSupabaseServidor(relativePath) {
  if (!(await garantirBucketServidor())) return null;

  const storagePath = limparStoragePathServidor(relativePath);
  const { data, error } = await supabaseAdmin.storage.from(BUCKET).download(storagePath);

  if (error) return null;
  if (!data) return null;

  const arrayBuffer = await data.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

async function moverSupabaseServidor(origem, destino) {
  if (!(await garantirBucketServidor())) return { ok: false, skipped: true };

  const origemPath = limparStoragePathServidor(origem);
  const destinoPath = limparStoragePathServidor(destino);

  if (!origemPath || !destinoPath) return { ok: false, skipped: true };

  const { error } = await supabaseAdmin.storage.from(BUCKET).move(origemPath, destinoPath);

  if (error) {
    const msg = String(error.message || "").toLowerCase();
    if (msg.includes("not found") || msg.includes("does not exist") || msg.includes("object not found")) {
      return { ok: false, skipped: true, message: "Origem não existia no Storage." };
    }

    throw new Error("Erro ao mover no Supabase Storage: " + error.message);
  }

  return { ok: true, origem: origemPath, destino: destinoPath };
}


async function deletarSupabaseServidor(paths) {
  if (!(await garantirBucketServidor())) {
    return { ok: false, skipped: true, message: "Supabase Storage não configurado." };
  }

  const lista = Array.isArray(paths) ? paths : [paths];
  const limpos = lista
    .map(limparStoragePathServidor)
    .filter(Boolean);

  if (!limpos.length) {
    return { ok: true, deleted: 0, paths: [] };
  }

  const chunks = [];

  for (let i = 0; i < limpos.length; i += 100) {
    chunks.push(limpos.slice(i, i + 100));
  }

  let deleted = 0;

  for (const chunk of chunks) {
    const { error } = await supabaseAdmin.storage.from(BUCKET).remove(chunk);

    if (error) {
      throw new Error("Erro ao apagar do Supabase Storage: " + error.message);
    }

    deleted += chunk.length;
  }

  return {
    ok: true,
    deleted,
    paths: limpos,
    bucket: BUCKET
  };
}

async function deletarPrefixoSupabaseServidor(prefix) {
  if (!(await garantirBucketServidor())) {
    return { ok: false, skipped: true, message: "Supabase Storage não configurado." };
  }

  const prefixLimpo = limparStoragePathServidor(prefix);
  const arquivos = await listarArquivosStorageServidor(prefixLimpo);

  if (!arquivos.length) {
    return { ok: true, deleted: 0, paths: [] };
  }

  return deletarSupabaseServidor(arquivos);
}

async function listarStorageServidor(prefix = "") {
  if (!(await garantirBucketServidor())) return [];

  const folder = limparStoragePathServidor(prefix);
  let offset = 0;
  const limit = 1000;
  const all = [];

  while (true) {
    const { data, error } = await supabaseAdmin.storage.from(BUCKET).list(folder, {
      limit,
      offset,
      sortBy: { column: "name", order: "asc" }
    });

    if (error) throw new Error("Erro ao listar Storage: " + error.message);

    const batch = data || [];
    all.push(...batch);

    if (batch.length < limit) break;
    offset += limit;
  }

  const result = [];

  for (const item of all) {
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
        children: await listarStorageServidor(rel)
      });
    }
  }

  return result.sort((a, b) => {
    if (a.type !== b.type) return a.type === "folder" ? -1 : 1;
    return a.name.localeCompare(b.name, "pt-BR");
  });
}

async function listarArquivosStorageServidor(prefix = "") {
  const tree = await listarStorageServidor(prefix);
  const arquivos = [];

  function walk(items) {
    for (const item of items || []) {
      if (item.type === "file") arquivos.push(item.path);
      if (item.children) walk(item.children);
    }
  }

  walk(tree);
  return arquivos;
}

function listarArquivosLocaisServidor(rootDir, dir = rootDir, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;

    const full = path.join(dir, entry.name);
    const rel = path.relative(rootDir, full).replace(/\\/g, "/");

    if (entry.isDirectory()) {
      listarArquivosLocaisServidor(rootDir, full, result);
    } else if (entry.isFile()) {
      result.push({ full, rel, mtimeMs: fs.statSync(full).mtimeMs });
    }
  }

  return result;
}

async function enviarDiretorioParaSupabaseServidor(rootDir) {
  if (!(await garantirBucketServidor())) return { ok: false, skipped: true };

  const arquivos = listarArquivosLocaisServidor(rootDir);
  let enviados = 0;

  for (const arquivo of arquivos) {
    await uploadLocalFileSupabaseServidor(arquivo.full, arquivo.rel);
    enviados += 1;
  }

  return { ok: true, enviados, bucket: BUCKET };
}

async function restaurarSupabaseParaDiretorioServidor(rootDir) {
  if (!(await garantirBucketServidor())) return { ok: false, skipped: true };

  fs.mkdirSync(rootDir, { recursive: true });

  const arquivos = await listarArquivosStorageServidor();
  let restaurados = 0;

  for (const rel of arquivos) {
    const localPath = path.join(rootDir, limparStoragePathServidor(rel));

    if (fs.existsSync(localPath)) continue;

    const buffer = await downloadBufferSupabaseServidor(rel);
    if (!buffer) continue;

    fs.mkdirSync(path.dirname(localPath), { recursive: true });
    fs.writeFileSync(localPath, buffer);
    restaurados += 1;
  }

  return { ok: true, restaurados, totalStorage: arquivos.length, bucket: BUCKET };
}

async function iniciarProtecaoServidorSupabase(rootDir) {
  if (!storageAtivoServidor()) {
    console.warn("⚠️ Supabase Storage do servidor não está ativo. Verifique SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e SUPABASE_STORAGE_BUCKET.");
    return;
  }

  const executarSync = async (motivo = "auto") => {
    if (syncRunning) return;

    const now = Date.now();
    if (motivo === "auto" && now - lastSyncStartedAt < 20000) return;

    syncRunning = true;
    lastSyncStartedAt = now;

    try {
      await garantirBucketServidor();
      const restore = await restaurarSupabaseParaDiretorioServidor(rootDir);
      const upload = await enviarDiretorioParaSupabaseServidor(rootDir);
      console.log(`✅ Proteção Supabase Storage ativa (${motivo}): restaurados=${restore.restaurados || 0}, enviados=${upload.enviados || 0}, bucket=${BUCKET}`);
    } catch (error) {
      console.warn("⚠️ Falha na proteção Supabase Storage:", error.message);
    } finally {
      syncRunning = false;
    }
  };

  setTimeout(() => executarSync("inicial"), 1800);
  setInterval(() => executarSync("auto"), 60000).unref?.();
}

module.exports = {
  BUCKET,
  storageAtivoServidor,
  garantirBucketServidor,
  uploadBufferSupabaseServidor,
  uploadLocalFileSupabaseServidor,
  downloadBufferSupabaseServidor,
  moverSupabaseServidor,
  deletarSupabaseServidor,
  deletarPrefixoSupabaseServidor,
  listarStorageServidor,
  listarArquivosStorageServidor,
  enviarDiretorioParaSupabaseServidor,
  restaurarSupabaseParaDiretorioServidor,
  iniciarProtecaoServidorSupabase,
  limparStoragePathServidor
};
