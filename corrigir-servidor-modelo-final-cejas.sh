#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "servidor.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e servidor.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/servidor-modelo-final-$STAMP"
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
    files: 8000
  }
});

const MESES_SERVIDOR_EVENTO = [
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

const PALAVRAS_DOCUMENTO_SERVIDOR = [
  "CONTRATO",
  "CONTRATOS",
  "BOLETO",
  "BOLETOS",
  "DEMONSTRATIVO",
  "DEMONSTRATIVOS",
  "RELATORIO",
  "RELATÓRIO",
  "ORCAMENTO",
  "ORÇAMENTO",
  "PROPOSTA",
  "RECIBO",
  "RECIBOS",
  "COMPROVANTE",
  "COMPROVANTES",
  "NOTA FISCAL",
  "NOTAS FISCAIS",
  "NOTA",
  "NFS",
  "NF",
  "EVENTO",
  "EVENTOS",
  "ENTIDADE",
  "ENTIDADES",
  "ASSINADO",
  "ASSINADA",
  "FINAL",
  "OK",
  "PDF",
  "DOC",
  "DOCX",
  "XLS",
  "XLSX",
  "PNG",
  "JPG",
  "JPEG"
];

function normalizarServidorEvento(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function slugServidorEvento(texto, fallback = "VERIFICAR") {
  const limpo = String(texto || "")
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .trim();

  return limpo || fallback;
}

function nomeArquivoSeguroServidorEvento(texto, fallback = "arquivo") {
  return slugServidorEvento(texto, fallback).replace(/^\.+/, fallback);
}

function itemMesServidorEvento(mes) {
  const numero = String(mes || "").padStart(2, "0");
  return MESES_SERVIDOR_EVENTO.find(m => m.numero === numero) || null;
}

function pastaMesServidorEvento(mes) {
  const item = itemMesServidorEvento(mes);
  return item ? `${item.numero} ${item.nome}` : "MES NAO IDENTIFICADO";
}

function pastaMesVerificarServidorEvento(mes) {
  const item = itemMesServidorEvento(mes);
  return item ? item.simples : "SEM MES";
}

function mesPorNomeServidorEvento(texto) {
  const normal = normalizarServidorEvento(texto);

  for (const mes of MESES_SERVIDOR_EVENTO) {
    for (const alias of mes.aliases) {
      const aliasNormal = normalizarServidorEvento(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(^|[^A-Z0-9])${aliasNormal}([^A-Z0-9]|$)`);
      if (re.test(normal)) return mes.numero;
    }
  }

  return "";
}

function detectarDataEventoServidor(texto, anoPadrao = "2026") {
  const original = String(texto || "");
  const padraoAno = String(anoPadrao || "2026");

  let match = original.match(/\b(20\d{2})[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ](\d{1,2})\b/);
  if (match) {
    return {
      ok: true,
      ano: match[1],
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[3]).padStart(2, "0"),
      temDia: true,
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
      temDia: true,
      anoExplicito: true
    };
  }

  match = original.match(/(?:^|[^\d])(\d{1,2})\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?(?:[^\d]|$)/i);
  if (match) {
    const ano = match[3]
      ? (String(match[3]).length === 2 ? `20${match[3]}` : match[3])
      : padraoAno;

    return {
      ok: true,
      ano,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      temDia: true,
      anoExplicito: Boolean(match[3])
    };
  }

  match = original.match(/(?:^|[^\d])(\d{1,2})\s+(0?[1-9]|1[0-2])(?:\s+(20\d{2}|\d{2}))?(?:[^\d]|$)/);
  if (match) {
    const ano = match[3]
      ? (String(match[3]).length === 2 ? `20${match[3]}` : match[3])
      : padraoAno;

    return {
      ok: true,
      ano,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      temDia: true,
      anoExplicito: Boolean(match[3])
    };
  }

  const mesNome = mesPorNomeServidorEvento(original);
  const anoCompleto = original.match(/\b(20\d{2})\b/);

  if (mesNome) {
    return {
      ok: false,
      ano: anoCompleto ? anoCompleto[1] : padraoAno,
      mes: mesNome,
      dia: "",
      temDia: false,
      anoExplicito: Boolean(anoCompleto)
    };
  }

  return {
    ok: false,
    ano: anoCompleto ? anoCompleto[1] : padraoAno,
    mes: "",
    dia: "",
    temDia: false,
    anoExplicito: Boolean(anoCompleto)
  };
}

function removerDatasServidorEvento(texto) {
  return String(texto || "")
    .replace(/\b20\d{2}[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ]\d{1,2}\b/g, " ")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}[.\-_/ ](20\d{2}|\d{2})\b/g, " ")
    .replace(/(^|[^\d])\d{1,2}\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?($|[^\d])/gi, " ")
    .replace(/(^|[^\d])\d{1,2}\s+(0?[1-9]|1[0-2])(?:\s+(20\d{2}|\d{2}))?($|[^\d])/g, " ");
}

function removerPalavrasDocumentoServidorEvento(texto) {
  let saida = normalizarServidorEvento(texto);

  for (const palavra of PALAVRAS_DOCUMENTO_SERVIDOR) {
    const normal = normalizarServidorEvento(palavra).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`(^|[^A-Z0-9])${normal}([^A-Z0-9]|$)`, "gi");
    saida = saida.replace(re, " ");
  }

  for (const mes of MESES_SERVIDOR_EVENTO) {
    for (const alias of mes.aliases) {
      const normal = normalizarServidorEvento(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(^|[^A-Z0-9])${normal}([^A-Z0-9]|$)`, "gi");
      saida = saida.replace(re, " ");
    }
  }

  return saida;
}

function limparNomeEventoServidor(originalPath, fileName) {
  const partes = String(originalPath || fileName || "")
    .replace(/\\/g, "/")
    .split("/")
    .filter(Boolean);

  const candidatos = [];

  const baseArquivo = path.basename(String(fileName || partes[partes.length - 1] || "arquivo"), path.extname(String(fileName || "")));
  candidatos.push(baseArquivo);

  for (let i = partes.length - 2; i >= 0; i--) {
    const parte = partes[i];

    if (!parte) continue;

    const normal = normalizarServidorEvento(parte);

    if (
      normal === "DOCUMENTOS" ||
      normal === "EVENTOS" ||
      normal === "BOLETOS" ||
      normal === "DEMONSTRATIVOS" ||
      normal === "CONTRATOS" ||
      normal === "ENTIDADES" ||
      normal === "VERIFICAR" ||
      normal === "SERVIDOR" ||
      /^20\d{2}$/.test(normal) ||
      /^\d{2}\s+[A-Z]/.test(normal) ||
      MESES_SERVIDOR_EVENTO.some(m => normal === m.simples || normal === `${m.numero} ${normalizarServidorEvento(m.nome)}`)
    ) {
      continue;
    }

    candidatos.push(parte);
  }

  for (const candidato of candidatos) {
    let nome = path.basename(String(candidato || ""), path.extname(String(candidato || "")));

    nome = removerDatasServidorEvento(nome);
    nome = removerPalavrasDocumentoServidorEvento(nome);

    nome = nome
      .replace(/[_\-.]+/g, " ")
      .replace(/\b(DO|DE|DA|DAS|DOS)\b$/gi, " ")
      .replace(/\s+/g, " ")
      .trim();

    if (nome.length >= 2) {
      return slugServidorEvento(nome.toUpperCase(), "VERIFICAR");
    }
  }

  return "";
}

function pastaEventoFinalServidor(titulo, data) {
  const dia = String(data.dia || "").padStart(2, "0");
  const mes = String(data.mes || "").padStart(2, "0");
  return slugServidorEvento(`${titulo} ${dia}.${mes}`.toUpperCase(), "VERIFICAR");
}

function destinoServidorPorEvento(originalPath, fileName, anoPadrao = "2026") {
  const texto = `${originalPath || ""} ${fileName || ""}`;
  const data = detectarDataEventoServidor(texto, anoPadrao);
  const titulo = limparNomeEventoServidor(originalPath, fileName);
  const nomeArquivo = nomeArquivoSeguroServidorEvento(fileName || path.basename(originalPath || "arquivo"), "arquivo");

  if (data.ok && data.temDia && data.mes && titulo) {
    const mesPasta = pastaMesServidorEvento(data.mes);
    const eventoPasta = pastaEventoFinalServidor(titulo, data);

    if (data.ano && data.ano !== String(anoPadrao || "2026")) {
      return `${data.ano}/${mesPasta}/${eventoPasta}/${nomeArquivo}`;
    }

    return `${mesPasta}/${eventoPasta}/${nomeArquivo}`;
  }

  const mesVerificar = data.mes ? pastaMesVerificarServidorEvento(data.mes) : "SEM MES";
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

  const bloqueadas = [
    "DOCUMENTOS",
    "EVENTOS",
    "BOLETOS",
    "DEMONSTRATIVOS",
    "CONTRATOS",
    "ENTIDADES",
    "NOTAS E RECIBOS",
    "VERIFICAR"
  ];

  const normal = normalizarServidorEvento(nomeEvento);

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
      .slice(0, 2500);

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

    if (!fs.statSync(destinoDir).isDirectory()) {
      return res.status(400).json({
        ok: false,
        message: "Destino precisa ser uma pasta."
      });
    }

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
      const destinoRelativo = destinoServidorPorEvento(originalRelative, file.originalname, anoPadrao);
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
      message: `${salvos.length} arquivo(s) organizados. ${verificar.length} foram para VERIFICAR.`
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

      const destinoRelativo = destinoServidorPorEvento(arquivo.rel, arquivo.name, anoPadrao);
      const destinoAbsBase = safeServidorPath(destinoRelativo);
      const destinoAbs = caminhoUnicoServidor(destinoAbsBase);
      const destinoFinalRelativo = path.relative(SERVIDOR_DIR, destinoAbs).replace(/\\/g, "/");

      if (path.resolve(arquivo.full) === path.resolve(destinoAbs)) {
        ignorados.push(arquivo.rel);
        continue;
      }

      fs.mkdirSync(path.dirname(destinoAbs), { recursive: true });
      fs.renameSync(arquivo.full, destinoAbs);

      movidos.push({
        de: arquivo.rel,
        para: destinoFinalRelativo
      });

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
import re

html = Path("servidor.html")
s = html.read_text()

s = s.replace(
  "No modo inteligente, o sistema junta tudo pelo mesmo evento: nome do evento + dia + mês. Boleto, contrato, orçamento e demonstrativo ficam dentro da mesma pasta do evento.",
  "No modo inteligente, o sistema junta tudo na pasta do evento. Exemplo: 01 JANEIRO / WEG 23.01 / boleto, demonstrativo, contrato e orçamento."
)

s = s.replace(
  "Regra do modo inteligente: VEG 15 do 10, contrato VEG 15 10, boleto VEG 15/10 e demonstrativo VEG 15.10 entram todos em 2026 / 10 OUTUBRO / VEG 15 DO 10. O que não tiver evento + dia + mês vai para VERIFICAR.",
  "Regra do modo inteligente: WEG 23.01, boleto WEG 23.01 e demonstrativo WEG 23.01 entram todos em 01 JANEIRO / WEG 23.01. O que não tiver nome + data vai para VERIFICAR."
)

s = s.replace(
  "Exemplo correto: 2026 / 10 OUTUBRO / VEG 15 DO 10 / contrato.pdf, boleto.pdf, orçamento.pdf e demonstrativo.pdf. Nada de separar por DOCUMENTOS, BOLETOS ou DEMONSTRATIVOS. O que não for entendido entra em VERIFICAR.",
  "Exemplo correto: 01 JANEIRO / WEG 23.01 / WEG23.01.pdf, BOLETO WEG 23.01.pdf e DEMONSTRATIVO WEG 23.01.pdf. Nada de separar por DOCUMENTOS, BOLETOS ou DEMONSTRATIVOS. O que não for entendido entra em VERIFICAR."
)

if "CEJAS_VERIFICAR_PANEL_START" not in s:
    painel_script = r'''
<script>
// CEJAS_VERIFICAR_PANEL_START
(function () {
  if (window.__CEJAS_VERIFICAR_PANEL__) return;
  window.__CEJAS_VERIFICAR_PANEL__ = true;

  function escapeHTML(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function criarPainelVerificar() {
    if (document.getElementById("painelVerificarServidor")) return;

    const main = document.querySelector("main") || document.body;

    const panel = document.createElement("section");
    panel.id = "painelVerificarServidor";
    panel.style.cssText = `
      background: #111114;
      border: 1px solid rgba(255,255,255,.09);
      border-radius: 22px;
      padding: 18px;
      margin: 18px 0;
      color: #fff;
    `;

    panel.innerHTML = `
      <div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap;margin-bottom:14px;">
        <div>
          <h3 style="margin:0 0 6px;font-size:20px;">VERIFICAR</h3>
          <p style="margin:0;color:#b3b3b3;font-size:13px;line-height:1.45;">
            Arquivos que o sistema não entendeu. Você pode apagar ou mover para uma pasta de evento já criada.
          </p>
        </div>
        <button class="btn" type="button" onclick="carregarPainelVerificarServidor()">Atualizar VERIFICAR</button>
      </div>
      <div id="listaVerificarServidor" style="display:grid;gap:10px;"></div>
    `;

    const tree = document.querySelector("#serverTree, #tree, .tree-panel, .server-tree");
    if (tree && tree.parentNode) {
      tree.parentNode.insertBefore(panel, tree);
    } else {
      main.appendChild(panel);
    }
  }

  async function carregarPastasServidorVerificar() {
    try {
      const response = await fetch("/api/servidor/pastas", { cache: "no-store" });
      const data = await response.json();
      if (!data.ok) return [];
      return data.pastas || [];
    } catch {
      return [];
    }
  }

  window.carregarPainelVerificarServidor = async function carregarPainelVerificarServidor() {
    criarPainelVerificar();

    const lista = document.getElementById("listaVerificarServidor");
    lista.innerHTML = `<div style="color:#b3b3b3;">Carregando arquivos para verificar...</div>`;

    const [pastasResponse, verificarResponse] = await Promise.all([
      carregarPastasServidorVerificar(),
      fetch("/api/servidor/verificar", { cache: "no-store" }).then(r => r.json()).catch(() => ({ ok: false, itens: [] }))
    ]);

    const pastas = pastasResponse || [];
    const itens = verificarResponse.ok ? (verificarResponse.itens || []) : [];

    if (!itens.length) {
      lista.innerHTML = `<div style="color:#b3b3b3;padding:14px;border:1px dashed rgba(255,255,255,.16);border-radius:14px;">Nenhum arquivo pendente em VERIFICAR.</div>`;
      return;
    }

    const options = [
      `<option value="">Selecione a pasta de destino...</option>`,
      ...pastas.map(pasta => `<option value="${escapeHTML(pasta)}">${escapeHTML(pasta)}</option>`)
    ].join("");

    lista.innerHTML = itens.map((item, index) => `
      <article style="display:grid;grid-template-columns:1fr 220px auto auto;gap:10px;align-items:center;background:#17171c;border:1px solid rgba(255,255,255,.08);border-radius:16px;padding:12px;">
        <div style="min-width:0;">
          <strong style="display:block;overflow-wrap:anywhere;">${escapeHTML(item.nome)}</strong>
          <small style="display:block;color:#b3b3b3;overflow-wrap:anywhere;margin-top:4px;">${escapeHTML(item.pasta)}</small>
        </div>

        <select id="verificarDestino-${index}" style="width:100%;padding:11px;border-radius:11px;background:#0b0b10;color:#fff;border:1px solid rgba(255,255,255,.14);">
          ${options}
        </select>

        <button class="btn" type="button" onclick="moverVerificarServidor('${encodeURIComponent(item.path)}', 'verificarDestino-${index}')">
          Mover
        </button>

        <button class="btn red" type="button" onclick="apagarVerificarServidor('${encodeURIComponent(item.path)}')">
          Apagar
        </button>
      </article>
    `).join("");
  };

  window.moverVerificarServidor = async function moverVerificarServidor(pathEncoded, selectId) {
    const origem = decodeURIComponent(pathEncoded);
    const destinoPasta = document.getElementById(selectId)?.value || "";

    if (!destinoPasta) {
      alert("Selecione a pasta de destino.");
      return;
    }

    const response = await fetch("/api/servidor/mover", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ origem, destinoPasta })
    });

    const data = await response.json();

    if (!data.ok) {
      alert(data.message || "Erro ao mover arquivo.");
      return;
    }

    if (typeof loadTree === "function") await loadTree();
    await carregarPainelVerificarServidor();

    alert("Arquivo movido com sucesso.");
  };

  window.apagarVerificarServidor = async function apagarVerificarServidor(pathEncoded) {
    const path = decodeURIComponent(pathEncoded);

    if (!confirm("Apagar este arquivo de VERIFICAR?")) return;

    if (typeof deleteItem === "function") {
      await deleteItem(path, "file");
      await carregarPainelVerificarServidor();
      return;
    }

    alert("Não encontrei a função de apagar nesta tela.");
  };

  const iniciar = () => {
    criarPainelVerificar();
    carregarPainelVerificarServidor();

    const originalLoadTree = window.loadTree;

    if (typeof originalLoadTree === "function" && !window.__CEJAS_LOADTREE_VERIFICAR_PATCH__) {
      window.__CEJAS_LOADTREE_VERIFICAR_PATCH__ = true;
      window.loadTree = async function patchedLoadTree() {
        const result = await originalLoadTree.apply(this, arguments);
        carregarPainelVerificarServidor();
        return result;
      };
    }
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", iniciar);
  } else {
    iniciar();
  }
})();
// CEJAS_VERIFICAR_PANEL_END
</script>
'''
    s = s.replace("</body>", painel_script + "\n</body>", 1)

html.write_text(s)
PY

node --check server.js

node <<'NODE'
const fs = require('fs');
const html = fs.readFileSync('servidor.html', 'utf8');
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync('.cejas-local-backups/check-servidor-modelo-final', { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-servidor-modelo-final/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-servidor-modelo-final/script-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-servidor-modelo-final

echo ""
echo "✅ Servidor corrigido no modelo final."
echo ""
echo "Estrutura correta agora:"
echo "01 JANEIRO / WEG 23.01 / WEG23.01 + BOLETO + DEMONSTRATIVO"
echo ""
echo "VERIFICAR agora mostra:"
echo "VERIFICAR / FEVEREIRO / arquivo.pdf com opções APAGAR e MOVER."
echo ""
echo "Agora rode:"
echo "npm run dev"
echo ""
echo "Abra:"
echo "http://localhost:5500/servidor.html"
