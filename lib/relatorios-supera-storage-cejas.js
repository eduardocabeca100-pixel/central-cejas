require("dotenv").config();

const fs = require("fs");
const path = require("path");

const BUCKET_PADRAO = "servidor-cejas";
const STORAGE_PREFIX = "_SISTEMA/relatorios-supera";

const PASTAS_RELATORIO = [
  {
    nome: "relatorios",
    local: path.join(process.cwd(), "uploads", "relatorios"),
    storage: `${STORAGE_PREFIX}/relatorios`
  },
  {
    nome: "supera",
    local: path.join(process.cwd(), "uploads", "supera"),
    storage: `${STORAGE_PREFIX}/supera`
  },
  {
    nome: "importar-relatorio",
    local: path.join(process.cwd(), "uploads", "importar-relatorio"),
    storage: `${STORAGE_PREFIX}/importar-relatorio`
  }
];

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
    BUCKET_PADRAO;

  return { url, serviceRole, bucket };
}

function statusRelatoriosSuperaStorage() {
  const env = getEnv();

  return {
    ok: Boolean(env.url && env.serviceRole && env.bucket),
    bucket: env.bucket,
    prefix: STORAGE_PREFIX,
    hasUrl: Boolean(env.url),
    hasServiceRole: Boolean(env.serviceRole),
    hasBucket: Boolean(env.bucket)
  };
}

function assertEnv() {
  const env = getEnv();

  if (!env.url || !env.serviceRole || !env.bucket) {
    throw new Error("Supabase Storage não configurado para relatórios do Supera.");
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

function mimePorArquivo(file = "") {
  const ext = path.extname(file).toLowerCase();

  const map = {
    ".pdf": "application/pdf",
    ".txt": "text/plain; charset=utf-8",
    ".json": "application/json",
    ".csv": "text/csv",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".xls": "application/vnd.ms-excel"
  };

  return map[ext] || "application/octet-stream";
}

async function storageRequest(route, options = {}) {
  const env = assertEnv();
  const url = `${env.url.replace(/\/$/, "")}/storage/v1${route}`;

  const response = await fetch(url, {
    ...options,
    headers: headers(options.headers || {})
  });

  if (options.raw) {
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(text || `HTTP ${response.status}`);
    }

    const arrayBuffer = await response.arrayBuffer();
    return Buffer.from(arrayBuffer);
  }

  const text = await response.text();

  if (!response.ok) {
    throw new Error(text || `HTTP ${response.status}`);
  }

  if (!text) return null;

  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function listarArquivosLocais(dir, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".DS_Store") continue;

    const full = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      listarArquivosLocais(full, result);
    } else if (entry.isFile()) {
      result.push(full);
    }
  }

  return result;
}

async function uploadArquivoStorage(localFile, storagePath) {
  const env = assertEnv();
  const buffer = fs.readFileSync(localFile);

  await storageRequest(`/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(storagePath)}`, {
    method: "POST",
    headers: {
      "Content-Type": mimePorArquivo(localFile),
      "Cache-Control": "3600",
      "x-upsert": "true"
    },
    body: buffer
  });

  return storagePath;
}

async function syncRelatoriosSuperaParaStorage() {
  const enviados = [];
  const falhas = [];

  for (const pasta of PASTAS_RELATORIO) {
    fs.mkdirSync(pasta.local, { recursive: true });

    const arquivos = listarArquivosLocais(pasta.local);

    for (const arquivo of arquivos) {
      try {
        const rel = path.relative(pasta.local, arquivo).replace(/\\/g, "/");
        const destino = limparPath(`${pasta.storage}/${rel}`);

        await uploadArquivoStorage(arquivo, destino);
        enviados.push(destino);
      } catch (error) {
        falhas.push({
          arquivo,
          erro: error.message
        });
      }
    }
  }

  return {
    ok: falhas.length === 0,
    enviados: enviados.length,
    falhas
  };
}

async function listarStorageRecursivo(prefix) {
  const env = assertEnv();
  const todos = [];
  const visitados = new Set();

  async function listar(folder) {
    folder = limparPath(folder);

    if (visitados.has(folder)) return;
    visitados.add(folder);

    let offset = 0;
    const limit = 1000;

    while (true) {
      const batch = await storageRequest(`/object/list/${encodeURIComponent(env.bucket)}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
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
          await listar(rel);
        }
      }

      if (items.length < limit) break;
      offset += limit;
    }
  }

  await listar(prefix);

  return todos;
}

async function baixarArquivoStorage(storagePath) {
  const env = assertEnv();

  return storageRequest(`/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(storagePath)}`, {
    method: "GET",
    raw: true
  });
}

async function restaurarRelatoriosSuperaDoStorage() {
  let restaurados = 0;
  const falhas = [];

  for (const pasta of PASTAS_RELATORIO) {
    fs.mkdirSync(pasta.local, { recursive: true });

    const arquivos = await listarStorageRecursivo(pasta.storage);

    for (const storagePath of arquivos) {
      try {
        const rel = storagePath.replace(`${pasta.storage}/`, "");
        const destino = path.join(pasta.local, rel);

        const buffer = await baixarArquivoStorage(storagePath);

        fs.mkdirSync(path.dirname(destino), { recursive: true });
        fs.writeFileSync(destino, buffer);

        restaurados += 1;
      } catch (error) {
        falhas.push({
          storagePath,
          erro: error.message
        });
      }
    }
  }

  return {
    ok: falhas.length === 0,
    restaurados,
    falhas
  };
}

async function listarRelatoriosSuperaStorageStatus() {
  const arquivos = await listarStorageRecursivo(STORAGE_PREFIX);

  return {
    ok: true,
    bucket: getEnv().bucket,
    prefix: STORAGE_PREFIX,
    arquivos: arquivos.length,
    lista: arquivos.slice(0, 100)
  };
}

function registrarRotasRelatoriosSuperaStorage(app) {
  if (!app || app.__CEJAS_RELATORIOS_SUPERA_STORAGE__) return;

  app.__CEJAS_RELATORIOS_SUPERA_STORAGE__ = true;

  app.get("/api/sistema/relatorios-supera-storage-status", async (_req, res) => {
    try {
      const result = await listarRelatoriosSuperaStorageStatus();
      res.set("Cache-Control", "no-store");
      res.json(result);
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message,
        status: statusRelatoriosSuperaStorage()
      });
    }
  });

  app.post("/api/sistema/relatorios-supera-sync", async (_req, res) => {
    try {
      const result = await syncRelatoriosSuperaParaStorage();
      res.json({
        ok: result.ok,
        ...result
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.post("/api/sistema/relatorios-supera-restore", async (_req, res) => {
    try {
      const result = await restaurarRelatoriosSuperaDoStorage();
      res.json({
        ok: result.ok,
        ...result
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.use((req, res, next) => {
    const metodoMuda = ["POST", "PUT", "PATCH", "DELETE"].includes(req.method);

    const rotaRelatorio =
      req.path.startsWith("/api/importar-relatorio") ||
      req.path.startsWith("/api/relatorio") ||
      req.path.startsWith("/api/supera");

    if (metodoMuda && rotaRelatorio) {
      res.on("finish", () => {
        if (res.statusCode < 400) {
          setTimeout(() => {
            syncRelatoriosSuperaParaStorage().catch(error => {
              console.warn("⚠️ Sync relatórios Supera Storage falhou:", error.message);
            });
          }, 1500);
        }
      });
    }

    next();
  });
}

module.exports = {
  statusRelatoriosSuperaStorage,
  syncRelatoriosSuperaParaStorage,
  restaurarRelatoriosSuperaDoStorage,
  listarRelatoriosSuperaStorageStatus,
  registrarRotasRelatoriosSuperaStorage
};
