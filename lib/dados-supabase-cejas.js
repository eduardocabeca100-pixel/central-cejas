require("dotenv").config();

const fs = require("fs");
const path = require("path");

const DATA_ROOT = path.join(process.cwd(), "data");
const PREFIX = "_SISTEMA/data";

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

function statusDadosSupabase() {
  const env = getRuntimeEnv();

  return {
    ok: Boolean(env.url && env.serviceRole && env.bucket),
    bucket: env.bucket,
    prefix: PREFIX,
    resolvedUrl: Boolean(env.url),
    resolvedServiceRole: Boolean(env.serviceRole),
    resolvedBucket: Boolean(env.bucket)
  };
}

function assertEnv() {
  const status = statusDadosSupabase();

  if (!status.ok) {
    throw new Error("Supabase não configurado para persistência de data/: " + JSON.stringify(status));
  }

  return getRuntimeEnv();
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

async function storageRequest(route, options = {}) {
  const env = assertEnv();
  const url = `${env.url.replace(/\/$/, "")}/storage/v1${route}`;

  const response = await fetch(url, {
    ...options,
    headers: headers(options.headers || {})
  });

  const contentType = response.headers.get("content-type") || "";
  const isJson = contentType.includes("application/json");

  if (!response.ok) {
    const body = isJson
      ? await response.json().catch(() => null)
      : await response.text().catch(() => "");

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

function listarArquivosLocais(dir = DATA_ROOT, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".DS_Store") continue;

    const full = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      listarArquivosLocais(full, result);
    } else if (entry.isFile()) {
      const rel = path.relative(DATA_ROOT, full).replace(/\\/g, "/");

      if (
        rel.endsWith(".json") ||
        rel.endsWith(".txt") ||
        rel.endsWith(".csv")
      ) {
        result.push({ full, rel });
      }
    }
  }

  return result;
}

async function listarStorageData() {
  const env = assertEnv();
  const todos = [];
  const visitados = new Set();

  async function listarPrefixo(prefix) {
    const folder = limparPath(prefix);

    if (visitados.has(folder)) return;
    visitados.add(folder);

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
          sortBy: {
            column: "name",
            order: "asc"
          }
        })
      });

      const items = Array.isArray(batch) ? batch : [];

      for (const item of items) {
        if (!item || !item.name || item.name === ".emptyFolderPlaceholder") continue;

        const rel = folder ? `${folder}/${item.name}` : item.name;
        const isFile = item.metadata && typeof item.metadata.size === "number";

        if (isFile) {
          todos.push(rel);
        } else {
          await listarPrefixo(rel);
        }
      }

      if (items.length < limit) break;
      offset += limit;
    }
  }

  await listarPrefixo(PREFIX);
  return todos;
}

async function uploadArquivoData(localFile, rel) {
  const env = assertEnv();
  const storagePath = limparPath(`${PREFIX}/${rel}`);
  const buffer = fs.readFileSync(localFile);

  await storageRequest(`/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(storagePath)}`, {
    method: "POST",
    headers: {
      "Content-Type": rel.endsWith(".json") ? "application/json" : "text/plain; charset=utf-8",
      "Cache-Control": "3600",
      "x-upsert": "true"
    },
    body: buffer
  });

  return storagePath;
}

async function baixarArquivoData(storagePath) {
  const env = assertEnv();

  return storageRequest(`/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(storagePath)}`, {
    method: "GET",
    raw: true
  });
}

async function syncDataParaSupabase() {
  fs.mkdirSync(DATA_ROOT, { recursive: true });

  const arquivos = listarArquivosLocais();
  const enviados = [];

  for (const item of arquivos) {
    try {
      const pathStorage = await uploadArquivoData(item.full, item.rel);
      enviados.push(pathStorage);
    } catch (error) {
      console.warn("⚠️ Falha ao sincronizar data/" + item.rel + ":", error.message);
    }
  }

  return {
    ok: true,
    enviados: enviados.length,
    arquivos: enviados
  };
}

async function restoreDataDoSupabase() {
  fs.mkdirSync(DATA_ROOT, { recursive: true });

  const arquivos = await listarStorageData();
  let restaurados = 0;

  for (const storagePath of arquivos) {
    try {
      const rel = storagePath.replace(`${PREFIX}/`, "");
      const destino = path.join(DATA_ROOT, rel);
      const buffer = await baixarArquivoData(storagePath);

      fs.mkdirSync(path.dirname(destino), { recursive: true });
      fs.writeFileSync(destino, buffer);
      restaurados += 1;
    } catch (error) {
      console.warn("⚠️ Falha ao restaurar " + storagePath + ":", error.message);
    }
  }

  return {
    ok: true,
    restaurados,
    totalStorage: arquivos.length
  };
}

module.exports = {
  statusDadosSupabase,
  syncDataParaSupabase,
  restoreDataDoSupabase
};
