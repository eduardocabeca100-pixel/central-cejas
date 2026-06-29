#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "orcamentos.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e orcamentos.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/servidor-storage-orcamento-pdf-$STAMP"
mkdir -p "$BACKUP_DIR" lib scripts
cp server.js orcamentos.html package.json .env.example .gitignore "$BACKUP_DIR/" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true
[ -d uploads ] && cp -R uploads "$BACKUP_DIR/uploads" 2>/dev/null || true
[ -d lib ] && cp -R lib "$BACKUP_DIR/lib" 2>/dev/null || true
[ -d scripts ] && cp -R scripts "$BACKUP_DIR/scripts" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

cat > lib/servidor-supabase-definitivo.js <<'EOF'
const fs = require("fs");
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
    throw new Error("Supabase Storage não configurado. Confira SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e SUPABASE_STORAGE_BUCKET.");
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
EOF

python3 <<'PY'
from pathlib import Path
import re

p = Path("server.js")
s = p.read_text()

# Adiciona require definitivo.
require_line = 'const { registrarRotasServidorSupabaseDefinitivo } = require("./lib/servidor-supabase-definitivo");'
if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace('const path = require("path");', 'const path = require("path");\n' + require_line, 1)
    else:
        s = require_line + "\n" + s

# Bloqueia rotas antigas do servidor para não sobrescrever as novas.
route_patterns = [
    r'\napp\.get\("/api/servidor/tree"[\s\S]*?\n\}\);',
    r'\napp\.get\("/api/servidor/pastas"[\s\S]*?\n\}\);',
    r'\napp\.get\("/api/servidor/verificar"[\s\S]*?\n\}\);',
    r'\napp\.get\("/api/servidor/arquivo"[\s\S]*?\n\}\);',
    r'\napp\.post\("/api/servidor/upload-inteligente"[\s\S]*?\n\}\);',
    r'\napp\.post\("/api/servidor/upload"[\s\S]*?\n\}\);',
    r'\napp\.post\("/api/servidor/mover"[\s\S]*?\n\}\);',
    r'\napp\.delete\("/api/servidor/item"[\s\S]*?\n\}\);',
    r'\napp\.post\("/api/servidor/reorganizar-eventos"[\s\S]*?\n\}\);',
]

for pattern in route_patterns:
    s = re.sub(pattern, lambda m: "\n/* ROTA ANTIGA SERVIDOR DESATIVADA PELO PATCH SUPABASE DEFINITIVO\n" + m.group(0) + "\n*/", s)

# Registra rotas definitivas depois de const app = express().
marker = "const app = express();"
register = "\nregistrarRotasServidorSupabaseDefinitivo(app);\n"

if "registrarRotasServidorSupabaseDefinitivo(app);" not in s:
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express();")
    s = s.replace(marker, marker + register, 1)

p.write_text(s)
PY

cat > scripts/check-servidor-definitivo.js <<'EOF'
const { garantirBucket, listarArquivos } = require("../lib/servidor-supabase-definitivo");

(async () => {
  await garantirBucket();
  const arquivos = await listarArquivos();

  console.log("✅ Servidor conectado ao Supabase Storage definitivo.");
  console.log("Arquivos no Storage:", arquivos.length);
  arquivos.slice(0, 30).forEach(item => console.log("-", item));
})().catch(error => {
  console.error("❌ Erro no servidor definitivo:", error.message);
  process.exit(1);
});
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["servidor:check-definitivo"] = "node scripts/check-servidor-definitivo.js"
p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("orcamentos.html")
s = p.read_text()

# Remove patches anteriores de PDF para não brigar.
s = re.sub(r"\s*/\* CEJAS_ORCAMENTO_PDF_A4_COMPLETO_START \*/[\s\S]*?/\* CEJAS_ORCAMENTO_PDF_A4_COMPLETO_END \*/", "", s)
s = re.sub(r"\s*<script>\s*// CEJAS_ORCAMENTO_PDF_A4_COMPLETO_JS_START[\s\S]*?// CEJAS_ORCAMENTO_PDF_A4_COMPLETO_JS_END\s*</script>", "", s)

css = r'''
    /* CEJAS_ORCAMENTO_PDF_A4_COMPLETO_START */

    .cronometro,
    .countdown,
    .countdown-card,
    .timer-card,
    .timer-box,
    .budget-timer,
    .orcamento-timer,
    .validade-timer,
    #cronometro,
    #countdown,
    #budgetTimer,
    #orcamentoTimer {
      display: none !important;
      visibility: hidden !important;
    }

    .cejas-pdf-a4-root {
      position: fixed !important;
      left: -100000px !important;
      top: 0 !important;
      width: 210mm !important;
      background: #ffffff !important;
      padding: 0 !important;
      margin: 0 !important;
      z-index: -1 !important;
      pointer-events: none !important;
      overflow: visible !important;
    }

    .cejas-pdf-a4-page {
      width: 210mm !important;
      min-height: 297mm !important;
      background: #ffffff !important;
      color: #111827 !important;
      padding: 14mm 12mm 12mm !important;
      margin: 0 !important;
      box-shadow: none !important;
      border-radius: 0 !important;
      transform: none !important;
      display: flex !important;
      flex-direction: column !important;
      font-family: Arial, Helvetica, sans-serif !important;
      font-size: 9.4px !important;
      line-height: 1.28 !important;
      box-sizing: border-box !important;
    }

    .cejas-pdf-a4-page * {
      box-sizing: border-box !important;
    }

    .cejas-pdf-a4-page .doc-header {
      display: grid !important;
      grid-template-columns: 35mm 1fr !important;
      align-items: start !important;
      gap: 8mm !important;
      padding-bottom: 8mm !important;
      border-bottom: 1.4px solid #111827 !important;
      margin-bottom: 4mm !important;
    }

    .cejas-pdf-a4-page .cejas-logo img {
      width: 24mm !important;
      height: auto !important;
    }

    .cejas-pdf-a4-page .doc-company {
      text-align: right !important;
      font-size: 8.5px !important;
      line-height: 1.23 !important;
      color: #374151 !important;
    }

    .cejas-pdf-a4-page .doc-company h1 {
      font-size: 10.8px !important;
      line-height: 1.1 !important;
      margin: 0 0 4px !important;
      color: #111827 !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
    }

    .cejas-pdf-a4-page .doc-meta {
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      gap: 8px !important;
      margin: 0 0 4mm !important;
      font-size: 9px !important;
      color: #374151 !important;
    }

    .cejas-pdf-a4-page .doc-title {
      background: #f3f4f6 !important;
      border: 1px solid #d1d5db !important;
      padding: 2.8mm 4mm !important;
      margin: 0 0 4.5mm !important;
      text-align: center !important;
      text-transform: uppercase !important;
      letter-spacing: .28em !important;
      font-size: 10px !important;
      font-weight: 900 !important;
      color: #111827 !important;
    }

    .cejas-pdf-a4-page .doc-fields {
      border: 1px solid #d1d5db !important;
      padding: 4mm !important;
      margin: 0 0 4.5mm !important;
      font-size: 9.3px !important;
      line-height: 1.65 !important;
    }

    .cejas-pdf-a4-page .doc-fields p {
      display: grid !important;
      grid-template-columns: 25mm 1fr !important;
      gap: 4mm !important;
      margin: 0 !important;
    }

    .cejas-pdf-a4-page .doc-period-title {
      border-left: 4px solid #64748b !important;
      padding-left: 8px !important;
      margin: 0 0 2.7mm !important;
      font-size: 9px !important;
      font-weight: 900 !important;
      text-transform: uppercase !important;
      color: #111827 !important;
    }

    .cejas-pdf-a4-page .period {
      margin: 0 0 4mm !important;
    }

    .cejas-pdf-a4-page table {
      width: 100% !important;
      border-collapse: collapse !important;
      table-layout: fixed !important;
      font-size: 8px !important;
      margin: 0 !important;
    }

    .cejas-pdf-a4-page th,
    .cejas-pdf-a4-page td {
      border: 1px solid #d1d5db !important;
      padding: 3.5px 4px !important;
      color: #111827 !important;
      line-height: 1.16 !important;
      vertical-align: top !important;
      overflow-wrap: break-word !important;
      word-break: normal !important;
    }

    .cejas-pdf-a4-page th {
      background: #f3f4f6 !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-a4-page th:nth-child(1),
    .cejas-pdf-a4-page td:nth-child(1) {
      width: 8mm !important;
      text-align: center !important;
    }

    .cejas-pdf-a4-page th:nth-child(2),
    .cejas-pdf-a4-page td:nth-child(2) {
      width: 32mm !important;
    }

    .cejas-pdf-a4-page th:nth-child(3),
    .cejas-pdf-a4-page td:nth-child(3) {
      width: 10mm !important;
      text-align: center !important;
    }

    .cejas-pdf-a4-page th:nth-child(5),
    .cejas-pdf-a4-page td:nth-child(5),
    .cejas-pdf-a4-page th:nth-child(6),
    .cejas-pdf-a4-page td:nth-child(6) {
      width: 23mm !important;
      text-align: right !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-a4-page .subtotal td {
      background: #f8fafc !important;
      font-weight: 900 !important;
      font-style: italic !important;
    }

    .cejas-pdf-a4-page .total-general {
      width: 66mm !important;
      margin: 3mm 0 5mm auto !important;
      border: 1.4px solid #111827 !important;
      padding: 3mm 4mm !important;
      display: flex !important;
      justify-content: space-between !important;
      align-items: center !important;
      font-size: 9.5px !important;
      font-weight: 900 !important;
      color: #111827 !important;
    }

    .cejas-pdf-a4-page .total-general strong {
      font-size: 13px !important;
      color: #111827 !important;
      white-space: nowrap !important;
    }

    .cejas-pdf-a4-page .conditions {
      margin-top: auto !important;
      margin-bottom: 5mm !important;
      border: 1px solid #d1d5db !important;
      background: #f8fafc !important;
    }

    .cejas-pdf-a4-page .conditions h4 {
      background: #e5e7eb !important;
      padding: 2.7mm 4mm !important;
      font-size: 7.5px !important;
      letter-spacing: .18em !important;
      color: #111827 !important;
      text-transform: uppercase !important;
      font-weight: 900 !important;
    }

    .cejas-pdf-a4-page .conditions div {
      padding: 3.5mm 4mm !important;
      font-size: 8.2px !important;
      line-height: 1.38 !important;
      color: #374151 !important;
    }

    .cejas-pdf-a4-page .conditions p {
      margin: 0 0 2mm !important;
    }

    .cejas-pdf-a4-page .warning {
      font-weight: 900 !important;
      color: #111827 !important;
      border-top: 1px solid #e5e7eb !important;
      border-bottom: 1px solid #e5e7eb !important;
      padding: 4px 0 !important;
      margin: 4px 0 !important;
      text-transform: uppercase !important;
    }

    .cejas-pdf-a4-page .signature {
      display: flex !important;
      justify-content: space-between !important;
      align-items: flex-end !important;
      gap: 18px !important;
      font-size: 8.6px !important;
      line-height: 1.28 !important;
      color: #374151 !important;
      margin-top: 0 !important;
    }

    .cejas-pdf-a4-page .signature strong {
      display: block !important;
      color: #111827 !important;
      font-size: 9.5px !important;
      margin: 4px 0 1px !important;
    }

    .cejas-pdf-a4-page .system-mark {
      font-size: 6.7px !important;
      color: #9ca3af !important;
      text-transform: uppercase !important;
      white-space: nowrap !important;
    }

    @media print {
      @page {
        size: A4;
        margin: 0;
      }
    }

    /* CEJAS_ORCAMENTO_PDF_A4_COMPLETO_END */
'''

if "</style>" not in s:
    raise SystemExit("❌ Não encontrei </style> em orcamentos.html.")

s = s.replace("</style>", css + "\n  </style>", 1)

js = r'''
<script>
// CEJAS_ORCAMENTO_PDF_A4_COMPLETO_JS_START
(function () {
  if (window.__CEJAS_ORCAMENTO_PDF_A4_COMPLETO__) return;
  window.__CEJAS_ORCAMENTO_PDF_A4_COMPLETO__ = true;

  function carregarScript(src) {
    return new Promise((resolve, reject) => {
      const existente = [...document.scripts].find((script) => script.src && script.src.includes(src));
      if (existente) return resolve();

      const script = document.createElement("script");
      script.src = src;
      script.onload = resolve;
      script.onerror = () => reject(new Error("Não foi possível carregar " + src));
      document.head.appendChild(script);
    });
  }

  async function garantirPDFLibs() {
    if (!window.html2canvas) {
      await carregarScript("https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js");
    }

    if (!window.jspdf || !window.jspdf.jsPDF) {
      await carregarScript("https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js");
    }
  }

  function isDocument(el) {
    const text = String(el && el.innerText || "").toUpperCase();

    return text.includes("DOCUMENTO AUXILIAR DE VENDA") ||
      text.includes("ORÇAMENTO LOCAÇÃO") ||
      text.includes("ORCAMENTO LOCACAO") ||
      text.includes("SOLICITANTE:");
  }

  function findDocument() {
    const selectors = [
      ".cejas-orcamento-folha",
      ".document",
      "#orcamentoDocumento",
      "#document",
      "#orcamentoPreview",
      "[data-orcamento-documento]"
    ];

    for (const selector of selectors) {
      for (const el of [...document.querySelectorAll(selector)]) {
        if (isDocument(el)) return el;
      }
    }

    const candidates = [...document.querySelectorAll("body *")]
      .filter(el => el.children.length > 0 && isDocument(el))
      .sort((a, b) => a.getBoundingClientRect().width - b.getBoundingClientRect().width);

    if (candidates[0]) return candidates[0];

    throw new Error("Não encontrei a folha do orçamento.");
  }

  function removeControls(clone) {
    [...clone.querySelectorAll("*")].forEach((el) => {
      const idClass = `${el.id || ""} ${el.className || ""}`.toLowerCase();
      const text = String(el.textContent || "").trim();

      const remove =
        el.tagName === "BUTTON" ||
        idClass.includes("timer") ||
        idClass.includes("countdown") ||
        idClass.includes("cronometro") ||
        idClass.includes("toolbar") ||
        idClass.includes("actions") ||
        idClass.includes("modal") ||
        idClass.includes("btn") ||
        /conectado\s+\d/i.test(text) ||
        /voltar ao painel/i.test(text) ||
        /cadastro de itens/i.test(text) ||
        /salvar pdf/i.test(text) ||
        /imprimir/i.test(text);

      if (remove) el.remove();
    });
  }

  function splitLongContentIntoPages(baseClone) {
    const root = document.createElement("div");
    root.className = "cejas-pdf-a4-root";

    const page = baseClone.cloneNode(true);
    page.classList.add("cejas-pdf-a4-page");
    page.style.width = "210mm";
    page.style.minHeight = "297mm";
    page.style.height = "auto";
    page.style.transform = "none";
    page.style.margin = "0";
    page.style.boxShadow = "none";

    root.appendChild(page);
    return root;
  }

  async function gerarPdfBlobA4Completo() {
    await garantirPDFLibs();

    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }

    const original = findDocument();
    const clone = original.cloneNode(true);

    removeControls(clone);

    const root = splitLongContentIntoPages(clone);
    document.body.appendChild(root);

    await new Promise(resolve => setTimeout(resolve, 280));

    await Promise.all(
      [...root.querySelectorAll("img")].map(img => {
        if (img.complete) return Promise.resolve();

        return new Promise(resolve => {
          img.onload = resolve;
          img.onerror = resolve;
        });
      })
    );

    const pages = [...root.querySelectorAll(".cejas-pdf-a4-page")];
    const { jsPDF } = window.jspdf;
    const pdf = new jsPDF("p", "mm", "a4", true);

    for (let i = 0; i < pages.length; i++) {
      const page = pages[i];

      const canvas = await window.html2canvas(page, {
        scale: 2.45,
        useCORS: true,
        allowTaint: true,
        backgroundColor: "#ffffff",
        scrollX: 0,
        scrollY: 0,
        width: page.scrollWidth,
        height: page.scrollHeight,
        windowWidth: page.scrollWidth,
        windowHeight: page.scrollHeight
      });

      if (i > 0) pdf.addPage();

      const img = canvas.toDataURL("image/jpeg", 0.98);
      pdf.addImage(img, "JPEG", 0, 0, 210, 297, undefined, "FAST");
    }

    document.body.removeChild(root);

    return pdf.output("blob");
  }

  function pdfName() {
    const text = document.body.innerText || "";
    const match = text.match(/Evento:\s*([^\n\r]+)/i);
    const event = match && match[1]
      ? match[1].replace(/[^\wÀ-ÿ]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "")
      : "orcamento";

    return `${event || "orcamento"}-${new Date().toISOString().slice(0, 10)}.pdf`;
  }

  async function baixarPDFA4Completo() {
    try {
      const blob = await gerarPdfBlobA4Completo();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");

      a.href = url;
      a.download = pdfName();
      document.body.appendChild(a);
      a.click();
      a.remove();

      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error) {
      alert("Erro ao gerar PDF: " + error.message);
      throw error;
    }
  }

  window.gerarPdfBlob = gerarPdfBlobA4Completo;
  window.gerarPDFBlob = gerarPdfBlobA4Completo;
  window.gerarPdfBlobA4Completo = gerarPdfBlobA4Completo;

  window.gerarPdf = baixarPDFA4Completo;
  window.gerarPDF = baixarPDFA4Completo;
  window.imprimirOrcamento = baixarPDFA4Completo;
  window.baixarPdfOrcamento = baixarPDFA4Completo;

  document.addEventListener("click", function (event) {
    const btn = event.target.closest("button, a");
    if (!btn) return;

    const text = String(btn.textContent || "").toLowerCase();

    const isPdf = text.includes("imprimir") || text.includes("pdf a4") || text.includes("gerar pdf");
    const isSaveServer = text.includes("salvar pdf no servidor");

    if (isPdf && !isSaveServer) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      baixarPDFA4Completo();
    }
  }, true);

  console.log("✅ CEJAS: PDF A4 completo ativo.");
})();
// CEJAS_ORCAMENTO_PDF_A4_COMPLETO_JS_END
</script>
'''

if "</body>" not in s:
    raise SystemExit("❌ Não encontrei </body> em orcamentos.html.")

s = s.replace("</body>", js + "\n</body>", 1)

p.write_text(s)
PY

node --check lib/servidor-supabase-definitivo.js
node --check scripts/check-servidor-definitivo.js
node --check server.js

node <<'NODE'
const fs = require("fs");

const html = fs.readFileSync("orcamentos.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map(m => m[1]);

fs.mkdirSync(".cejas-local-backups/check-orcamento-a4-completo", { recursive: true });

scripts.forEach((code, index) => {
  fs.writeFileSync(`.cejas-local-backups/check-orcamento-a4-completo/script-${index + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-orcamento-a4-completo/script-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-orcamento-a4-completo

echo ""
echo "✅ Correção aplicada."
echo ""
echo "Servidor:"
echo "- A aba Servidor passa a ler/salvar/apagar/mover direto no Supabase Storage."
echo "- O local vira apenas cache."
echo "- Deploy não deve apagar os documentos do Servidor."
echo ""
echo "Orçamento:"
echo "- PDF A4 completo."
echo "- Não corta a página."
echo "- Mantém Observações, assinatura e rodapé."
echo ""
echo "Agora rode:"
echo "npm run servidor:check-definitivo"
echo "npm run dev"
