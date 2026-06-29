#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "servidor.html" ]; then
  echo "❌ Rode este comando dentro da pasta raiz do projeto, onde ficam server.js e servidor.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/servidor-inteligente-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js servidor.html "$BACKUP_DIR/"

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

server = Path("server.js")
s = server.read_text()

start_marker = 'const SERVIDOR_TMP_DIR = path.join(__dirname, "uploads", "tmp-servidor");'
end_marker = 'app.get("/api/servidor/arquivo", (req, res) => {'

if start_marker not in s or end_marker not in s:
    raise SystemExit("❌ Não encontrei o bloco do upload inteligente no server.js. Me mande o server.js atualizado.")

start = s.index(start_marker)
end = s.index(end_marker, start)

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
    files: 5000
  }
});

function normalizarTextoServidor(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function slugPastaServidor(texto, fallback = "_A_ORGANIZAR") {
  const limpo = String(texto || "")
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .trim();

  return limpo || fallback;
}

const MESES_SERVIDOR = [
  { numero: "01", nome: "JANEIRO", aliases: ["JANEIRO", "JAN"] },
  { numero: "02", nome: "FEVEREIRO", aliases: ["FEVEREIRO", "FEV"] },
  { numero: "03", nome: "MARÇO", aliases: ["MARCO", "MARÇO", "MAR"] },
  { numero: "04", nome: "ABRIL", aliases: ["ABRIL", "ABR"] },
  { numero: "05", nome: "MAIO", aliases: ["MAIO", "MAI"] },
  { numero: "06", nome: "JUNHO", aliases: ["JUNHO", "JUN"] },
  { numero: "07", nome: "JULHO", aliases: ["JULHO", "JUL"] },
  { numero: "08", nome: "AGOSTO", aliases: ["AGOSTO", "AGO"] },
  { numero: "09", nome: "SETEMBRO", aliases: ["SETEMBRO", "SET"] },
  { numero: "10", nome: "OUTUBRO", aliases: ["OUTUBRO", "OUT"] },
  { numero: "11", nome: "NOVEMBRO", aliases: ["NOVEMBRO", "NOV"] },
  { numero: "12", nome: "DEZEMBRO", aliases: ["DEZEMBRO", "DEZ"] }
];

const ENTIDADES_SERVIDOR = [
  {
    pasta: "PEV",
    aliases: ["PEV", "PROGRAMA EMPRESA VIVA", "EMPRESA VIVA"]
  },
  {
    pasta: "CDL",
    aliases: ["CDL", "CAMARA DE DIRIGENTES LOJISTAS", "CÂMARA DE DIRIGENTES LOJISTAS"]
  },
  {
    pasta: "SINDICATOS",
    aliases: ["SINDICATO", "SINDICATOS", "SINDICAL", "SIND"]
  },
  {
    pasta: "ASSIS",
    aliases: ["ASSIS"]
  }
];

const TIPOS_DOCUMENTO_ENTIDADE_SERVIDOR = [
  {
    pasta: "01 EVENTOS ENTIDADES",
    aliases: ["EVENTO", "EVENTOS", "ORCAMENTO", "ORÇAMENTO", "PROPOSTA", "BRIEFING", "PROJETO", "CONTRATACAO", "CONTRATAÇÃO"]
  },
  {
    pasta: "02 BOLETOS ENTIDADES",
    aliases: ["BOLETO", "BOLETOS", "FATURA", "FATURAS", "COBRANCA", "COBRANÇA", "PAGAMENTO", "PARCELA"]
  },
  {
    pasta: "03 DEMONSTRATIVOS ENTIDADES",
    aliases: ["DEMONSTRATIVO", "DEMONSTRATIVOS", "RELATORIO", "RELATÓRIO", "EXTRATO", "PRESTACAO", "PRESTAÇÃO"]
  },
  {
    pasta: "04 NOTAS E RECIBOS",
    aliases: ["NOTA FISCAL", "NFS", "NF", "RECIBO", "COMPROVANTE"]
  },
  {
    pasta: "05 CONTRATOS",
    aliases: ["CONTRATO", "CONTRATOS", "TERMO", "ADITIVO"]
  }
];

function pastaMesServidor(numeroMes) {
  const mes = MESES_SERVIDOR.find(item => item.numero === String(numeroMes).padStart(2, "0"));
  return mes ? `${mes.numero} ${mes.nome}` : "_MES_NAO_IDENTIFICADO";
}

function detectarAnoServidor(texto, anoPadrao) {
  const normal = String(texto || "");
  const anoCompleto = normal.match(/\b(20\d{2})\b/);
  if (anoCompleto) return anoCompleto[1];

  const dataAnoCurto = normal.match(/\b\d{1,2}[.\-_/]\d{1,2}[.\-_/](\d{2})\b/);
  if (dataAnoCurto) return `20${dataAnoCurto[1]}`;

  return String(anoPadrao || new Date().getFullYear());
}

function detectarMesServidor(texto) {
  const original = String(texto || "");
  const normalizado = normalizarTextoServidor(original);

  const dataIso = original.match(/\b(20\d{2})[.\-_/](0?[1-9]|1[0-2])[.\-_/](\d{1,2})\b/);
  if (dataIso) return String(dataIso[2]).padStart(2, "0");

  const dataCompleta = original.match(/\b(\d{1,2})[.\-_/](\d{1,2})[.\-_/](20\d{2}|\d{2})\b/);
  if (dataCompleta) return String(dataCompleta[2]).padStart(2, "0");

  const mesAno = original.match(/\b(0?[1-9]|1[0-2])[.\-_/](20\d{2}|\d{2})\b/);
  if (mesAno) return String(mesAno[1]).padStart(2, "0");

  for (const mes of MESES_SERVIDOR) {
    if (normalizado.includes(`${mes.numero} ${normalizarTextoServidor(mes.nome)}`)) return mes.numero;
    if (normalizado.includes(`${mes.numero}-${normalizarTextoServidor(mes.nome)}`)) return mes.numero;
    if (normalizado.includes(`${mes.numero}_${normalizarTextoServidor(mes.nome)}`)) return mes.numero;

    for (const alias of mes.aliases) {
      const aliasNormal = normalizarTextoServidor(alias);
      const re = new RegExp(`(^|[^A-Z0-9])${aliasNormal}([^A-Z0-9]|$)`);
      if (re.test(normalizado)) return mes.numero;
    }
  }

  const diaMes = original.match(/\b(\d{1,2})[.\-_/](\d{1,2})\b/);
  if (diaMes) return String(diaMes[2]).padStart(2, "0");

  return "";
}

function extrairDataServidor(texto, anoPadrao) {
  const original = String(texto || "");

  let match = original.match(/\b(20\d{2})[.\-_/](0?[1-9]|1[0-2])[.\-_/](\d{1,2})\b/);
  if (match) {
    return {
      ano: match[1],
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[3]).padStart(2, "0"),
      label: `${String(match[3]).padStart(2, "0")}.${String(match[2]).padStart(2, "0")}`
    };
  }

  match = original.match(/\b(\d{1,2})[.\-_/](\d{1,2})[.\-_/](20\d{2}|\d{2})\b/);
  if (match) {
    const ano = String(match[3]).length === 2 ? `20${match[3]}` : match[3];
    return {
      ano,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      label: `${String(match[1]).padStart(2, "0")}.${String(match[2]).padStart(2, "0")}`
    };
  }

  match = original.match(/\b(0?[1-9]|1[0-2])[.\-_/](20\d{2}|\d{2})\b/);
  if (match) {
    const ano = String(match[2]).length === 2 ? `20${match[2]}` : match[2];
    return {
      ano,
      mes: String(match[1]).padStart(2, "0"),
      dia: "",
      label: `${String(match[1]).padStart(2, "0")}.${ano}`
    };
  }

  const mes = detectarMesServidor(original);

  return {
    ano: detectarAnoServidor(original, anoPadrao),
    mes,
    dia: "",
    label: mes ? `${mes}.${detectarAnoServidor(original, anoPadrao)}` : ""
  };
}

function detectarEntidadeServidor(texto) {
  const normalizado = normalizarTextoServidor(texto);

  for (const entidade of ENTIDADES_SERVIDOR) {
    for (const alias of entidade.aliases) {
      const aliasNormal = normalizarTextoServidor(alias);
      const re = new RegExp(`(^|[^A-Z0-9])${aliasNormal}([^A-Z0-9]|$)`);
      if (re.test(normalizado)) return entidade;
    }
  }

  return null;
}

function detectarTipoDocumentoEntidadeServidor(texto) {
  const normalizado = normalizarTextoServidor(texto);

  for (const tipo of TIPOS_DOCUMENTO_ENTIDADE_SERVIDOR) {
    for (const alias of tipo.aliases) {
      const aliasNormal = normalizarTextoServidor(alias);
      const re = new RegExp(`(^|[^A-Z0-9])${aliasNormal}([^A-Z0-9]|$)`);
      if (re.test(normalizado)) return tipo.pasta;
    }
  }

  return "99 OUTROS DOCUMENTOS";
}

function limparNomeEventoServidor(nome) {
  let base = String(nome || "")
    .replace(/\.[a-zA-Z0-9]{2,8}$/g, "")
    .replace(/\\/g, "/")
    .split("/")
    .pop();

  base = base
    .replace(/\b(20\d{2})\b/g, "")
    .replace(/\b\d{1,2}[.\-_/]\d{1,2}([.\-_/](20\d{2}|\d{2}))?\b/g, "")
    .replace(/\b(ORCAMENTO|ORÇAMENTO|BOLETO|DEMONSTRATIVO|RECIBO|COMPROVANTE|NF|NFS|NOTA|FISCAL|CONTRATO|PDF|DOC|DOCUMENTO|EVENTO|EVENTOS|ENTIDADE|ENTIDADES)\b/gi, "")
    .replace(/[_\-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (!base || base.length < 3) return "_A_ORGANIZAR";

  return slugPastaServidor(base.toUpperCase());
}

function segmentoEhAnoOuMesServidor(segmento) {
  const n = normalizarTextoServidor(segmento);

  if (/^20\d{2}$/.test(n)) return true;
  if (detectarMesServidor(segmento)) return true;
  if (["CEJAS", "AREA DE TRABALHO", "DESKTOP", "DOWNLOADS", "DOCUMENTOS", "DOCUMENTS", "SERVIDOR", "ARQUIVOS"].includes(n)) return true;

  return false;
}

function detectarNomeEventoServidor(relativePath, fileName) {
  const partes = String(relativePath || "")
    .replace(/\\/g, "/")
    .split("/")
    .filter(Boolean);

  const filePart = partes[partes.length - 1] || fileName;
  let indiceMes = -1;

  for (let i = 0; i < partes.length; i++) {
    if (detectarMesServidor(partes[i])) {
      indiceMes = i;
      break;
    }
  }

  if (indiceMes >= 0 && partes[indiceMes + 1] && partes[indiceMes + 1] !== filePart) {
    return limparNomeEventoServidor(partes[indiceMes + 1]);
  }

  const possiveis = partes.slice(0, -1).filter(p => !segmentoEhAnoOuMesServidor(p));

  if (possiveis.length) {
    return limparNomeEventoServidor(possiveis[possiveis.length - 1]);
  }

  return limparNomeEventoServidor(fileName || filePart);
}

function destinoInteligenteServidor(originalPath, fileName, anoPadrao) {
  const texto = `${originalPath || ""} ${fileName || ""}`;
  const data = extrairDataServidor(texto, anoPadrao);
  const ano = data.ano || detectarAnoServidor(texto, anoPadrao);
  const mesNumero = data.mes || detectarMesServidor(texto);
  const mes = mesNumero ? pastaMesServidor(mesNumero) : "_A_ORGANIZAR";
  const nomeArquivo = slugPastaServidor(fileName || path.basename(originalPath || "arquivo"), "arquivo");
  const entidade = detectarEntidadeServidor(texto);

  if (entidade) {
    const tipoDocumento = detectarTipoDocumentoEntidadeServidor(texto);
    const grupoData = data.label ? `${entidade.pasta} - ${data.label}` : `${entidade.pasta} - SEM DATA`;

    return `${ano}/${mes}/ENTIDADES/${entidade.pasta}/${tipoDocumento}/${grupoData}/${nomeArquivo}`;
  }

  const evento = mesNumero ? detectarNomeEventoServidor(originalPath, fileName) : "_A_ORGANIZAR";
  return `${ano}/${mes}/${evento}/${nomeArquivo}`;
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

app.post("/api/servidor/upload-inteligente", servidorBulkUpload.array("arquivos"), (req, res) => {
  try {
    const files = req.files || [];
    let paths = req.body.paths || [];
    const anoPadrao = req.body.anoPadrao || new Date().getFullYear();

    if (!Array.isArray(paths)) paths = [paths];

    if (!files.length) {
      return res.status(400).json({
        ok: false,
        message: "Nenhum arquivo enviado."
      });
    }

    const salvos = [];
    const organizar = [];
    const entidades = {};

    files.forEach((file, index) => {
      const originalRelative = paths[index] || file.originalname;
      const destinoRelativo = destinoInteligenteServidor(originalRelative, file.originalname, anoPadrao);
      const target = caminhoUnicoServidor(safeServidorPath(destinoRelativo));
      const destinoFinalRelativo = path.relative(SERVIDOR_DIR, target).replace(/\\/g, "/");

      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.renameSync(file.path, target);

      salvos.push(destinoFinalRelativo);

      if (destinoFinalRelativo.includes("_A_ORGANIZAR") || destinoFinalRelativo.includes("SEM DATA")) {
        organizar.push(destinoFinalRelativo);
      }

      const entidade = detectarEntidadeServidor(`${originalRelative} ${file.originalname}`);
      if (entidade) entidades[entidade.pasta] = (entidades[entidade.pasta] || 0) + 1;
    });

    res.json({
      ok: true,
      saved: salvos.length,
      organizar: organizar.length,
      entidades,
      exemplos: salvos.slice(0, 8),
      message: `${salvos.length} arquivo(s) organizados. ${organizar.length} precisam de revisão em _A_ORGANIZAR ou SEM DATA.`
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro no upload inteligente: " + error.message
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

css_insert = r'''

    .upload-tools {
      display: grid;
      gap: 10px;
      grid-template-columns: 1fr;
    }

    .file-label.secondary {
      background: #1f2937;
      border-color: rgba(255,255,255,.18);
      box-shadow: none;
    }

    .drop-zone-servidor {
      margin-top: 12px;
      border: 1px dashed rgba(255,255,255,.2);
      background: rgba(255,255,255,.035);
      color: var(--muted);
      border-radius: 16px;
      padding: 14px;
      font-size: 13px;
      line-height: 1.45;
    }

    .drop-zone-servidor.dragover {
      border-color: rgba(255,97,210,.85);
      background: rgba(255,97,210,.09);
      color: #fff;
    }

    .upload-preview {
      max-height: 150px;
      overflow: auto;
      margin-top: 12px;
      padding: 10px;
      background: #0b0b10;
      border: 1px solid var(--border);
      border-radius: 14px;
      text-align: left;
      font-size: 12px;
      color: var(--muted);
      display: none;
    }

    .upload-preview div {
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      padding: 3px 0;
      border-bottom: 1px solid rgba(255,255,255,.05);
    }

    .upload-preview div:last-child {
      border-bottom: 0;
    }
'''

if ".upload-tools {" not in s:
    s = s.replace("    @media (max-width: 1200px) {", css_insert + "\n    @media (max-width: 1200px) {")

upload_start = '          <div class="upload-box">\n            <h3>Subir pasta completa</h3>'
upload_end = '\n          <div class="server-options">'

if upload_start not in s:
    raise SystemExit("❌ Não encontrei o bloco antigo de upload no servidor.html.")

start = s.index(upload_start)
end = s.index(upload_end, start)

novo_upload = '''          <div class="upload-box" id="dropZoneServidor">
            <h3>Subir arquivos e pastas</h3>
            <p>
              Envie arquivos soltos, uma pasta completa ou arraste várias pastas/arquivos ao mesmo tempo. No modo inteligente, o sistema organiza por ano, mês, entidade, tipo de documento e data.
            </p>

            <div class="upload-tools">
              <input id="folderInput" class="file-input" type="file" webkitdirectory directory multiple>
              <label class="file-label" for="folderInput">📁 Selecionar pasta</label>

              <input id="fileInput" class="file-input" type="file" multiple>
              <label class="file-label secondary" for="fileInput">📄 Selecionar arquivos soltos</label>
            </div>

            <div class="drop-zone-servidor">
              Ou arraste aqui várias pastas e arquivos juntos. Essa é a melhor opção para enviar mais de uma pasta ao mesmo tempo.
            </div>

            <div id="uploadStatus" class="upload-status">Nenhum arquivo selecionado.</div>
            <div id="uploadPreview" class="upload-preview"></div>
          </div>'''

s = s[:start] + novo_upload + s[end:]

options_start = '          <div class="server-options">'
button_marker = '\n\n          <button class="btn gradient" style="width:100%;justify-content:center;" onclick="uploadFolder()">'

if options_start not in s or button_marker not in s:
    raise SystemExit("❌ Não encontrei o bloco de opções/botão no servidor.html.")

start = s.index(options_start)
end = s.index(button_marker, start)

novo_options = '''          <div class="server-options">
            <div>
              <label>Forma de organização</label>

              <div class="radio-row">
                <label class="radio-card">
                  <input id="uploadModeAuto" type="radio" name="uploadMode" value="auto" checked onchange="toggleUploadDestination()">
                  Organizar automaticamente por entidade, mês, tipo e data
                </label>

                <label class="radio-card">
                  <input type="radio" name="uploadMode" value="direct" onchange="toggleUploadDestination()">
                  Enviar mantendo a pasta original
                </label>

                <label class="radio-card">
                  <input id="uploadModeMonth" type="radio" name="uploadMode" value="month" onchange="toggleUploadDestination()">
                  Enviar manualmente dentro de Ano / Mês
                </label>
              </div>
            </div>

            <div id="autoDestinationBox">
              <label>Ano padrão quando o nome do arquivo não trouxer ano</label>

              <select id="autoYear">
                <option value="2025">2025</option>
                <option value="2026" selected>2026</option>
                <option value="2027">2027</option>
                <option value="2028">2028</option>
                <option value="2029">2029</option>
                <option value="2030">2030</option>
              </select>

              <div class="upload-status">
                Regras do modo inteligente: PEV, CDL, Sindicatos e Assis vão para ENTIDADES. Boletos, eventos, demonstrativos, notas e contratos entram em subpastas próprias. Arquivos sem mês ou sem data ficam marcados para revisão.
              </div>
            </div>

            <div id="monthDestinationBox" style="display:none;">
              <label>Destino manual do envio</label>

              <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
                <select id="uploadYear">
                  <option value="2026">2026</option>
                  <option value="2027">2027</option>
                  <option value="2028">2028</option>
                  <option value="2029">2029</option>
                  <option value="2030">2030</option>
                </select>

                <select id="uploadMonth">
                  <option value="01 JANEIRO">01 JANEIRO</option>
                  <option value="02 FEVEREIRO">02 FEVEREIRO</option>
                  <option value="03 MARÇO">03 MARÇO</option>
                  <option value="04 ABRIL">04 ABRIL</option>
                  <option value="05 MAIO">05 MAIO</option>
                  <option value="06 JUNHO">06 JUNHO</option>
                  <option value="07 JULHO">07 JULHO</option>
                  <option value="08 AGOSTO">08 AGOSTO</option>
                  <option value="09 SETEMBRO">09 SETEMBRO</option>
                  <option value="10 OUTUBRO">10 OUTUBRO</option>
                  <option value="11 NOVEMBRO">11 NOVEMBRO</option>
                  <option value="12 DEZEMBRO">12 DEZEMBRO</option>
                </select>
              </div>
            </div>

            <div>
              <label>Criar estrutura automática</label>

              <div class="year-actions">
                <input id="structureYear" value="2026" maxlength="4" placeholder="Ano, ex: 2026">
                <button class="btn" type="button" onclick="createYearStructure()">Criar ano</button>
              </div>
            </div>
          </div>'''

s = s[:start] + novo_options + s[end:]

s = s.replace('''          <button class="btn gradient" style="width:100%;justify-content:center;" onclick="uploadFolder()">
            Enviar pasta para o servidor
          </button>''', '''          <button class="btn gradient" style="width:100%;justify-content:center;" onclick="uploadFolder()">
            Enviar para o servidor
          </button>

          <button class="btn" style="width:100%;justify-content:center;margin-top:10px;" onclick="clearSelectedFiles()">
            Limpar seleção
          </button>''')

s = s.replace('''            <strong>Como organizar</strong>
            Exemplo: 2026 / Junho / Evento X / orçamento.pdf, boleto.pdf e demonstrativo.pdf. Você também pode criar 2027, 2028 e anos posteriores.''', '''            <strong>Como o modo inteligente organiza</strong>
            Exemplo de entidade: 2026 / 01 JANEIRO / ENTIDADES / CDL / 02 BOLETOS ENTIDADES / CDL - 15.01 / boleto.pdf. Eventos comuns seguem por ano, mês e nome do evento.''')

js_start = '    document.getElementById("folderInput").addEventListener("change", () => {'
js_end = '\n\n    loadTree();'

if js_start not in s:
    raise SystemExit("❌ Não encontrei o JavaScript antigo do upload no servidor.html.")

start = s.index(js_start)
end = s.index(js_end, start)

novo_js = r'''    let selectedServidorFiles = [];

    function mergeSelectedFiles(filesWithPaths) {
      const map = new Map(selectedServidorFiles.map(item => [item.path + "::" + item.file.size, item]));

      filesWithPaths.forEach(item => {
        if (!item || !item.file) return;
        const key = `${item.path || item.file.name}::${item.file.size}`;
        map.set(key, {
          file: item.file,
          path: item.path || item.file.webkitRelativePath || item.file.name
        });
      });

      selectedServidorFiles = [...map.values()];
      updateSelectedFilesUI();
    }

    function updateSelectedFilesUI() {
      const status = document.getElementById("uploadStatus");
      const preview = document.getElementById("uploadPreview");
      const totalSize = selectedServidorFiles.reduce((acc, item) => acc + Number(item.file.size || 0), 0);

      status.textContent = selectedServidorFiles.length
        ? `${selectedServidorFiles.length} arquivo(s) selecionado(s) • ${formatBytes(totalSize)}`
        : "Nenhum arquivo selecionado.";

      if (!selectedServidorFiles.length) {
        preview.style.display = "none";
        preview.innerHTML = "";
        return;
      }

      preview.style.display = "block";
      preview.innerHTML = selectedServidorFiles
        .slice(0, 40)
        .map(item => `<div>• ${item.path}</div>`)
        .join("") + (selectedServidorFiles.length > 40 ? `<div>+ ${selectedServidorFiles.length - 40} arquivo(s)...</div>` : "");
    }

    function clearSelectedFiles() {
      selectedServidorFiles = [];
      document.getElementById("folderInput").value = "";
      document.getElementById("fileInput").value = "";
      updateSelectedFilesUI();
    }

    document.getElementById("folderInput").addEventListener("change", () => {
      const files = [...document.getElementById("folderInput").files].map(file => ({
        file,
        path: file.webkitRelativePath || file.name
      }));

      mergeSelectedFiles(files);
    });

    document.getElementById("fileInput").addEventListener("change", () => {
      const files = [...document.getElementById("fileInput").files].map(file => ({
        file,
        path: file.name
      }));

      mergeSelectedFiles(files);
    });

    function readEntryAsFile(entry, basePath = "") {
      return new Promise((resolve, reject) => {
        if (entry.isFile) {
          entry.file(file => {
            resolve([{ file, path: `${basePath}${file.name}` }]);
          }, reject);
          return;
        }

        if (!entry.isDirectory) {
          resolve([]);
          return;
        }

        const reader = entry.createReader();
        const allEntries = [];

        function readBatch() {
          reader.readEntries(async entries => {
            if (!entries.length) {
              try {
                const nested = await Promise.all(allEntries.map(child => readEntryAsFile(child, `${basePath}${entry.name}/`)));
                resolve(nested.flat());
              } catch (error) {
                reject(error);
              }
              return;
            }

            allEntries.push(...entries);
            readBatch();
          }, reject);
        }

        readBatch();
      });
    }

    async function handleServidorDrop(event) {
      event.preventDefault();

      const dropZone = document.getElementById("dropZoneServidor");
      dropZone.classList.remove("dragover");

      const items = [...(event.dataTransfer.items || [])];
      const files = [];

      if (items.length && items[0].webkitGetAsEntry) {
        for (const item of items) {
          const entry = item.webkitGetAsEntry();
          if (!entry) continue;
          files.push(...await readEntryAsFile(entry));
        }
      } else {
        files.push(...[...(event.dataTransfer.files || [])].map(file => ({ file, path: file.name })));
      }

      mergeSelectedFiles(files);
    }

    const dropZoneServidor = document.getElementById("dropZoneServidor");

    dropZoneServidor.addEventListener("dragover", (event) => {
      event.preventDefault();
      dropZoneServidor.classList.add("dragover");
    });

    dropZoneServidor.addEventListener("dragleave", () => {
      dropZoneServidor.classList.remove("dragover");
    });

    dropZoneServidor.addEventListener("drop", handleServidorDrop);

    function toggleUploadDestination() {
      const mode = document.querySelector("input[name='uploadMode']:checked")?.value || "auto";
      document.getElementById("monthDestinationBox").style.display = mode === "month" ? "block" : "none";
      document.getElementById("autoDestinationBox").style.display = mode === "auto" ? "block" : "none";
    }

    function getUploadMode() {
      return document.querySelector("input[name='uploadMode']:checked")?.value || "auto";
    }

    async function createYearStructure() {
      const ano = document.getElementById("structureYear").value.trim();

      if (!/^\d{4}$/.test(ano)) {
        alert("Informe um ano válido, exemplo: 2026.");
        return;
      }

      const response = await fetch("/api/servidor/criar-estrutura", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ ano })
      });

      const data = await response.json();

      if (!data.ok) {
        alert(data.message || "Erro ao criar estrutura.");
        return;
      }

      alert(data.message);
      await loadTree();
    }

    function getUploadDestination() {
      const mode = document.querySelector("input[name='uploadMode']:checked")?.value || "auto";

      if (mode !== "month") return "";

      const year = document.getElementById("uploadYear").value;
      const month = document.getElementById("uploadMonth").value;

      return `${year}/${month}`;
    }

    async function uploadFolder() {
      const status = document.getElementById("uploadStatus");
      const files = selectedServidorFiles;

      if (!files.length) {
        alert("Selecione arquivos, uma pasta ou arraste várias pastas primeiro.");
        return;
      }

      const formData = new FormData();
      const mode = getUploadMode();
      const endpoint = mode === "auto"
        ? "/api/servidor/upload-inteligente"
        : "/api/servidor/upload";

      const destino = getUploadDestination();
      formData.append("destino", destino);

      if (mode === "auto") {
        formData.append("anoPadrao", document.getElementById("autoYear")?.value || new Date().getFullYear());
      }

      files.forEach(item => {
        formData.append("arquivos", item.file);
        formData.append("paths", item.path || item.file.name);
      });

      const destinoLabel = mode === "auto" ? "organização inteligente" : getUploadDestination();
      status.textContent = destinoLabel
        ? `Enviando para ${destinoLabel}...`
        : "Enviando para o servidor...";

      try {
        const response = await fetch(endpoint, {
          method: "POST",
          body: formData
        });

        const contentType = response.headers.get("content-type") || "";
        const data = contentType.includes("application/json")
          ? await response.json()
          : {
              ok: false,
              message: response.redirected
                ? "Sua sessão expirou. Faça login novamente e tente enviar os arquivos."
                : `Resposta inesperada do servidor (${response.status}).`
            };

        if (!response.ok || !data.ok) {
          throw new Error(data.message || "Erro ao enviar.");
        }

        const exemplos = Array.isArray(data.exemplos) && data.exemplos.length
          ? " Ex.: " + data.exemplos.slice(0, 3).join(" | ")
          : "";

        status.textContent = (data.message || "Envio concluído.") + exemplos;
        clearSelectedFiles();

        await loadTree();
      } catch (error) {
        status.textContent = "Erro: " + error.message;
        alert("Erro ao enviar: " + error.message);
      }
    }

    toggleUploadDestination();'''

s = s[:start] + novo_js + s[end:]
html.write_text(s)
PY

node --check server.js

python3 <<'PY'
from pathlib import Path
import re
s = Path("servidor.html").read_text()
scripts = re.findall(r"<script>(.*?)</script>", s, re.S)

for i, script in enumerate(scripts, 1):
    Path(f".cejas-local-backups/check-servidor-script-{i}.js").write_text(script)
PY

for f in .cejas-local-backups/check-servidor-script-*.js; do
  node --check "$f"
done

rm -f .cejas-local-backups/check-servidor-script-*.js

echo ""
echo "✅ Servidor inteligente aplicado com sucesso."
echo ""
echo "Agora rode:"
echo "npm run dev"
echo ""
echo "Depois abra:"
echo "http://localhost:5500/servidor.html"
