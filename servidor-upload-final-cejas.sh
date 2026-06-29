#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "servidor.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e servidor.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/servidor-upload-final-$STAMP"
mkdir -p "$BACKUP_DIR"
cp server.js servidor.html "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

server = Path("server.js")
s = server.read_text()

block_start = 'const SERVIDOR_TMP_DIR = path.join(__dirname, "uploads", "tmp-servidor");'
block_end = 'app.get("/api/servidor/arquivo", (req, res) => {'

if block_start not in s or block_end not in s:
    raise SystemExit("❌ Não encontrei o bloco do servidor no server.js.")

start = s.index(block_start)
end = s.index(block_end, start)

novo_bloco = r'''
const SERVIDOR_TMP_DIR = path.join(__dirname, "uploads", "tmp-servidor");
fs.mkdirSync(SERVIDOR_TMP_DIR, { recursive: true });

const servidorBulkUpload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, SERVIDOR_TMP_DIR),
    filename: (_req, file, cb) => {
      const safe = Date.now() + "-" + Math.random().toString(16).slice(2) + "-" + String(file.originalname || "arquivo").replace(/[^a-zA-Z0-9._-]/g, "-");
      cb(null, safe);
    }
  }),
  limits: {
    fileSize: 500 * 1024 * 1024,
    files: 10000
  }
});

const MESES_SERVIDOR_FINAL = [
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

const PALAVRAS_DOCUMENTO_SERVIDOR_FINAL = [
  "CONTRATO", "CONTRATOS",
  "BOLETO", "BOLETOS",
  "DEMONSTRATIVO", "DEMONSTRATIVOS",
  "RELATORIO", "RELATÓRIO",
  "ORCAMENTO", "ORÇAMENTO",
  "PROPOSTA",
  "RECIBO", "RECIBOS",
  "COMPROVANTE", "COMPROVANTES",
  "NOTA FISCAL", "NOTAS FISCAIS", "NOTA", "NFS", "NF",
  "EVENTO", "EVENTOS",
  "ENTIDADE", "ENTIDADES",
  "ASSINADO", "ASSINADA",
  "FINAL", "OK", "PDF", "DOC", "DOCX", "XLS", "XLSX", "PNG", "JPG", "JPEG"
];

function normalizarServidorFinal(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function slugServidorFinal(texto, fallback = "VERIFICAR") {
  const limpo = normalizarServidorFinal(texto)
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  return limpo || fallback;
}

function nomeArquivoSeguroServidorFinal(texto, fallback = "arquivo") {
  return String(texto || fallback)
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^\.+/, fallback) || fallback;
}

function itemMesServidorFinal(mes) {
  const numero = String(mes || "").padStart(2, "0");
  return MESES_SERVIDOR_FINAL.find(m => m.numero === numero) || null;
}

function pastaMesServidorFinal(mes) {
  const item = itemMesServidorFinal(mes);
  return item ? `${item.numero} ${item.nome}` : "MES NAO IDENTIFICADO";
}

function pastaMesVerificarServidorFinal(mes) {
  const item = itemMesServidorFinal(mes);
  return item ? item.simples : "SEM MES";
}

function mesPorNomeServidorFinal(texto) {
  const normal = normalizarServidorFinal(texto);

  for (const mes of MESES_SERVIDOR_FINAL) {
    for (const alias of mes.aliases) {
      const aliasNormal = normalizarServidorFinal(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(^|[^A-Z0-9])${aliasNormal}([^A-Z0-9]|$)`);
      if (re.test(normal)) return mes.numero;
    }
  }

  return "";
}

function detectarDataServidorFinal(texto, anoPadrao = "2026") {
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

  const mesNome = mesPorNomeServidorFinal(original);
  const anoCompleto = original.match(/\b(20\d{2})\b/);

  return {
    ok: false,
    ano: anoCompleto ? anoCompleto[1] : anoDefault,
    mes: mesNome,
    dia: "",
    anoExplicito: Boolean(anoCompleto)
  };
}

function removerDatasServidorFinal(texto) {
  return String(texto || "")
    .replace(/\b20\d{2}[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ]\d{1,2}\b/g, " ")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}[.\-_/ ](20\d{2}|\d{2})\b/g, " ")
    .replace(/(^|[^\d])\d{1,2}\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?($|[^\d])/gi, " ")
    .replace(/(^|[^\d])\d{1,2}\s+(0?[1-9]|1[0-2])(?:\s+(20\d{2}|\d{2}))?($|[^\d])/g, " ");
}

function removerPalavrasDocumentoServidorFinal(texto) {
  let saida = normalizarServidorFinal(texto);

  for (const palavra of PALAVRAS_DOCUMENTO_SERVIDOR_FINAL) {
    const normal = normalizarServidorFinal(palavra).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`(^|[^A-Z0-9])${normal}([^A-Z0-9]|$)`, "gi");
    saida = saida.replace(re, " ");
  }

  for (const mes of MESES_SERVIDOR_FINAL) {
    for (const alias of mes.aliases) {
      const normal = normalizarServidorFinal(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(^|[^A-Z0-9])${normal}([^A-Z0-9]|$)`, "gi");
      saida = saida.replace(re, " ");
    }
  }

  return saida;
}

function parteIgnoradaServidorFinal(parte) {
  const normal = normalizarServidorFinal(parte);

  if (!normal) return true;
  if (normal === "SERVIDOR") return true;
  if (normal === "DOCUMENTOS") return true;
  if (normal === "EVENTOS") return true;
  if (normal === "BOLETOS") return true;
  if (normal === "DEMONSTRATIVOS") return true;
  if (normal === "CONTRATOS") return true;
  if (normal === "ENTIDADES") return true;
  if (normal === "VERIFICAR") return true;
  if (normal === "UPLOADS") return true;
  if (normal === "ARQUIVOS") return true;
  if (/^20\d{2}$/.test(normal)) return true;
  if (/^\d{2}\s+[A-Z]/.test(normal)) return true;

  return MESES_SERVIDOR_FINAL.some(m => normal === m.simples || normal === `${m.numero} ${normalizarServidorFinal(m.nome)}`);
}

function limparNomeEventoServidorFinal(originalPath, fileName) {
  const partes = String(originalPath || fileName || "")
    .replace(/\\/g, "/")
    .split("/")
    .filter(Boolean);

  const candidatos = [];

  const baseArquivo = path.basename(String(fileName || partes[partes.length - 1] || "arquivo"), path.extname(String(fileName || "")));
  candidatos.push(baseArquivo);

  for (let i = partes.length - 2; i >= 0; i--) {
    if (!parteIgnoradaServidorFinal(partes[i])) {
      candidatos.push(partes[i]);
    }
  }

  for (const candidato of candidatos) {
    let nome = path.basename(String(candidato || ""), path.extname(String(candidato || "")));

    nome = removerDatasServidorFinal(nome);
    nome = removerPalavrasDocumentoServidorFinal(nome);

    nome = nome
      .replace(/[_\-.]+/g, " ")
      .replace(/\b(DO|DE|DA|DAS|DOS)\b$/gi, " ")
      .replace(/\s+/g, " ")
      .trim();

    if (nome.length >= 2) {
      return slugServidorFinal(nome, "VERIFICAR");
    }
  }

  return "";
}

function pastaEventoServidorFinal(titulo, data) {
  return slugServidorFinal(`${titulo} ${data.dia}.${data.mes}`, "VERIFICAR");
}

function destinoServidorFinal(originalPath, fileName, anoPadrao = "2026") {
  const textoCompleto = `${originalPath || ""} ${fileName || ""}`;
  const data = detectarDataServidorFinal(textoCompleto, anoPadrao);
  const titulo = limparNomeEventoServidorFinal(originalPath, fileName);
  const nomeArquivo = nomeArquivoSeguroServidorFinal(fileName || path.basename(originalPath || "arquivo"), "arquivo");

  if (data.ok && data.dia && data.mes && titulo) {
    const mesPasta = pastaMesServidorFinal(data.mes);
    const eventoPasta = pastaEventoServidorFinal(titulo, data);

    if (data.ano && data.ano !== String(anoPadrao || "2026")) {
      return `${data.ano}/${mesPasta}/${eventoPasta}/${nomeArquivo}`;
    }

    return `${mesPasta}/${eventoPasta}/${nomeArquivo}`;
  }

  const mesVerificar = data.mes ? pastaMesVerificarServidorFinal(data.mes) : "SEM MES";
  return `VERIFICAR/${mesVerificar}/${nomeArquivo}`;
}

function caminhoUnicoServidor(target) {
  if (!fs.existsSync(target)) return target;

  const dir = path.dirname(target);
  const ext = path.extname(target);
  const name = path.basename(target, ext);

  let count = 1;
  let candidate = path.join(dir, `${name}-${count}${ext}`);

  while (fs.existsSync(candidate)) {
    count++;
    candidate = path.join(dir, `${name}-${count}${ext}`);
  }

  return candidate;
}

function listarArquivosServidorRecursivo(dir, base = SERVIDOR_DIR, resultado = []) {
  if (!fs.existsSync(dir)) return resultado;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;

    const full = path.join(dir, entry.name);
    const rel = path.relative(base, full).replace(/\\/g, "/");

    if (entry.isDirectory()) {
      listarArquivosServidorRecursivo(full, base, resultado);
    } else if (entry.isFile()) {
      resultado.push({ full, rel, name: entry.name });
    }
  }

  return resultado;
}

function listarPastasServidorRecursivo(dir = SERVIDOR_DIR, base = SERVIDOR_DIR, resultado = []) {
  if (!fs.existsSync(dir)) return resultado;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;

    const full = path.join(dir, entry.name);
    const rel = path.relative(base, full).replace(/\\/g, "/");

    if (entry.isDirectory()) {
      resultado.push(rel);
      listarPastasServidorRecursivo(full, base, resultado);
    }
  }

  return resultado;
}

function pastaJaPareceCorretaServidor(rel) {
  const partes = String(rel || "").split("/").filter(Boolean);

  if (partes[0] === "VERIFICAR") return false;

  let idxMes = 0;

  if (/^20\d{2}$/.test(partes[0])) {
    idxMes = 1;
  }

  if (partes.length < idxMes + 3) return false;
  if (!/^\d{2}\s+[A-ZÁÉÍÓÚÂÊÔÃÕÇ]/.test(partes[idxMes])) return false;

  const nomeEvento = partes[idxMes + 1] || "";
  const normal = normalizarServidorFinal(nomeEvento);

  const bloqueadas = [
    "DOCUMENTOS", "EVENTOS", "BOLETOS", "DEMONSTRATIVOS",
    "CONTRATOS", "ENTIDADES", "NOTAS E RECIBOS", "VERIFICAR"
  ];

  if (bloqueadas.includes(normal)) return false;

  return /\b\d{2}\.\d{2}\b/.test(nomeEvento);
}

function listarVerificarServidor() {
  const verificarDir = safeServidorPath("VERIFICAR");

  if (!fs.existsSync(verificarDir)) return [];

  return listarArquivosServidorRecursivo(verificarDir)
    .map(item => ({
      path: item.rel,
      nome: item.name,
      pasta: path.dirname(item.rel).replace(/\\/g, "/"),
      mes: item.rel.split("/")[1] || "SEM MES"
    }))
    .sort((a, b) => a.path.localeCompare(b.path, "pt-BR"));
}

app.get("/api/servidor/pastas", (_req, res) => {
  try {
    const pastas = listarPastasServidorRecursivo()
      .filter(Boolean)
      .filter(pasta => !pasta.startsWith("VERIFICAR/"))
      .sort((a, b) => a.localeCompare(b, "pt-BR"))
      .slice(0, 3000);

    res.json({ ok: true, pastas });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao listar pastas: " + error.message
    });
  }
});

app.get("/api/servidor/verificar", (_req, res) => {
  try {
    res.json({
      ok: true,
      itens: listarVerificarServidor()
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao listar VERIFICAR: " + error.message
    });
  }
});

app.post("/api/servidor/mover", express.json({ limit: "2mb" }), (req, res) => {
  try {
    const origem = String(req.body?.origem || "").trim();
    const destinoPasta = String(req.body?.destinoPasta || "").trim();

    if (!origem || !destinoPasta) {
      return res.status(400).json({
        ok: false,
        message: "Informe origem e destino."
      });
    }

    const origemAbs = safeServidorPath(origem);
    const destinoDir = safeServidorPath(destinoPasta);

    if (!fs.existsSync(origemAbs)) {
      return res.status(404).json({
        ok: false,
        message: "Item de origem não encontrado."
      });
    }

    fs.mkdirSync(destinoDir, { recursive: true });

    const target = caminhoUnicoServidor(path.join(destinoDir, path.basename(origemAbs)));
    fs.renameSync(origemAbs, target);

    res.json({
      ok: true,
      destino: path.relative(SERVIDOR_DIR, target).replace(/\\/g, "/"),
      message: "Item movido com sucesso."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao mover item: " + error.message
    });
  }
});

app.post("/api/servidor/upload-inteligente", servidorBulkUpload.array("arquivos"), (req, res) => {
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

    files.forEach((file, index) => {
      const originalRelative = paths[index] || file.originalname;
      const destinoRelativo = destinoServidorFinal(originalRelative, file.originalname, anoPadrao);
      const target = caminhoUnicoServidor(safeServidorPath(destinoRelativo));
      const destinoFinalRelativo = path.relative(SERVIDOR_DIR, target).replace(/\\/g, "/");

      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.renameSync(file.path, target);

      salvos.push(destinoFinalRelativo);

      if (destinoFinalRelativo.startsWith("VERIFICAR/")) {
        verificar.push(destinoFinalRelativo);
      }
    });

    res.json({
      ok: true,
      saved: salvos.length,
      verificar: verificar.length,
      exemplos: salvos.slice(0, 10),
      message: `${salvos.length} arquivo(s) enviados e organizados. ${verificar.length} foram para VERIFICAR.`
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro no upload inteligente: " + error.message
    });
  }
});

app.post("/api/servidor/reorganizar-eventos", express.json({ limit: "2mb" }), (req, res) => {
  try {
    const anoPadrao = String(req.body?.anoPadrao || "2026");
    const arquivos = listarArquivosServidorRecursivo(SERVIDOR_DIR);
    const movidos = [];
    const verificar = [];
    const ignorados = [];

    for (const arquivo of arquivos) {
      if (pastaJaPareceCorretaServidor(arquivo.rel)) {
        ignorados.push(arquivo.rel);
        continue;
      }

      const destinoRelativo = destinoServidorFinal(arquivo.rel, arquivo.name, anoPadrao);
      const destinoAbs = caminhoUnicoServidor(safeServidorPath(destinoRelativo));
      const destinoFinalRelativo = path.relative(SERVIDOR_DIR, destinoAbs).replace(/\\/g, "/");

      if (path.resolve(arquivo.full) === path.resolve(destinoAbs)) {
        ignorados.push(arquivo.rel);
        continue;
      }

      fs.mkdirSync(path.dirname(destinoAbs), { recursive: true });
      fs.renameSync(arquivo.full, destinoAbs);

      movidos.push({ de: arquivo.rel, para: destinoFinalRelativo });

      if (destinoFinalRelativo.startsWith("VERIFICAR/")) {
        verificar.push(destinoFinalRelativo);
      }
    }

    res.json({
      ok: true,
      movidos: movidos.length,
      ignorados: ignorados.length,
      verificar: verificar.length,
      exemplos: movidos.slice(0, 12),
      message: `${movidos.length} arquivo(s) reorganizados. ${verificar.length} ficaram em VERIFICAR.`
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao reorganizar servidor: " + error.message
    });
  }
});

'''

s = s[:start] + novo_bloco + s[end:]
server.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

html = Path("servidor.html")
s = html.read_text()

if "CEJAS_UPLOAD_FINAL_OVERRIDE_START" not in s:
    js = r'''
<script>
// CEJAS_UPLOAD_FINAL_OVERRIDE_START
(function () {
  let arquivosSelecionadosServidorFinal = [];

  function $(id) {
    return document.getElementById(id);
  }

  function atualizarListaUploadFinal() {
    const status = $("uploadStatus");
    const preview = $("uploadPreview");

    if (!status) return;

    status.textContent = arquivosSelecionadosServidorFinal.length
      ? `${arquivosSelecionadosServidorFinal.length} arquivo(s) selecionado(s). O sistema vai organizar por evento, data e mês.`
      : "Nenhum arquivo selecionado.";

    if (preview) {
      preview.style.display = arquivosSelecionadosServidorFinal.length ? "block" : "none";
      preview.innerHTML = arquivosSelecionadosServidorFinal
        .slice(0, 60)
        .map(item => `<div>• ${item.path}</div>`)
        .join("") + (arquivosSelecionadosServidorFinal.length > 60 ? `<div>+ ${arquivosSelecionadosServidorFinal.length - 60} arquivo(s)...</div>` : "");
    }
  }

  function adicionarArquivosServidorFinal(lista) {
    const mapa = new Map(arquivosSelecionadosServidorFinal.map(item => [`${item.path}::${item.file.size}`, item]));

    lista.forEach(item => {
      if (!item || !item.file) return;
      const path = item.path || item.file.webkitRelativePath || item.file.name;
      mapa.set(`${path}::${item.file.size}`, {
        file: item.file,
        path
      });
    });

    arquivosSelecionadosServidorFinal = [...mapa.values()];
    atualizarListaUploadFinal();
  }

  function lerEntradaServidorFinal(entry, base = "") {
    return new Promise((resolve, reject) => {
      if (entry.isFile) {
        entry.file(file => {
          resolve([{ file, path: `${base}${file.name}` }]);
        }, reject);
        return;
      }

      if (!entry.isDirectory) {
        resolve([]);
        return;
      }

      const reader = entry.createReader();
      const entries = [];

      function readBatch() {
        reader.readEntries(async batch => {
          if (!batch.length) {
            try {
              const nested = await Promise.all(entries.map(child => lerEntradaServidorFinal(child, `${base}${entry.name}/`)));
              resolve(nested.flat());
            } catch (error) {
              reject(error);
            }
            return;
          }

          entries.push(...batch);
          readBatch();
        }, reject);
      }

      readBatch();
    });
  }

  async function processarDropServidorFinal(event) {
    event.preventDefault();

    const drop = $("dropZoneServidor");
    if (drop) drop.classList.remove("dragover");

    const items = [...(event.dataTransfer.items || [])];
    const arquivos = [];

    if (items.length && items[0].webkitGetAsEntry) {
      for (const item of items) {
        const entry = item.webkitGetAsEntry();
        if (!entry) continue;
        arquivos.push(...await lerEntradaServidorFinal(entry));
      }
    } else {
      arquivos.push(...[...(event.dataTransfer.files || [])].map(file => ({
        file,
        path: file.name
      })));
    }

    adicionarArquivosServidorFinal(arquivos);
  }

  window.clearSelectedFiles = function clearSelectedFiles() {
    arquivosSelecionadosServidorFinal = [];

    if ($("folderInput")) $("folderInput").value = "";
    if ($("fileInput")) $("fileInput").value = "";

    atualizarListaUploadFinal();
  };

  window.uploadFolder = async function uploadFolder() {
    if (!arquivosSelecionadosServidorFinal.length) {
      alert("Selecione arquivos soltos, uma pasta ou arraste várias pastas primeiro.");
      return;
    }

    const mode = document.querySelector("input[name='uploadMode']:checked")?.value || "auto";
    const endpoint = mode === "auto" ? "/api/servidor/upload-inteligente" : "/api/servidor/upload";

    const formData = new FormData();

    const destino = typeof getUploadDestination === "function" ? getUploadDestination() : "";
    formData.append("destino", destino);

    const anoPadrao = $("autoYear")?.value || "2026";
    formData.append("anoPadrao", anoPadrao);

    arquivosSelecionadosServidorFinal.forEach(item => {
      formData.append("arquivos", item.file);
      formData.append("paths", item.path);
    });

    const status = $("uploadStatus");
    if (status) status.textContent = "Enviando e organizando por evento...";

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        body: formData
      });

      const data = await response.json();

      if (!response.ok || !data.ok) {
        throw new Error(data.message || "Erro ao enviar.");
      }

      if (status) {
        status.textContent = data.message || "Arquivos enviados.";
      }

      clearSelectedFiles();

      if (typeof loadTree === "function") {
        await loadTree();
      }

      if (typeof carregarPainelVerificarServidor === "function") {
        await carregarPainelVerificarServidor();
      }

      alert(data.message || "Arquivos enviados e organizados.");
    } catch (error) {
      if (status) status.textContent = "Erro: " + error.message;
      alert("Erro ao enviar: " + error.message);
    }
  };

  function iniciarUploadFinal() {
    const folder = $("folderInput");
    const file = $("fileInput");
    const drop = $("dropZoneServidor");

    if (folder && !folder.dataset.cejasUploadFinal) {
      folder.dataset.cejasUploadFinal = "1";
      folder.addEventListener("change", () => {
        adicionarArquivosServidorFinal([...folder.files].map(file => ({
          file,
          path: file.webkitRelativePath || file.name
        })));
      });
    }

    if (file && !file.dataset.cejasUploadFinal) {
      file.dataset.cejasUploadFinal = "1";
      file.addEventListener("change", () => {
        adicionarArquivosServidorFinal([...file.files].map(file => ({
          file,
          path: file.name
        })));
      });
    }

    if (drop && !drop.dataset.cejasUploadFinal) {
      drop.dataset.cejasUploadFinal = "1";

      drop.addEventListener("dragover", event => {
        event.preventDefault();
        drop.classList.add("dragover");
      });

      drop.addEventListener("dragleave", () => {
        drop.classList.remove("dragover");
      });

      drop.addEventListener("drop", processarDropServidorFinal);
    }

    atualizarListaUploadFinal();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", iniciarUploadFinal);
  } else {
    iniciarUploadFinal();
  }
})();
// CEJAS_UPLOAD_FINAL_OVERRIDE_END
</script>
'''
    s = s.replace("</body>", js + "\n</body>", 1)

html.write_text(s)
PY

node --check server.js

node <<'NODE'
const fs = require('fs');
const html = fs.readFileSync('servidor.html', 'utf8');
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync('.cejas-local-backups/check-servidor-upload-final', { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-servidor-upload-final/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-servidor-upload-final/script-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-servidor-upload-final

echo ""
echo "✅ Upload final do servidor ajustado."
echo ""
echo "Agora ele aceita:"
echo "- vários arquivos soltos"
echo "- uma pasta inteira"
echo "- várias pastas juntas por arrastar e soltar"
echo ""
echo "E organiza assim:"
echo "01 JANEIRO / WEG 23.01 / BOLETO WEG 23.01.pdf"
echo "06 JUNHO / JARAGUA MAIS SAUDAVEL 06.06 / contrato.pdf"
echo "VERIFICAR / JUNHO / arquivo-nao-entendido.pdf"
echo ""
echo "Agora rode:"
echo "npm run dev"
