#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "servidor.html" ]; then
  echo "❌ Rode este comando dentro da pasta raiz do projeto, onde ficam server.js e servidor.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/servidor-mobile-relatorio-$STAMP"
mkdir -p "$BACKUP_DIR"
cp server.js servidor.html importar-relatorio.html agenda.html dashboard.html "$BACKUP_DIR/" 2>/dev/null || true
[ -d css ] && cp -R css "$BACKUP_DIR/css" 2>/dev/null || true
[ -d js ] && cp -R js "$BACKUP_DIR/js" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

p = Path('server.js')
s = p.read_text()

start_marker = '// CEJAS_FIX_RELATORIO_DELETE_START'
end_marker = 'app.delete("/api/relatorio-atual", async (_req, res) => {'
if start_marker in s and end_marker in s:
    start = s.index(start_marker)
    end = s.index(end_marker, start)
    replacement = '''// CEJAS_FIX_RELATORIO_DELETE_START\n// Não responder vazio aqui: deixa a rota principal tentar carregar local ou Supabase.\napp.get("/api/relatorio-atual", (_req, _res, next) => next());\n\n'''
    s = s[:start] + replacement + s[end:]

block_start = 'const SERVIDOR_TMP_DIR = path.join(__dirname, "uploads", "tmp-servidor");'
block_end = 'app.get("/api/servidor/arquivo", (req, res) => {'
if block_start in s and block_end in s:
    start = s.index(block_start)
    end = s.index(block_end, start)
else:
    if block_end not in s:
        raise SystemExit('❌ Não encontrei onde inserir o upload inteligente no server.js.')
    start = end = s.index(block_end)

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

function normalizarTextoServidor(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function slugPastaServidor(texto, fallback = "VERIFICAR") {
  const limpo = String(texto || "")
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .trim();

  return limpo || fallback;
}

function nomeArquivoSeguroServidor(texto, fallback = "arquivo") {
  return slugPastaServidor(texto, fallback).replace(/^\.+/, fallback);
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
  { pasta: "PEV", aliases: ["PEV", "PROGRAMA EMPRESA VIVA", "EMPRESA VIVA"] },
  { pasta: "CDL", aliases: ["CDL", "CAMARA DE DIRIGENTES LOJISTAS", "CÂMARA DE DIRIGENTES LOJISTAS"] },
  { pasta: "SINDICATOS", aliases: ["SINDICATO", "SINDICATOS", "SINDICAL", "SIND"] },
  { pasta: "ASSIS", aliases: ["ASSIS"] }
];

const TIPOS_DOCUMENTO_SERVIDOR = [
  { id: "boleto", pasta: "02 BOLETOS ENTIDADES", geral: "BOLETOS", aliases: ["BOLETO", "BOLETOS", "FATURA", "FATURAS", "COBRANCA", "COBRANÇA", "PAGAMENTO", "PARCELA"] },
  { id: "evento", pasta: "01 EVENTOS ENTIDADES", geral: "EVENTOS", aliases: ["EVENTO", "EVENTOS", "ORCAMENTO", "ORÇAMENTO", "PROPOSTA", "BRIEFING", "PROJETO", "CONTRATACAO", "CONTRATAÇÃO"] },
  { id: "demonstrativo", pasta: "03 DEMONSTRATIVOS ENTIDADES", geral: "DEMONSTRATIVOS", aliases: ["DEMONSTRATIVO", "DEMONSTRATIVOS", "RELATORIO", "RELATÓRIO", "EXTRATO", "PRESTACAO", "PRESTAÇÃO"] },
  { id: "nota", pasta: "04 NOTAS E RECIBOS", geral: "NOTAS E RECIBOS", aliases: ["NOTA FISCAL", "NOTAS FISCAIS", "NFS", "NF", "RECIBO", "COMPROVANTE"] },
  { id: "contrato", pasta: "05 CONTRATOS", geral: "CONTRATOS", aliases: ["CONTRATO", "CONTRATOS", "TERMO", "ADITIVO"] }
];

function pastaMesServidor(numeroMes) {
  const mes = MESES_SERVIDOR.find(item => item.numero === String(numeroMes).padStart(2, "0"));
  return mes ? `${mes.numero} ${mes.nome}` : "VERIFICAR MES";
}

function regexPalavraServidor(alias) {
  const aliasNormal = normalizarTextoServidor(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^A-Z0-9])${aliasNormal}([^A-Z0-9]|$)`);
}

function detectarMesPorNomeServidor(texto) {
  const normalizado = normalizarTextoServidor(texto);

  for (const mes of MESES_SERVIDOR) {
    for (const alias of mes.aliases) {
      if (regexPalavraServidor(alias).test(normalizado)) return mes.numero;
    }
  }

  return "";
}

function detectarDataServidor(texto, anoPadrao) {
  const original = String(texto || "");
  const anoDefault = String(anoPadrao || new Date().getFullYear());

  let match = original.match(/\b(20\d{2})[.\-_/](0?[1-9]|1[0-2])[.\-_/](\d{1,2})\b/);
  if (match) {
    return {
      ano: match[1],
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[3]).padStart(2, "0"),
      label: `${String(match[3]).padStart(2, "0")}.${String(match[2]).padStart(2, "0")}`,
      precisao: "dia"
    };
  }

  match = original.match(/\b(\d{1,2})[.\-_/](\d{1,2})[.\-_/](20\d{2}|\d{2})\b/);
  if (match) {
    const ano = String(match[3]).length === 2 ? `20${match[3]}` : match[3];
    return {
      ano,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      label: `${String(match[1]).padStart(2, "0")}.${String(match[2]).padStart(2, "0")}`,
      precisao: "dia"
    };
  }

  match = original.match(/(?:^|[^\d])(\d{1,2})\s*(?:do|de)?\s*(0?[1-9]|1[0-2])(?:\s*(?:de|do)?\s*(20\d{2}|\d{2}))?(?:[^\d]|$)/i);
  if (match) {
    const ano = match[3]
      ? (String(match[3]).length === 2 ? `20${match[3]}` : match[3])
      : anoDefault;

    return {
      ano,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      label: `${String(match[1]).padStart(2, "0")}.${String(match[2]).padStart(2, "0")}`,
      precisao: "dia"
    };
  }

  match = original.match(/\b(0?[1-9]|1[0-2])[.\-_/](20\d{2}|\d{2})\b/);
  if (match) {
    const ano = String(match[2]).length === 2 ? `20${match[2]}` : match[2];
    return {
      ano,
      mes: String(match[1]).padStart(2, "0"),
      dia: "",
      label: `${String(match[1]).padStart(2, "0")}.${ano}`,
      precisao: "mes"
    };
  }

  const mesPorNome = detectarMesPorNomeServidor(original);
  const anoCompleto = original.match(/\b(20\d{2})\b/);

  if (mesPorNome) {
    const ano = anoCompleto ? anoCompleto[1] : anoDefault;
    return {
      ano,
      mes: mesPorNome,
      dia: "",
      label: `${mesPorNome}.${ano}`,
      precisao: "mes"
    };
  }

  return {
    ano: anoCompleto ? anoCompleto[1] : anoDefault,
    mes: "",
    dia: "",
    label: "SEM DATA",
    precisao: "nenhuma"
  };
}

function detectarEntidadeServidor(texto) {
  const normalizado = normalizarTextoServidor(texto);

  for (const entidade of ENTIDADES_SERVIDOR) {
    for (const alias of entidade.aliases) {
      if (regexPalavraServidor(alias).test(normalizado)) return entidade;
    }
  }

  return null;
}

function detectarContextoEntidadeServidor(texto) {
  const normalizado = normalizarTextoServidor(texto);
  return Boolean(
    detectarEntidadeServidor(texto) ||
    regexPalavraServidor("ENTIDADE").test(normalizado) ||
    regexPalavraServidor("ENTIDADES").test(normalizado) ||
    normalizado.includes("EVENTOS ENTIDADES") ||
    normalizado.includes("BOLETOS ENTIDADES")
  );
}

function detectarTipoDocumentoServidor(texto) {
  const normalizado = normalizarTextoServidor(texto);

  for (const tipo of TIPOS_DOCUMENTO_SERVIDOR) {
    for (const alias of tipo.aliases) {
      if (regexPalavraServidor(alias).test(normalizado)) return tipo;
    }
  }

  return null;
}

function removerDatasDoNomeServidor(texto) {
  return String(texto || "")
    .replace(/\b20\d{2}[.\-_/](0?[1-9]|1[0-2])[.\-_/]\d{1,2}\b/g, " ")
    .replace(/\b\d{1,2}[.\-_/]\d{1,2}[.\-_/](20\d{2}|\d{2})\b/g, " ")
    .replace(/\b\d{1,2}[.\-_/]\d{1,2}\b/g, " ")
    .replace(/\b(0?[1-9]|1[0-2])[.\-_/](20\d{2}|\d{2})\b/g, " ")
    .replace(/\b\d{1,2}\s*(do|de)?\s*(0?[1-9]|1[0-2])\s*((de|do)?\s*(20\d{2}|\d{2}))?\b/gi, " ");
}

function limparNomeDocumentoServidor(originalPath, fileName) {
  const partes = String(originalPath || fileName || "")
    .replace(/\\/g, "/")
    .split("/")
    .filter(Boolean);

  const baseArquivo = path.basename(String(fileName || partes[partes.length - 1] || "arquivo"), path.extname(String(fileName || "")));
  const candidatos = [baseArquivo, ...partes.slice(0, -1).reverse()];

  for (const candidato of candidatos) {
    let base = path.basename(String(candidato || ""), path.extname(String(candidato || "")));

    base = removerDatasDoNomeServidor(base)
      .replace(/\b(BOLETO|BOLETOS|FATURA|FATURAS|EVENTO|EVENTOS|ENTIDADE|ENTIDADES|ORCAMENTO|ORÇAMENTO|DEMONSTRATIVO|RELATORIO|RELATÓRIO|RECIBO|COMPROVANTE|NOTA|FISCAL|CONTRATO|PDF|DOC|DOCX|XLS|XLSX)\b/gi, " ")
      .replace(/[_\-.]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();

    if (base.length >= 3) return slugPastaServidor(base.toUpperCase());
  }

  return slugPastaServidor(baseArquivo.toUpperCase(), "VERIFICAR");
}

function montarPastaDocumentoServidor(data, titulo) {
  const nome = slugPastaServidor(titulo, "VERIFICAR");

  if (data.precisao === "dia") return `${data.label} - ${nome}`;
  if (data.precisao === "mes") return `${data.label} - ${nome}`;

  return nome;
}

function destinoInteligenteServidor(originalPath, fileName, anoPadrao) {
  const texto = `${originalPath || ""} ${fileName || ""}`;
  const data = detectarDataServidor(texto, anoPadrao);
  const mes = data.mes ? pastaMesServidor(data.mes) : "VERIFICAR";
  const entidade = detectarEntidadeServidor(texto);
  const contextoEntidade = detectarContextoEntidadeServidor(texto);
  const tipo = detectarTipoDocumentoServidor(texto);
  const nomeArquivo = nomeArquivoSeguroServidor(fileName || path.basename(originalPath || "arquivo"), "arquivo");
  const titulo = limparNomeDocumentoServidor(originalPath, fileName);
  const pastaDocumento = montarPastaDocumentoServidor(data, titulo);

  if (contextoEntidade) {
    if (!data.mes) {
      const entidadePasta = entidade ? entidade.pasta : "ENTIDADE NAO IDENTIFICADA";
      return `${data.ano}/VERIFICAR/ENTIDADES/${entidadePasta}/${pastaDocumento}/${nomeArquivo}`;
    }

    if (!entidade) {
      const tipoVerificacao = tipo ? tipo.geral : "TIPO NAO IDENTIFICADO";
      return `${data.ano}/${mes}/VERIFICAR/ENTIDADES/${tipoVerificacao}/${pastaDocumento}/${nomeArquivo}`;
    }

    if (!tipo) {
      return `${data.ano}/${mes}/ENTIDADES/${entidade.pasta}/VERIFICAR/${pastaDocumento}/${nomeArquivo}`;
    }

    return `${data.ano}/${mes}/ENTIDADES/${entidade.pasta}/${tipo.pasta}/${pastaDocumento}/${nomeArquivo}`;
  }

  if (tipo && tipo.id === "boleto") {
    if (!data.mes) {
      return `${data.ano}/VERIFICAR/BOLETOS/${pastaDocumento}/${nomeArquivo}`;
    }

    return `${data.ano}/${mes}/VERIFICAR/BOLETOS/${pastaDocumento}/${nomeArquivo}`;
  }

  if (!data.mes) {
    return `${data.ano}/VERIFICAR/SEM DATA/${pastaDocumento}/${nomeArquivo}`;
  }

  if (tipo && tipo.id !== "evento") {
    return `${data.ano}/${mes}/DOCUMENTOS/${tipo.geral}/${pastaDocumento}/${nomeArquivo}`;
  }

  return `${data.ano}/${mes}/EVENTOS/${pastaDocumento}/${nomeArquivo}`;
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
    const entidades = {};
    const tipos = {};

    files.forEach((file, index) => {
      const originalRelative = paths[index] || file.originalname;
      const destinoRelativo = destinoInteligenteServidor(originalRelative, file.originalname, anoPadrao);
      const target = caminhoUnicoServidor(safeServidorPath(destinoRelativo));
      const destinoFinalRelativo = path.relative(SERVIDOR_DIR, target).replace(/\\/g, "/");

      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.renameSync(file.path, target);

      salvos.push(destinoFinalRelativo);

      if (destinoFinalRelativo.includes("/VERIFICAR/") || destinoFinalRelativo.includes("/VERIFICAR") || destinoFinalRelativo.includes("SEM DATA")) {
        verificar.push(destinoFinalRelativo);
      }

      const entidade = detectarEntidadeServidor(`${originalRelative} ${file.originalname}`);
      const tipo = detectarTipoDocumentoServidor(`${originalRelative} ${file.originalname}`);
      if (entidade) entidades[entidade.pasta] = (entidades[entidade.pasta] || 0) + 1;
      if (tipo) tipos[tipo.geral] = (tipos[tipo.geral] || 0) + 1;
    });

    res.json({
      ok: true,
      saved: salvos.length,
      verificar: verificar.length,
      organizar: verificar.length,
      entidades,
      tipos,
      exemplos: salvos.slice(0, 10),
      message: `${salvos.length} arquivo(s) organizados em pastas próprias. ${verificar.length} foram enviados para VERIFICAR.`
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

old = '''    if (!fs.existsSync(destinoDir) || !fs.statSync(destinoDir).isDirectory()) {
      return res.status(400).json({
        ok: false,
        message: "Destino precisa ser uma pasta existente."
      });
    }
'''
new = '''    if (!fs.existsSync(destinoDir)) {
      fs.mkdirSync(destinoDir, { recursive: true });
    }

    if (!fs.statSync(destinoDir).isDirectory()) {
      return res.status(400).json({
        ok: false,
        message: "Destino precisa ser uma pasta."
      });
    }
'''
if old in s:
    s = s.replace(old, new, 1)

fallback_marker = 'function emptySuperaReport() {'
if 'async function carregarRelatorioAtualDoSupabaseServidor' not in s and fallback_marker in s:
    helper = r'''
function isoParaDataBRServidor(iso) {
  if (!iso || !String(iso).includes("-")) return "";
  const [ano, mes, dia] = String(iso).slice(0, 10).split("-");
  if (!ano || !mes || !dia) return "";
  return `${dia}/${mes}/${ano}`;
}

function relatorioCejasVazioServidor(report) {
  const eventos = Array.isArray(report?.eventos) ? report.eventos : [];
  const resumo = report?.resumo || {};

  return !eventos.length &&
    !Number(resumo.totalEventos || 0) &&
    !Number(resumo.faturamentoPrevisto || 0) &&
    !Number(resumo.receitaConfirmada || 0);
}

async function carregarRelatorioAtualDoSupabaseServidor() {
  try {
    const { supabaseAdmin, isSupabaseConfigured } = require("./lib/supabase");

    if (!isSupabaseConfigured || !isSupabaseConfigured() || !supabaseAdmin) return null;

    const relatorios = await supabaseAdmin
      .from("cejas_relatorios")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(1);

    if (relatorios.error || !relatorios.data || !relatorios.data.length) return null;

    const relatorio = relatorios.data[0];

    const eventosQuery = await supabaseAdmin
      .from("cejas_eventos")
      .select("*")
      .eq("relatorio_id", relatorio.id)
      .order("data_evento", { ascending: true });

    if (eventosQuery.error) return null;

    const eventos = (eventosQuery.data || []).map((evento) => ({
      data: isoParaDataBRServidor(evento.data_evento),
      horaInicial: evento.hora_inicial || "",
      horaFinal: evento.hora_final || "",
      sala: evento.sala || "",
      empresa: evento.empresa || "",
      evento: evento.evento || "",
      status: evento.status || "em_espera",
      participantes: Number(evento.participantes || 0),
      valor: Number(evento.valor || 0),
      desconto: Number(evento.desconto || 0),
      produtos: evento.produtos || [],
      blocoOriginal: evento.bloco_original || ""
    }));

    const report = {
      atualizadoEm: relatorio.created_at || new Date().toISOString(),
      arquivo: relatorio.nome_arquivo || "relatorio-supabase.pdf",
      origem: "supabase",
      resumo: {
        faturamentoPrevisto: Number(relatorio.faturamento_previsto || 0),
        receitaConfirmada: Number(relatorio.receita_confirmada || 0),
        descontosAplicados: Number(relatorio.descontos_aplicados || 0),
        eventosConfirmados: Number(relatorio.eventos_confirmados || 0),
        eventosPendentes: Number(relatorio.eventos_em_espera || 0),
        eventosCancelados: Number(relatorio.eventos_cancelados || 0),
        totalEventos: Number(relatorio.total_eventos || eventos.length)
      },
      eventos,
      salas: [],
      produtos: []
    };

    return report;
  } catch (error) {
    console.warn("⚠️ Não foi possível carregar relatório do Supabase:", error.message);
    return null;
  }
}

'''
    s = s.replace(fallback_marker, helper + fallback_marker, 1)

route_start = 'app.get("/api/relatorio-atual", (_req, res) => {'
route_end = 'app.post("/api/importar-relatorio", (req, res, next) => {'
if route_start in s and route_end in s:
    a = s.index(route_start)
    b = s.index(route_end, a)
    route = r'''app.get("/api/relatorio-atual", async (_req, res) => {
  try {
    let report = null;

    if (fs.existsSync(RELATORIO_FILE)) {
      try {
        report = JSON.parse(fs.readFileSync(RELATORIO_FILE, "utf8"));
      } catch {
        report = null;
      }
    }

    if (!report || relatorioCejasVazioServidor(report)) {
      const supabaseReport = await carregarRelatorioAtualDoSupabaseServidor();

      if (supabaseReport && !relatorioCejasVazioServidor(supabaseReport)) {
        fs.writeFileSync(RELATORIO_FILE, JSON.stringify(supabaseReport, null, 2), "utf8");
        report = supabaseReport;
      }
    }

    if (!report) {
      report = emptySuperaReport();
      fs.writeFileSync(RELATORIO_FILE, JSON.stringify(report, null, 2), "utf8");
    }

    res.json({
      ok: true,
      report
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar relatório: " + error.message
    });
  }
});

'''
    s = s[:a] + route + s[b:]

old_import = '''    fs.writeFileSync(RELATORIO_FILE, JSON.stringify(report, null, 2), "utf8");

    console.log("✅ Relatório processado:", report.resumo);'''
new_import = '''    fs.writeFileSync(RELATORIO_FILE, JSON.stringify(report, null, 2), "utf8");

    let syncSupabase = null;
    try {
      syncSupabase = await syncRelatorioAtualComSupabase({ reportPath: RELATORIO_FILE });
      console.log("✅ Relatório sincronizado com Supabase:", syncSupabase);
    } catch (syncError) {
      syncSupabase = { ok: false, message: syncError.message };
      console.warn("⚠️ Relatório salvo localmente, mas não sincronizou com Supabase:", syncError.message);
    }

    console.log("✅ Relatório processado:", report.resumo);'''
if old_import in s:
    s = s.replace(old_import, new_import, 1)

old_response = '''    res.json({
      ok: true,
      message: "Relatório importado com sucesso.",
      report
    });'''
new_response = '''    res.json({
      ok: true,
      message: syncSupabase && syncSupabase.ok
        ? "Relatório importado e sincronizado para todos os dispositivos."
        : "Relatório importado localmente. Verifique a configuração do Supabase para aparecer em celular/tablet.",
      report,
      syncSupabase
    });'''
if old_response in s:
    s = s.replace(old_response, new_response, 1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path('servidor.html')
s = p.read_text()

s = s.replace(
'''              Envie arquivos soltos, uma pasta completa ou arraste várias pastas/arquivos ao mesmo tempo. No modo inteligente, o sistema organiza por ano, mês, entidade, tipo de documento e data.''',
'''              Envie vários arquivos soltos, uma pasta completa ou arraste várias pastas/arquivos ao mesmo tempo. No modo inteligente, cada arquivo vira uma pasta própria. O que o sistema não entender cai em VERIFICAR para você mover depois.'''
)

s = s.replace(
'''                Regras do modo inteligente: PEV, CDL, Sindicatos e Assis vão para ENTIDADES. Boletos, eventos, demonstrativos, notas e contratos entram em subpastas próprias. Arquivos sem mês ou sem data ficam marcados para revisão.''',
'''                Regras do modo inteligente: arquivos soltos nunca ficam soltos; cada um ganha uma pasta. Entidades como PEV, CDL, Sindicatos e Assis são destrinchadas uma a uma. Boleto sem entidade clara e arquivo sem data vão para VERIFICAR.'''
)

s = s.replace(
'''            Exemplo de entidade: 2026 / 01 JANEIRO / ENTIDADES / CDL / 02 BOLETOS ENTIDADES / CDL - 15.01 / boleto.pdf. Eventos comuns seguem por ano, mês e nome do evento.''',
'''            Exemplo de entidade: 2026 / 01 JANEIRO / ENTIDADES / CDL / 02 BOLETOS ENTIDADES / 15.01 - CAFÉ / boleto.pdf. Exemplo de evento solto: 2027 / 01 JANEIRO / EVENTOS / 15.01 - NOME DO EVENTO / arquivo.pdf. O que não for entendido entra em VERIFICAR.'''
)

if 'async function moveItemServidor' not in s:
    marker = '    async function deleteItem(path, type) {'
    insert = r'''    async function moveItemServidor(path) {
      const sugestao = path.includes("VERIFICAR") ? "2026/01 JANEIRO/EVENTOS" : "2026/VERIFICAR";
      const destino = prompt(
        "Digite a pasta de destino. Exemplo: 2026/01 JANEIRO/EVENTOS ou 2026/01 JANEIRO/ENTIDADES/CDL/02 BOLETOS ENTIDADES",
        sugestao
      );

      if (!destino) return;

      const response = await fetch("/api/servidor/mover", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ origem: path, destinoPasta: destino })
      });

      const data = await response.json();

      if (!data.ok) {
        alert(data.message || "Erro ao mover item.");
        return;
      }

      alert("Movido com sucesso.");
      await loadTree();
    }

'''
    if marker in s:
        s = s.replace(marker, insert + marker, 1)

s = s.replace(
'''                    <button class="mini" onclick="toggleFolder('${item.path.replace(/'/g, "\\'")}')">Abrir</button>
                    <button class="mini red" onclick="deleteItem('${item.path.replace(/'/g, "\\'")}', 'folder')">Excluir</button>''',
'''                    <button class="mini" onclick="toggleFolder('${item.path.replace(/'/g, "\\'")}')">Abrir</button>
                    <button class="mini" onclick="moveItemServidor('${item.path.replace(/'/g, "\\'")}')">Mover</button>
                    <button class="mini red" onclick="deleteItem('${item.path.replace(/'/g, "\\'")}', 'folder')">Excluir</button>'''
)

s = s.replace(
'''                  <button class="mini" onclick="openFile('${item.path.replace(/'/g, "\\'")}')">Abrir</button>
                  <button class="mini" onclick="downloadFile('${item.path.replace(/'/g, "\\'")}')">Baixar</button>
                  <button class="mini red" onclick="deleteItem('${item.path.replace(/'/g, "\\'")}', 'file')">Excluir</button>''',
'''                  <button class="mini" onclick="openFile('${item.path.replace(/'/g, "\\'")}')">Abrir</button>
                  <button class="mini" onclick="downloadFile('${item.path.replace(/'/g, "\\'")}')">Baixar</button>
                  <button class="mini" onclick="moveItemServidor('${item.path.replace(/'/g, "\\'")}')">Mover</button>
                  <button class="mini red" onclick="deleteItem('${item.path.replace(/'/g, "\\'")}', 'file')">Excluir</button>'''
)

p.write_text(s)
PY

mkdir -p css js

cat > css/cejas-mobile-fix.css <<'EOF'
html {
  -webkit-text-size-adjust: 100%;
  text-size-adjust: 100%;
}

img, svg, video, canvas, iframe {
  max-width: 100%;
}

input, select, textarea, button {
  font-size: 16px;
}

@media (max-width: 899px) {
  body {
    overflow: auto !important;
    min-width: 0 !important;
  }

  .app,
  .layout,
  body:has(> aside) {
    display: block !important;
    min-width: 0 !important;
  }

  aside,
  .sidebar,
  .layout > aside {
    display: none !important;
  }

  main,
  .main,
  .layout > main {
    width: 100% !important;
    min-width: 0 !important;
    min-height: 100vh !important;
    height: auto !important;
    overflow: visible !important;
    padding: 74px 14px 22px !important;
  }

  .topbar,
  .top,
  header {
    display: grid !important;
    grid-template-columns: 1fr !important;
    gap: 12px !important;
    align-items: stretch !important;
  }

  .actions,
  .filters,
  .toolbar,
  .server-actions,
  .item-actions,
  .year-actions,
  .form-grid,
  .grid,
  .stats,
  .kpis,
  .module-grid,
  .content-grid,
  .recent-grid,
  .calendar-layout,
  .dashboard-grid,
  .cards,
  .summary-grid {
    grid-template-columns: 1fr !important;
    flex-wrap: wrap !important;
    width: 100% !important;
  }

  .card,
  .panel,
  .stat-card,
  .module-card,
  .upload-card,
  .upload-panel,
  .calendar-panel,
  .day-panel,
  .list-panel,
  .tree-panel,
  .server-panel {
    width: 100% !important;
    min-width: 0 !important;
    padding: 14px !important;
    border-radius: 16px !important;
  }

  button,
  .btn,
  .mini,
  .file-label {
    min-height: 42px !important;
    justify-content: center !important;
    white-space: normal !important;
  }

  .item-actions {
    display: grid !important;
    grid-template-columns: 1fr 1fr !important;
    gap: 8px !important;
  }

  .tree-row {
    display: grid !important;
    grid-template-columns: 1fr !important;
    gap: 10px !important;
  }

  .item-main,
  .item-name,
  .item-meta {
    min-width: 0 !important;
    overflow-wrap: anywhere !important;
  }

  table {
    display: block !important;
    width: 100% !important;
    overflow-x: auto !important;
    white-space: nowrap !important;
  }

  th,
  td {
    padding: 10px 8px !important;
  }

  .modal,
  .modal-card,
  .pdf-servidor-card {
    width: 96vw !important;
    max-width: 96vw !important;
    height: 88vh !important;
    max-height: 88vh !important;
    border-radius: 18px !important;
  }
}

.cejas-mobile-menu-btn {
  position: fixed;
  top: 14px;
  left: 14px;
  z-index: 1000001;
  border: 1px solid rgba(255,255,255,.16);
  border-radius: 999px;
  padding: 10px 14px;
  background: linear-gradient(135deg, #7B61FF, #FF61D2);
  color: #fff;
  font-weight: 900;
  box-shadow: 0 12px 35px rgba(0,0,0,.45);
  cursor: pointer;
  display: none;
}

.cejas-mobile-drawer {
  position: fixed;
  inset: 0 auto 0 0;
  width: min(330px, 86vw);
  transform: translateX(-105%);
  transition: transform .22s ease;
  z-index: 1000002;
  background: #0b0b10;
  color: #fff;
  border-right: 1px solid rgba(255,255,255,.12);
  padding: 18px;
  overflow: auto;
  box-shadow: 30px 0 80px rgba(0,0,0,.55);
}

.cejas-mobile-drawer.ativo {
  transform: translateX(0);
}

.cejas-mobile-drawer strong {
  display: block;
  margin-bottom: 14px;
  font-size: 15px;
}

.cejas-mobile-drawer nav,
.cejas-mobile-drawer .nav {
  display: grid;
  gap: 9px;
}

.cejas-mobile-drawer a {
  display: block;
  color: #e5e7eb;
  text-decoration: none;
  padding: 12px 13px;
  border-radius: 13px;
  background: rgba(255,255,255,.055);
  border: 1px solid rgba(255,255,255,.07);
  font-weight: 800;
}

.cejas-mobile-drawer a.active {
  background: linear-gradient(135deg, rgba(123,97,255,.35), rgba(255,97,210,.28));
  color: #fff;
}

.cejas-mobile-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000000;
  background: rgba(0,0,0,.58);
  display: none;
}

.cejas-mobile-overlay.ativo {
  display: block;
}

@media (max-width: 899px) {
  .cejas-mobile-menu-btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }
}
EOF

cat > js/cejas-mobile-menu.js <<'EOF'
(function () {
  if (window.__CEJAS_MOBILE_MENU__) return;
  window.__CEJAS_MOBILE_MENU__ = true;

  function normalizar(path) {
    return String(path || "").replace(/\/+$/, "");
  }

  function montarLinks() {
    const aside = document.querySelector("aside, .sidebar");
    const nav = aside && (aside.querySelector("nav") || aside.querySelector(".nav"));
    const links = nav ? [...nav.querySelectorAll("a")] : [];

    if (links.length) {
      return links.map((a) => ({ href: a.getAttribute("href"), texto: a.textContent.trim() })).filter(item => item.href);
    }

    return [
      { href: "/dashboard.html", texto: "▦ Painel Geral" },
      { href: "/agenda.html", texto: "◫ Agenda Dinâmica" },
      { href: "/painel-dia.html", texto: "▣ Painel do Dia" },
      { href: "/chat.html", texto: "💬 Chat Interno" },
      { href: "/orcamentos.html", texto: "◉ Orçamentos" },
      { href: "/financeiro.html", texto: "💰 Financeiro" },
      { href: "/tarefas.html", texto: "☑ Tarefas" },
      { href: "/servidor.html", texto: "▣ Servidor" },
      { href: "/importar-relatorio.html", texto: "▤ Importar Relatório" },
      { href: "/usuarios.html", texto: "◦ Usuários" },
      { href: "/configuracoes.html", texto: "⚙ Configurações" }
    ];
  }

  function iniciar() {
    if (document.querySelector(".cejas-mobile-menu-btn")) return;
    if (location.pathname.includes("login")) return;

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "cejas-mobile-menu-btn";
    btn.textContent = "☰ Menu";

    const overlay = document.createElement("div");
    overlay.className = "cejas-mobile-overlay";

    const drawer = document.createElement("div");
    drawer.className = "cejas-mobile-drawer";

    function render() {
      const atual = normalizar(location.pathname);
      const links = montarLinks();
      drawer.innerHTML = `
        <strong>Sistema CEJAS</strong>
        <nav>
          ${links.map(item => {
            const active = normalizar(item.href) === atual ? "active" : "";
            return `<a class="${active}" href="${item.href}">${item.texto}</a>`;
          }).join("")}
        </nav>
      `;
    }

    function abrir() {
      render();
      overlay.classList.add("ativo");
      drawer.classList.add("ativo");
    }

    function fechar() {
      overlay.classList.remove("ativo");
      drawer.classList.remove("ativo");
    }

    btn.addEventListener("click", abrir);
    overlay.addEventListener("click", fechar);
    drawer.addEventListener("click", (event) => {
      if (event.target.closest("a")) fechar();
    });

    document.body.appendChild(btn);
    document.body.appendChild(overlay);
    document.body.appendChild(drawer);

    render();
    setTimeout(render, 700);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", iniciar);
  } else {
    iniciar();
  }
})();
EOF

python3 <<'PY'
from pathlib import Path

html_files = [
    'dashboard.html', 'agenda.html', 'painel-dia.html', 'chat.html', 'orcamentos.html',
    'financeiro.html', 'tarefas.html', 'servidor.html', 'contratos.html',
    'importar-relatorio.html', 'usuarios.html', 'configuracoes.html'
]

for name in html_files:
    p = Path(name)
    if not p.exists():
        continue
    s = p.read_text()

    if '/css/cejas-mobile-fix.css' not in s:
        s = s.replace('</head>', '  <link rel="stylesheet" href="/css/cejas-mobile-fix.css?v=1">\n</head>', 1)

    if '/js/cejas-mobile-menu.js' not in s:
        s = s.replace('</body>', '<script src="/js/cejas-mobile-menu.js?v=1"></script>\n</body>', 1)

    p.write_text(s)
PY

node --check server.js
node --check js/cejas-mobile-menu.js

python3 <<'PY'
from pathlib import Path
import re

s = Path('servidor.html').read_text()
scripts = re.findall(r"<script>(.*?)</script>", s, re.S)
Path('.cejas-local-backups').mkdir(exist_ok=True)

for i, script in enumerate(scripts, 1):
    test = Path(f'.cejas-local-backups/check-servidor-inline-{i}.js')
    test.write_text(script)
PY

for f in .cejas-local-backups/check-servidor-inline-*.js; do
  node --check "$f"
done

rm -f .cejas-local-backups/check-servidor-inline-*.js

echo ""
echo "✅ Patch aplicado: servidor inteligente v2 + mover item + mobile/tablet + relatório com fallback Supabase."
echo ""
echo "Agora rode: npm run dev"
echo "Depois teste: http://localhost:5500/servidor.html"
