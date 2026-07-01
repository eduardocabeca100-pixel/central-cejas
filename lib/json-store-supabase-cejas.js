require("dotenv").config();

const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(process.cwd(), "data");
const TABELA = "cejas_json_store";

let patchAplicado = false;
let syncTimer = null;

function limparEnv(value) {
  return String(value || "").trim().replace(/^["']|["']$/g, "");
}

function envSupabase() {
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

  return { url, serviceRole };
}

function statusJsonStore() {
  const env = envSupabase();

  return {
    ok: Boolean(env.url && env.serviceRole),
    tabela: TABELA,
    hasUrl: Boolean(env.url),
    hasServiceRole: Boolean(env.serviceRole),
    dataDir: DATA_DIR
  };
}

function assertEnv() {
  const env = envSupabase();

  if (!env.url || !env.serviceRole) {
    throw new Error("Supabase não configurado para JSON Store.");
  }

  return env;
}

function headers(extra = {}) {
  const env = assertEnv();

  return {
    apikey: env.serviceRole,
    Authorization: `Bearer ${env.serviceRole}`,
    "Content-Type": "application/json",
    ...extra
  };
}

async function supabaseRequest(route, options = {}) {
  const env = assertEnv();
  const url = `${env.url.replace(/\/$/, "")}/rest/v1/${route}`;

  const response = await fetch(url, {
    ...options,
    headers: headers(options.headers || {})
  });

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

function chaveDoArquivo(filePath) {
  const abs = path.resolve(filePath);
  const rel = path.relative(DATA_DIR, abs).replace(/\\/g, "/");

  if (rel.startsWith("..")) return null;
  if (!rel.endsWith(".json")) return null;

  return rel;
}

function listarJsonsLocais(dir = DATA_DIR, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".DS_Store") continue;

    const full = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      listarJsonsLocais(full, result);
    } else if (entry.isFile() && entry.name.endsWith(".json")) {
      const chave = chaveDoArquivo(full);
      if (chave) result.push({ full, chave });
    }
  }

  return result;
}

function lerJsonSeguro(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;

    const raw = fs.readFileSync(filePath, "utf8").trim();

    if (!raw) return null;

    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function salvarJsonNoSupabase(chave, dados) {
  await supabaseRequest(TABELA, {
    method: "POST",
    headers: {
      Prefer: "resolution=merge-duplicates"
    },
    body: JSON.stringify({
      chave,
      dados: dados ?? null
    })
  });

  return true;
}

async function syncJsonsParaSupabase() {
  fs.mkdirSync(DATA_DIR, { recursive: true });

  const arquivos = listarJsonsLocais();
  const enviados = [];
  const falhas = [];

  for (const item of arquivos) {
    try {
      const dados = lerJsonSeguro(item.full);

      if (dados === null) continue;

      await salvarJsonNoSupabase(item.chave, dados);
      enviados.push(item.chave);
    } catch (error) {
      falhas.push({
        chave: item.chave,
        erro: error.message
      });
    }
  }

  return {
    ok: falhas.length === 0,
    enviados: enviados.length,
    falhas
  };
}

async function restaurarJsonsDoSupabase() {
  fs.mkdirSync(DATA_DIR, { recursive: true });

  const rows = await supabaseRequest(`${TABELA}?select=chave,dados`, {
    method: "GET"
  });

  const lista = Array.isArray(rows) ? rows : [];
  let restaurados = 0;

  for (const row of lista) {
    if (!row || !row.chave) continue;

    const destino = path.join(DATA_DIR, row.chave);

    fs.mkdirSync(path.dirname(destino), { recursive: true });
    fs.writeFileSync(destino, JSON.stringify(row.dados ?? {}, null, 2), "utf8");
    restaurados += 1;
  }

  return {
    ok: true,
    restaurados,
    totalSupabase: lista.length
  };
}

function agendarSyncJsons() {
  clearTimeout(syncTimer);

  syncTimer = setTimeout(() => {
    syncJsonsParaSupabase().catch(error => {
      console.warn("⚠️ Sync JSON Supabase falhou:", error.message);
    });
  }, 800);
}

function aplicarPatchWriteFileJsonStore() {
  if (patchAplicado) return;
  patchAplicado = true;

  const originalWriteFileSync = fs.writeFileSync;
  const originalWriteFile = fs.writeFile;

  fs.writeFileSync = function patchedWriteFileSync(file, data, ...args) {
    const result = originalWriteFileSync.call(fs, file, data, ...args);

    try {
      const chave = chaveDoArquivo(String(file));
      if (chave) agendarSyncJsons();
    } catch {}

    return result;
  };

  fs.writeFile = function patchedWriteFile(file, data, ...args) {
    const cb = typeof args[args.length - 1] === "function" ? args[args.length - 1] : null;

    const wrappedCb = cb
      ? function (...cbArgs) {
          try {
            const chave = chaveDoArquivo(String(file));
            if (chave) agendarSyncJsons();
          } catch {}

          return cb.apply(this, cbArgs);
        }
      : cb;

    if (cb) {
      args[args.length - 1] = wrappedCb;
    }

    return originalWriteFile.call(fs, file, data, ...args);
  };
}

module.exports = {
  statusJsonStore,
  syncJsonsParaSupabase,
  restaurarJsonsDoSupabase,
  aplicarPatchWriteFileJsonStore
};
