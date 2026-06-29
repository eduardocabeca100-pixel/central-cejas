const fs = require("fs");
const express = require("express");
const path = require("path");
const multer = require("multer");
const {
  supabaseAdmin,
  isSupabaseConfigured,
  SUPABASE_BUCKET
} = require("./supabase");

const BUCKET = process.env.SUPABASE_STORAGE_BUCKET || SUPABASE_BUCKET || "servidor-cejas";
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

const MESES = [
  { numero: "01", nome: "JANEIRO", simples: "JANEIRO", aliases: ["JANEIRO", "JAN"] },
  { numero: "02", nome: "FEVEREIRO", simples: "FEVEREIRO", aliases: ["FEVEREIRO", "FEV"] },
  { numero: "03", nome: "MARÇO", simples: "MARÇO", aliases: ["MARCO", "MARÇO", "MAR"] },
  { numero: "04", nome: "ABRIL", simples: "ABRIL", aliases: ["ABRIL", "ABR"] },
  { numero: "05", nome: "MAIO", simples: "MAIO", aliases: ["MAIO", "MAI"] },
  { numero: "06", nome: "JUNHO", simples: "JUNHO", aliases: ["JUNHO", "JUN"] },
  { numero: "07", nome: "JULHO", simples: "JULHO", aliases: ["JULHO", "JUL"] },
  { numero: "08", nome: "AGOSTO", simples: "AGOSTO", aliases: ["AGOSTO", "AGO"] },
  { numero: "09", nome: "SETEMBRO", simples: "SETEMBRO", aliases: ["SETEMBRO", "SET"] },
  { numero: "10", nome: "OUTUBRO", simples: "OUTUBRO", aliases: ["OUTUBRO", "OUT"] },
  { numero: "11", nome: "NOVEMBRO", simples: "NOVEMBRO", aliases: ["NOVEMBRO", "NOV"] },
  { numero: "12", nome: "DEZEMBRO", simples: "DEZEMBRO", aliases: ["DEZEMBRO", "DEZ"] }
];

const PALAVRAS_DOC = [
  "CONTRATO", "CONTRATOS", "BOLETO", "BOLETOS", "DEMONSTRATIVO", "DEMONSTRATIVOS",
  "RELATORIO", "RELATÓRIO", "ORCAMENTO", "ORÇAMENTO", "PROPOSTA", "RECIBO", "RECIBOS",
  "COMPROVANTE", "COMPROVANTES", "NOTA FISCAL", "NOTAS FISCAIS", "NOTA", "NFS", "NF",
  "EVENTO", "EVENTOS", "ENTIDADE", "ENTIDADES", "ASSINADO", "ASSINADA", "FINAL", "OK",
  "PDF", "DOC", "DOCX", "XLS", "XLSX", "PNG", "JPG", "JPEG"
];

function storageAtivo() {
  return Boolean(isSupabaseConfigured && isSupabaseConfigured() && supabaseAdmin && BUCKET);
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

async function garantirBucket() {
  if (!storageAtivo()) {
    throw new Error("Supabase Storage não configurado no runtime. O sistema aceita NEXT_PUBLIC_SUPABASE_URL ou SUPABASE_URL, mas precisa obrigatoriamente de SUPABASE_SERVICE_ROLE_KEY e SUPABASE_STORAGE_BUCKET.");
  }

  const { data, error } = await supabaseAdmin.storage.listBuckets();

  if (error) {
    throw new Error("Erro ao listar buckets do Supabase: " + error.message);
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

async function uploadBuffer(relativePath, buffer) {
  await garantirBucket();

  const clean = limparPath(relativePath);

  if (!clean) {
    throw new Error("Caminho vazio para upload.");
  }

  const { error } = await supabaseAdmin.storage.from(BUCKET).upload(clean, buffer, {
    upsert: true,
    contentType: contentType(clean),
    cacheControl: "3600"
  });

  if (error) {
    throw new Error("Erro ao enviar para Supabase Storage: " + error.message);
  }

  const local = localPath(clean);
  fs.mkdirSync(path.dirname(local), { recursive: true });
  fs.writeFileSync(local, buffer);

  return {
    ok: true,
    path: clean,
    bucket: BUCKET
  };
}

async function uploadLocal(localFile, relativePath) {
  const buffer = fs.readFileSync(localFile);
  return uploadBuffer(relativePath, buffer);
}

async function downloadBuffer(relativePath) {
  await garantirBucket();

  const clean = limparPath(relativePath);
  const { data, error } = await supabaseAdmin.storage.from(BUCKET).download(clean);

  if (error || !data) return null;

  const arrayBuffer = await data.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

async function listarStorage(prefix = "") {
  await garantirBucket();

  const folder = limparPath(prefix);
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

    if (batch.length < limit) break;
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

  const clean = limparPath(relativePath);

  if (!clean) throw new Error("Caminho vazio.");

  const arquivos = await listarArquivos(clean);
  const targets = arquivos.length ? arquivos : [clean];

  for (let i = 0; i < targets.length; i += 100) {
    const chunk = targets.slice(i, i + 100);
    const { error } = await supabaseAdmin.storage.from(BUCKET).remove(chunk);

    if (error) {
      throw new Error("Erro ao apagar do Supabase Storage: " + error.message);
    }
  }

  const local = localPath(clean);

  if (fs.existsSync(local)) {
    fs.rmSync(local, { recursive: true, force: true });
  }

  return {
    ok: true,
    deleted: targets.length,
    paths: targets
  };
}

async function moverItem(origem, destinoPasta) {
  await garantirBucket();

  const origemClean = limparPath(origem);
  const destinoDir = limparPath(destinoPasta);

  if (!origemClean || !destinoDir) {
    throw new Error("Origem e destino são obrigatórios.");
  }

  const destino = limparPath(path.posix.join(destinoDir, path.posix.basename(origemClean)));

  const arquivos = await listarArquivos(origemClean);

  if (arquivos.length) {
    let movidos = 0;

    for (const arquivo of arquivos) {
      const relDentro = arquivo.replace(origemClean, "").replace(/^\/+/, "");
      const destinoArquivo = limparPath(path.posix.join(destino, relDentro));

      const { error } = await supabaseAdmin.storage.from(BUCKET).move(arquivo, destinoArquivo);

      if (error) {
        throw new Error("Erro ao mover pasta no Supabase Storage: " + error.message);
      }

      movidos += 1;
    }

    const origemLocal = localPath(origemClean);
    const destinoLocal = localPath(destino);

    if (fs.existsSync(origemLocal)) {
      fs.mkdirSync(path.dirname(destinoLocal), { recursive: true });
      fs.renameSync(origemLocal, destinoLocal);
    }

    return {
      ok: true,
      destino,
      movidos
    };
  }

  const { error } = await supabaseAdmin.storage.from(BUCKET).move(origemClean, destino);

  if (error) {
    throw new Error("Erro ao mover arquivo no Supabase Storage: " + error.message);
  }

  const origemLocal = localPath(origemClean);
  const destinoLocal = localPath(destino);

  if (fs.existsSync(origemLocal)) {
    fs.mkdirSync(path.dirname(destinoLocal), { recursive: true });
    fs.renameSync(origemLocal, destinoLocal);
  }

  return {
    ok: true,
    destino,
    movidos: 1
  };
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

function mesItem(mes) {
  const numero = String(mes || "").padStart(2, "0");
  return MESES.find(item => item.numero === numero) || null;
}

function pastaMes(mes) {
  const item = mesItem(mes);
  return item ? `${item.numero} ${item.nome}` : "MES NAO IDENTIFICADO";
}

function pastaMesVerificar(mes) {
  const item = mesItem(mes);
  return item ? item.simples : "SEM MES";
}

function mesPorNome(texto) {
  const normal = normalizar(texto);

  for (const mes of MESES) {
    for (const alias of mes.aliases) {
      const aliasNormal = normalizar(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(^|[^A-Z0-9])${aliasNormal}([^A-Z0-9]|$)`);

      if (re.test(normal)) return mes.numero;
    }
  }

  return "";
}

function detectarData(texto, anoPadrao = "2026") {
  const original = String(texto || "");
  const anoDefault = String(anoPadrao || "2026");

  let match = original.match(/\b(20\d{2})[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ](\d{1,2})\b/);
  if (match) {
    return {
      ok: true,
      ano: match[1],
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[3]).padStart(2, "0"),
      anoExplicito: true
    };
  }

  match = original.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})[.\-_/ ](20\d{2}|\d{2})\b/);
  if (match) {
    return {
      ok: true,
      ano: String(match[3]).length === 2 ? `20${match[3]}` : match[3],
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      anoExplicito: true
    };
  }

  match = original.match(/(?:^|[^\d])(\d{1,2})\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?(?:[^\d]|$)/i);
  if (match) {
    return {
      ok: true,
      ano: match[3] ? (String(match[3]).length === 2 ? `20${match[3]}` : match[3]) : anoDefault,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      anoExplicito: Boolean(match[3])
    };
  }

  match = original.match(/(?:^|[^\d])(\d{1,2})\s+(0?[1-9]|1[0-2])(?:\s+(20\d{2}|\d{2}))?(?:[^\d]|$)/);
  if (match) {
    return {
      ok: true,
      ano: match[3] ? (String(match[3]).length === 2 ? `20${match[3]}` : match[3]) : anoDefault,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      anoExplicito: Boolean(match[3])
    };
  }

  const mesNome = mesPorNome(original);
  const anoCompleto = original.match(/\b(20\d{2})\b/);

  return {
    ok: false,
    ano: anoCompleto ? anoCompleto[1] : anoDefault,
    mes: mesNome,
    dia: "",
    anoExplicito: Boolean(anoCompleto)
  };
}

function removerDatas(texto) {
  return String(texto || "")
    .replace(/\b20\d{2}[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ]\d{1,2}\b/g, " ")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}[.\-_/ ](20\d{2}|\d{2})\b/g, " ")
    .replace(/(^|[^\d])\d{1,2}\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?($|[^\d])/gi, " ")
    .replace(/(^|[^\d])\d{1,2}\s+(0?[1-9]|1[0-2])(?:\s+(20\d{2}|\d{2}))?($|[^\d])/g, " ");
}

function removerPalavrasDoc(texto) {
  let saida = normalizar(texto);

  for (const palavra of PALAVRAS_DOC) {
    const word = normalizar(palavra).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`(^|[^A-Z0-9])${word}([^A-Z0-9]|$)`, "gi");
    saida = saida.replace(re, " ");
  }

  for (const mes of MESES) {
    for (const alias of mes.aliases) {
      const word = normalizar(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(^|[^A-Z0-9])${word}([^A-Z0-9]|$)`, "gi");
      saida = saida.replace(re, " ");
    }
  }

  return saida;
}

function parteIgnorada(parte) {
  const normal = normalizar(parte);

  if (!normal) return true;

  const simples = [
    "SERVIDOR", "DOCUMENTOS", "EVENTOS", "BOLETOS", "DEMONSTRATIVOS", "CONTRATOS",
    "ENTIDADES", "VERIFICAR", "UPLOADS", "ARQUIVOS", "TMP", "TEMP"
  ];

  if (simples.includes(normal)) return true;
  if (/^20\d{2}$/.test(normal)) return true;
  if (/^\d{2}\s+[A-Z]/.test(normal)) return true;

  return MESES.some(m => normal === m.simples || normal === `${m.numero} ${normalizar(m.nome)}`);
}

function limparNomeEvento(originalPath, fileName) {
  const partes = String(originalPath || fileName || "")
    .replace(/\\/g, "/")
    .split("/")
    .filter(Boolean);

  const candidatos = [];

  const baseArquivo = path.basename(String(fileName || partes[partes.length - 1] || "arquivo"), path.extname(String(fileName || "")));
  candidatos.push(baseArquivo);

  for (let i = partes.length - 2; i >= 0; i--) {
    if (!parteIgnorada(partes[i])) {
      candidatos.push(partes[i]);
    }
  }

  for (const candidato of candidatos) {
    let nome = path.basename(String(candidato || ""), path.extname(String(candidato || "")));

    nome = removerDatas(nome);
    nome = removerPalavrasDoc(nome);

    nome = nome
      .replace(/[_\-.]+/g, " ")
      .replace(/\b(DO|DE|DA|DAS|DOS)\b$/gi, " ")
      .replace(/\s+/g, " ")
      .trim();

    if (nome.length >= 2) {
      return slug(nome, "VERIFICAR");
    }
  }

  return "";
}

function nomeArquivoSeguro(fileName) {
  return String(fileName || "arquivo")
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^\.+/, "arquivo") || "arquivo";
}

function destinoInteligente(originalPath, fileName, anoPadrao = "2026") {
  const textoCompleto = `${originalPath || ""} ${fileName || ""}`;
  const data = detectarData(textoCompleto, anoPadrao);
  const titulo = limparNomeEvento(originalPath, fileName);
  const nomeArquivo = nomeArquivoSeguro(fileName || path.basename(originalPath || "arquivo"));

  if (data.ok && data.dia && data.mes && titulo) {
    const mesPasta = pastaMes(data.mes);
    const eventoPasta = slug(`${titulo} ${data.dia}.${data.mes}`);

    if (data.ano && data.ano !== String(anoPadrao || "2026")) {
      return limparPath(`${data.ano}/${mesPasta}/${eventoPasta}/${nomeArquivo}`);
    }

    return limparPath(`${mesPasta}/${eventoPasta}/${nomeArquivo}`);
  }

  const mesVerificar = data.mes ? pastaMesVerificar(data.mes) : "SEM MES";
  return limparPath(`VERIFICAR/${mesVerificar}/${nomeArquivo}`);
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
  if (!app) {
    throw new Error("App Express não informado para registrar rotas do servidor.");
  }

  app.get("/api/servidor/tree", async (_req, res) => {
    try {
      const root = await listarStorage();

      res.json({
        ok: true,
        origem: "supabase-storage-definitivo",
        bucket: BUCKET,
        root
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao carregar servidor pelo Supabase Storage: " + error.message
      });
    }
  });

  app.get("/api/servidor/pastas", async (_req, res) => {
    try {
      const root = await listarStorage();
      const pastas = listarPastas(root)
        .filter(pasta => !pasta.startsWith("VERIFICAR/"))
        .sort((a, b) => a.localeCompare(b, "pt-BR"));

      res.json({
        ok: true,
        pastas
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
      const root = await listarStorage();

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
        return res.status(404).send("Arquivo não encontrado no Supabase Storage.");
      }

      const local = localPath(relativePath);
      fs.mkdirSync(path.dirname(local), { recursive: true });
      fs.writeFileSync(local, buffer);

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

      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const originalRelative = paths[i] || file.originalname;
        const destino = destinoInteligente(originalRelative, file.originalname, anoPadrao);

        await uploadLocal(file.path, destino);

        try {
          fs.rmSync(file.path, { force: true });
        } catch {}

        salvos.push(destino);

        if (destino.startsWith("VERIFICAR/")) verificar.push(destino);
      }

      res.json({
        ok: true,
        saved: salvos.length,
        verificar: verificar.length,
        exemplos: salvos.slice(0, 12),
        message: `${salvos.length} arquivo(s) salvos definitivamente no Supabase Storage. ${verificar.length} foram para VERIFICAR.`
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
      const salvos = [];

      if (!files.length) {
        return res.status(400).json({
          ok: false,
          message: "Nenhum arquivo enviado."
        });
      }

      for (const file of files) {
        const destino = limparPath(path.posix.join(destinoPasta, nomeArquivoSeguro(file.originalname)));
        await uploadLocal(file.path, destino);

        try {
          fs.rmSync(file.path, { force: true });
        } catch {}

        salvos.push(destino);
      }

      res.json({
        ok: true,
        saved: salvos.length,
        exemplos: salvos.slice(0, 12),
        message: `${salvos.length} arquivo(s) salvos definitivamente no Supabase Storage.`
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
      const origem = req.body?.origem || "";
      const destinoPasta = req.body?.destinoPasta || "";

      const result = await moverItem(origem, destinoPasta);

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
      const relativePath = req.query.path || "";
      const result = await deletarItem(relativePath);

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

  app.post("/api/servidor/reorganizar-eventos", express.json({ limit: "2mb" }), async (req, res) => {
    try {
      const anoPadrao = req.body?.anoPadrao || "2026";
      const arquivos = await listarArquivos();
      let movidos = 0;
      let verificar = 0;
      const exemplos = [];

      for (const arquivo of arquivos) {
        if (arquivo.startsWith("VERIFICAR/")) continue;

        const nome = path.posix.basename(arquivo);
        const destino = destinoInteligente(arquivo, nome, anoPadrao);

        if (destino === arquivo) continue;

        try {
          await moverItem(arquivo, path.posix.dirname(destino));
          movidos++;
          if (destino.startsWith("VERIFICAR/")) verificar++;
          if (exemplos.length < 12) exemplos.push({ de: arquivo, para: destino });
        } catch {}
      }

      res.json({
        ok: true,
        movidos,
        verificar,
        exemplos,
        message: `${movidos} arquivo(s) reorganizados no Supabase Storage.`
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao reorganizar: " + error.message
      });
    }
  });

  app.get("/api/servidor/storage-status", async (_req, res) => {
    try {
      const root = await listarStorage();
      const arquivos = achatarArquivos(root);

      res.json({
        ok: true,
        bucket: BUCKET,
        arquivos: arquivos.length,
        origem: "supabase-storage-definitivo"
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
  storageAtivo,
  garantirBucket,
  listarStorage,
  listarArquivos,
  uploadLocal,
  uploadBuffer,
  downloadBuffer,
  deletarItem,
  moverItem,
  destinoInteligente
};
