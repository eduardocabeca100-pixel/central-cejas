require("dotenv").config();

const fs = require("fs");
const path = require("path");
const express = require("express");
const multer = require("multer");

const TMP_ROOT = path.join(process.cwd(), "uploads", "tmp-servidor-supabase");
fs.mkdirSync(TMP_ROOT, { recursive: true });

const uploadServidorSupabase = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, TMP_ROOT),
    filename: (_req, file, cb) => {
      const safe =
        Date.now() +
        "-" +
        Math.random().toString(16).slice(2) +
        "-" +
        String(file.originalname || "arquivo").replace(/[^a-zA-Z0-9._-]/g, "-");

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
    keyType:
      env.serviceRole && env.serviceRole.startsWith("eyJ") && env.serviceRole.split(".").length === 3
        ? "legacy-jwt"
        : env.serviceRole && env.serviceRole.startsWith("sb_secret_")
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

function storageHeaders(extra = {}) {
  const env = assertStorageEnv();

  return {
    apikey: env.serviceRole,
    Authorization: `Bearer ${env.serviceRole}`,
    ...extra
  };
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

function nomeArquivoSeguro(fileName) {
  return String(fileName || "arquivo")
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^\.+/, "arquivo") || "arquivo";
}

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

const MESES = [
  ["01", "JANEIRO"],
  ["02", "FEVEREIRO"],
  ["03", "MARÇO"],
  ["04", "ABRIL"],
  ["05", "MAIO"],
  ["06", "JUNHO"],
  ["07", "JULHO"],
  ["08", "AGOSTO"],
  ["09", "SETEMBRO"],
  ["10", "OUTUBRO"],
  ["11", "NOVEMBRO"],
  ["12", "DEZEMBRO"]
];

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
  if (m) {
    return {
      ok: true,
      ano: m[1],
      mes: String(m[2]).padStart(2, "0"),
      dia: String(m[3]).padStart(2, "0")
    };
  }

  m = original.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})[.\-_/ ](20\d{2}|\d{2})\b/);
  if (m) {
    return {
      ok: true,
      ano: String(m[3]).length === 2 ? `20${m[3]}` : m[3],
      mes: String(m[2]).padStart(2, "0"),
      dia: String(m[1]).padStart(2, "0")
    };
  }

  m = original.match(/(?:^|[^\d])(\d{1,2})\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?(?:[^\d]|$)/i);
  if (m) {
    return {
      ok: true,
      ano: m[3] ? (String(m[3]).length === 2 ? `20${m[3]}` : m[3]) : anoPadrao,
      mes: String(m[2]).padStart(2, "0"),
      dia: String(m[1]).padStart(2, "0")
    };
  }

  return {
    ok: false,
    ano: anoPadrao,
    mes: "",
    dia: ""
  };
}

function limparNomeEvento(originalPath, fileName) {
  let base = path.basename(
    String(fileName || originalPath || "arquivo"),
    path.extname(String(fileName || originalPath || ""))
  );

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

async function uploadBuffer(relativePath, buffer) {
  const env = assertStorageEnv();
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

  return {
    ok: true,
    path: clean,
    bucket: env.bucket
  };
}

async function uploadLocal(localFile, relativePath) {
  const buffer = fs.readFileSync(localFile);
  return uploadBuffer(relativePath, buffer);
}

async function downloadBuffer(relativePath) {
  const env = assertStorageEnv();
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

async function listarObjetosPlanos() {
  const env = assertStorageEnv();
  const todos = [];
  let offset = 0;
  const limit = 1000;

  while (true) {
    const batch = await storageRequest(`/object/list/${encodeURIComponent(env.bucket)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        prefix: "",
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

      const isFile = item.metadata && typeof item.metadata.size === "number";

      if (isFile) {
        todos.push({
          type: "file",
          name: item.name,
          path: item.name,
          size: Number(item.metadata.size || 0),
          updatedAt: item.updated_at || item.created_at || new Date().toISOString()
        });
      }
    }

    if (items.length < limit) break;
    offset += limit;
  }

  return todos;
}

function montarArvoreDeArquivos(files) {
  const root = [];

  function getFolder(children, name, currentPath) {
    let folder = children.find(item => item.type === "folder" && item.name === name);

    if (!folder) {
      folder = {
        type: "folder",
        name,
        path: currentPath,
        size: 0,
        updatedAt: new Date().toISOString(),
        children: []
      };

      children.push(folder);
    }

    return folder;
  }

  for (const file of files) {
    const parts = limparPath(file.path).split("/").filter(Boolean);
    let children = root;
    let current = "";

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      current = current ? `${current}/${part}` : part;

      if (i === parts.length - 1) {
        children.push({
          ...file,
          name: part,
          path: current
        });
      } else {
        const folder = getFolder(children, part, current);
        children = folder.children;
      }
    }
  }

  function sortTree(items) {
    items.sort((a, b) => {
      if (a.type !== b.type) return a.type === "folder" ? -1 : 1;
      return a.name.localeCompare(b.name, "pt-BR");
    });

    for (const item of items) {
      if (item.children) sortTree(item.children);
    }
  }

  sortTree(root);

  return root;
}

async function listarStorage() {
  const files = await listarObjetosPlanos();
  return montarArvoreDeArquivos(files);
}

function achatarArquivos(items, result = []) {
  for (const item of items || []) {
    if (item.type === "file") result.push(item.path);
    if (item.children) achatarArquivos(item.children, result);
  }

  return result;
}

async function listarArquivos() {
  const files = await listarObjetosPlanos();
  return files.map(file => file.path);
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

async function deletarItem(relativePath) {
  const env = assertStorageEnv();
  const clean = limparPath(relativePath);

  if (!clean) throw new Error("Caminho vazio.");

  const arquivos = (await listarArquivos()).filter(pathItem => {
    return pathItem === clean || pathItem.startsWith(clean + "/");
  });

  const targets = arquivos.length ? arquivos : [clean];

  for (let i = 0; i < targets.length; i += 100) {
    const chunk = targets.slice(i, i + 100);

    await storageRequest(`/object/${encodeURIComponent(env.bucket)}`, {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        prefixes: chunk
      })
    });
  }

  return {
    ok: true,
    deleted: targets.length,
    paths: targets
  };
}

async function moverArquivo(origem, destino) {
  const env = assertStorageEnv();

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

  if (!origemClean || !destinoDir) {
    throw new Error("Origem e destino são obrigatórios.");
  }

  const arquivos = (await listarArquivos()).filter(pathItem => {
    return pathItem === origemClean || pathItem.startsWith(origemClean + "/");
  });

  const destinoBase = limparPath(path.posix.join(destinoDir, path.posix.basename(origemClean)));

  if (arquivos.length > 1) {
    let movidos = 0;

    for (const arquivo of arquivos) {
      const relDentro = arquivo.replace(origemClean, "").replace(/^\/+/, "");
      const destinoArquivo = limparPath(path.posix.join(destinoBase, relDentro));

      await moverArquivo(arquivo, destinoArquivo);
      movidos += 1;
    }

    return {
      ok: true,
      destino: destinoBase,
      movidos
    };
  }

  const destino = limparPath(path.posix.join(destinoDir, path.posix.basename(origemClean)));
  await moverArquivo(origemClean, destino);

  return {
    ok: true,
    destino,
    movidos: 1
  };
}


// CEJAS_LISTAGEM_ESTAVEL_SERVIDOR_START
async function listarArquivosComRetryCejas(tentativas = 3) {
  let ultimoErro = null;

  for (let i = 1; i <= tentativas; i++) {
    try {
      const arquivos = await listarArquivosComRetryCejas(3);

      return Array.isArray(arquivos) ? arquivos : [];
    } catch (error) {
      ultimoErro = error;
      await new Promise(resolve => setTimeout(resolve, 450 * i));
    }
  }

  throw ultimoErro || new Error("Falha ao listar arquivos.");
}

async function listarStorageEstavelCejas() {
  const arquivos = await listarArquivosComRetryCejas(3);
  return montarArvoreDeArquivos(
    arquivos.map(pathItem => ({
      type: "file",
      name: path.posix.basename(pathItem),
      path: pathItem,
      size: 0,
      updatedAt: new Date().toISOString()
    }))
  );
}

function headersNoCacheCejas(res) {
  headersNoCacheCejas(res);
  res.set("Pragma", "no-cache");
  res.set("Expires", "0");
}
// CEJAS_LISTAGEM_ESTAVEL_SERVIDOR_END



async function apagarTudoServidorCejas() {
  const arquivos = await listarArquivosComRetryCejas(3);

  if (!arquivos.length) {
    return {
      ok: true,
      deleted: 0,
      message: "Servidor já estava vazio."
    };
  }

  const env = assertStorageEnv();
  let deleted = 0;
  const falhas = [];

  for (let i = 0; i < arquivos.length; i += 100) {
    const chunk = arquivos.slice(i, i + 100);

    try {
      await storageRequest(`/object/${encodeURIComponent(env.bucket)}`, {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prefixes: chunk
        })
      });

      deleted += chunk.length;
    } catch (error) {
      falhas.push({
        lote: `${i + 1}-${Math.min(i + 100, arquivos.length)}`,
        erro: error.message
      });
    }
  }

  return {
    ok: falhas.length === 0,
    partial: falhas.length > 0 && deleted > 0,
    deleted,
    failedBatches: falhas.length,
    falhas,
    message: falhas.length
      ? `${deleted} arquivo(s) apagados. ${falhas.length} lote(s) falharam.`
      : `${deleted} arquivo(s) apagados definitivamente do Supabase Storage.`
  };
}


function registrarRotasServidorSupabaseDefinitivo(app) {
  app.get("/api/debug/storage-runtime", (_req, res) => {
    res.json({
      ok: true,
      storage: getSupabaseRuntimeStatus()
    });
  });

  app.get("/api/servidor/tree", async (_req, res) => {
    try {
      const root = await listarStorageEstavelCejas();

      headersNoCacheCejas(res);

      res.json({
        ok: true,
        origem: "supabase-storage-only",
        bucket: getRuntimeEnv().bucket,
        root
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao carregar servidor: " + error.message
      });
    }
  });

  app.get("/api/servidor/pastas", async (_req, res) => {
    try {
      const root = await listarStorageEstavelCejas();

      headersNoCacheCejas(res);

      res.json({
        ok: true,
        pastas: listarPastas(root).filter(p => !p.startsWith("VERIFICAR/"))
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao listar pastas: " + error.message
      });
    }
  });

  app.get("/api/servidor/verificar", async (_req, res) => {
    try {
      const root = await listarStorageEstavelCejas();

      headersNoCacheCejas(res);

      res.json({
        ok: true,
        itens: listarVerificar(root)
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao listar VERIFICAR: " + error.message
      });
    }
  });

  app.get("/api/servidor/arquivo", async (req, res) => {
    try {
      const relativePath = limparPath(req.query.path || "");
      const buffer = await downloadBuffer(relativePath);

      if (!buffer) {
        return res.status(404).send("Arquivo não encontrado.");
      }

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
        return res.status(400).json({
          ok: false,
          message: "Nenhum arquivo enviado."
        });
      }

      const salvos = [];
      const verificar = [];
      const falhas = [];

      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const originalRelative = paths[i] || file.originalname;
        const destino = destinoInteligente(originalRelative, file.originalname, anoPadrao);

        try {
          await uploadLocal(file.path, destino);
          salvos.push(destino);

          if (destino.startsWith("VERIFICAR/")) {
            verificar.push(destino);
          }
        } catch (error) {
          falhas.push({
            arquivo: file.originalname,
            destino,
            erro: error.message
          });
        } finally {
          try { fs.rmSync(file.path, { force: true }); } catch {}
        }
      }

      res.json({
        ok: falhas.length === 0,
        partial: falhas.length > 0 && salvos.length > 0,
        saved: salvos.length,
        failed: falhas.length,
        verificar: verificar.length,
        exemplos: salvos.slice(0, 12),
        falhas: falhas.slice(0, 50),
        message: falhas.length
          ? `${salvos.length} arquivo(s) salvos. ${falhas.length} arquivo(s) falharam.`
          : `${salvos.length} arquivo(s) salvos no Supabase Storage. ${verificar.length} foram para VERIFICAR.`
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro no upload inteligente: " + error.message
      });
    }
  });

  app.post("/api/servidor/upload", uploadServidorSupabase.array("arquivos"), async (req, res) => {
    try {
      const files = req.files || [];
      const destinoPasta = limparPath(req.body.destino || "");

      if (!files.length) {
        return res.status(400).json({
          ok: false,
          message: "Nenhum arquivo enviado."
        });
      }

      const salvos = [];
      const falhas = [];

      for (const file of files) {
        const destino = limparPath(path.posix.join(destinoPasta, nomeArquivoSeguro(file.originalname)));

        try {
          await uploadLocal(file.path, destino);
          salvos.push(destino);
        } catch (error) {
          falhas.push({
            arquivo: file.originalname,
            destino,
            erro: error.message
          });
        } finally {
          try { fs.rmSync(file.path, { force: true }); } catch {}
        }
      }

      res.json({
        ok: falhas.length === 0,
        partial: falhas.length > 0 && salvos.length > 0,
        saved: salvos.length,
        failed: falhas.length,
        exemplos: salvos.slice(0, 12),
        falhas: falhas.slice(0, 50),
        message: falhas.length
          ? `${salvos.length} arquivo(s) salvos. ${falhas.length} arquivo(s) falharam.`
          : `${salvos.length} arquivo(s) salvos no Supabase Storage.`
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao enviar arquivo: " + error.message
      });
    }
  });

  app.post("/api/servidor/mover", express.json({ limit: "2mb" }), async (req, res) => {
    try {
      const result = await moverItem(req.body?.origem || "", req.body?.destinoPasta || "");

      res.json({
        ok: true,
        ...result,
        message: "Item movido no Supabase Storage."
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao mover item: " + error.message
      });
    }
  });

  app.delete("/api/servidor/item", async (req, res) => {
    try {
      const result = await deletarItem(req.query.path || "");

      res.json({
        ok: true,
        ...result,
        message: `Item apagado definitivamente do Supabase Storage. Arquivos removidos: ${result.deleted}.`
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao apagar definitivamente: " + error.message
      });
    }
  });


  app.delete("/api/servidor/tudo", express.json({ limit: "2mb" }), async (req, res) => {
    try {
      const confirmacao = String(req.body?.confirmacao || req.query.confirmacao || "").trim();

      if (confirmacao !== "APAGAR TUDO") {
        return res.status(400).json({
          ok: false,
          message: "Confirmação inválida. Digite exatamente: APAGAR TUDO"
        });
      }

      const result = await apagarTudoServidorCejas();

      headersNoCacheCejas(res);

      res.json({
        ...result,
        bucket: getRuntimeEnv().bucket
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao apagar tudo: " + error.message
      });
    }
  });

  app.get("/api/servidor/storage-status", async (req, res) => {
    try {
      const arquivos = await listarArquivosComRetryCejas(3);
      const detalhado = String(req.query.detalhado || "") === "1";

      headersNoCacheCejas(res);

      res.json({
        ok: true,
        bucket: getRuntimeEnv().bucket,
        arquivos: arquivos.length,
        origem: "supabase-storage-only",
        lista: detalhado ? arquivos.slice(0, 1000) : undefined
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });
}

module.exports = {
  registrarRotasServidorSupabaseDefinitivo,
  uploadServidorSupabase,
  storageAtivo: () => getSupabaseRuntimeStatus().ok,
  garantirBucket: async () => assertStorageEnv(),
  listarStorage,
  listarArquivos,
  uploadLocal,
  uploadBuffer,
  downloadBuffer,
  deletarItem,
  moverItem,
  destinoInteligente,
  getSupabaseRuntimeStatus,
  apagarTudoServidorCejas
};
