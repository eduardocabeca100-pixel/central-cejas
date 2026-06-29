#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde fica server.js."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/gratuidades-planilha-$STAMP"
mkdir -p "$BACKUP_DIR"
cp server.js gratuidades.html dashboard.html "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

start_marker = "// CEJAS_GRATUIDADES_API_START"
end_marker = "// CEJAS_GRATUIDADES_API_END"

api_block = r'''
// CEJAS_GRATUIDADES_API_START
const cryptoCejasGrat = require("crypto");

const GRATUIDADES_FILE = path.join(__dirname, "data", "gratuidades-manuais.json");
const GRATUIDADES_OCULTAS_FILE = path.join(__dirname, "data", "gratuidades-ocultas.json");

function garantirArquivosGratuidadesCejas() {
  fs.mkdirSync(path.join(__dirname, "data"), { recursive: true });

  if (!fs.existsSync(GRATUIDADES_FILE)) {
    fs.writeFileSync(GRATUIDADES_FILE, "[]", "utf8");
  }

  if (!fs.existsSync(GRATUIDADES_OCULTAS_FILE)) {
    fs.writeFileSync(GRATUIDADES_OCULTAS_FILE, "[]", "utf8");
  }
}

function carregarArrayJsonGratCejas(file) {
  garantirArquivosGratuidadesCejas();

  try {
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
}

function salvarArrayJsonGratCejas(file, lista) {
  garantirArquivosGratuidadesCejas();
  fs.writeFileSync(file, JSON.stringify(lista || [], null, 2), "utf8");
}

function carregarGratuidadesManuaisCejas() {
  return carregarArrayJsonGratCejas(GRATUIDADES_FILE);
}

function salvarGratuidadesManuaisCejas(lista) {
  salvarArrayJsonGratCejas(GRATUIDADES_FILE, lista);
}

function carregarGratuidadesOcultasCejas() {
  return new Set(carregarArrayJsonGratCejas(GRATUIDADES_OCULTAS_FILE));
}

function salvarGratuidadesOcultasCejas(setIds) {
  salvarArrayJsonGratCejas(GRATUIDADES_OCULTAS_FILE, Array.from(setIds || []));
}

function normalizarTextoGratCejas(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function contemGratuidadeCejas(valor) {
  return normalizarTextoGratCejas(valor).includes("GRATUIDADE");
}

function numeroGratCejas(valor) {
  if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

  const texto = String(valor || "")
    .replace(/R\$/gi, "")
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".");

  const numero = Number(texto);
  return Number.isFinite(numero) ? numero : 0;
}

function perdaNegativaGratCejas(valor) {
  const numero = numeroGratCejas(valor);
  if (!numero) return 0;
  return numero > 0 ? -Math.abs(numero) : numero;
}

function calcularPerdaGratCejas(valorTotal, valorPago, valorInformado) {
  const informado = numeroGratCejas(valorInformado);

  if (informado !== 0) {
    return perdaNegativaGratCejas(informado);
  }

  const total = numeroGratCejas(valorTotal);
  const pago = numeroGratCejas(valorPago);
  const diferenca = Math.max(total - pago, 0);

  return diferenca > 0 ? -diferenca : 0;
}

function dataParaISOGratCejas(data) {
  const texto = String(data || "").trim();

  if (!texto) return "";

  if (/^\d{4}-\d{2}-\d{2}/.test(texto)) {
    return texto.slice(0, 10);
  }

  let match = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/);
  if (match) {
    return `${match[3]}-${String(match[2]).padStart(2, "0")}-${String(match[1]).padStart(2, "0")}`;
  }

  match = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2})\b/);
  if (match) {
    return `20${match[3]}-${String(match[2]).padStart(2, "0")}-${String(match[1]).padStart(2, "0")}`;
  }

  return "";
}

function isoParaDataBRGratCejas(iso) {
  if (!iso || !String(iso).includes("-")) return "";
  const [ano, mes, dia] = String(iso).slice(0, 10).split("-");
  if (!ano || !mes || !dia) return "";
  return `${dia}/${mes}/${ano}`;
}

function nomeMesGratCejas(key) {
  const nomes = [
    "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
    "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
  ];

  const [ano, mes] = String(key || "").split("-");
  const idx = Number(mes) - 1;

  if (!ano || idx < 0 || idx > 11) return key || "Sem mês";
  return `${nomes[idx]} de ${ano}`;
}

function hashGratCejas(obj) {
  return cryptoCejasGrat
    .createHash("sha1")
    .update(JSON.stringify(obj || {}))
    .digest("hex")
    .slice(0, 18);
}

function dentroPeriodoGratCejas(iso, de, ate) {
  if (!iso) return false;
  if (de && iso < de) return false;
  if (ate && iso > ate) return false;
  return true;
}

async function carregarRelatorioParaGratCejas() {
  const relatorioPath = typeof RELATORIO_FILE !== "undefined"
    ? RELATORIO_FILE
    : path.join(__dirname, "data", "relatorio-atual.json");

  let report = null;

  if (fs.existsSync(relatorioPath)) {
    try {
      report = JSON.parse(fs.readFileSync(relatorioPath, "utf8"));
    } catch {
      report = null;
    }
  }

  if ((!report || !Array.isArray(report.eventos)) && typeof carregarRelatorioAtualDoSupabaseServidor === "function") {
    try {
      const supabaseReport = await carregarRelatorioAtualDoSupabaseServidor();
      if (supabaseReport) report = supabaseReport;
    } catch {}
  }

  if (!report && typeof emptySuperaReport === "function") {
    return emptySuperaReport();
  }

  return report || { eventos: [] };
}

function textoObjetoGratCejas(obj) {
  try {
    return JSON.stringify(obj || {});
  } catch {
    return "";
  }
}

function descobrirDataGratCejas(obj) {
  const campos = [
    obj?.dataISO,
    obj?.dataEvento,
    obj?.data_evento,
    obj?.data,
    obj?.date,
    obj?.start,
    obj?.inicio,
    obj?.created_at,
    obj?.updated_at
  ];

  for (const campo of campos) {
    const iso = dataParaISOGratCejas(campo);
    if (iso) return iso;
  }

  return "";
}

function descobrirEventoGratCejas(obj) {
  return String(
    obj?.evento ||
    obj?.nomeEvento ||
    obj?.titulo ||
    obj?.title ||
    obj?.nome ||
    obj?.descricao ||
    obj?.empresa ||
    obj?.cliente ||
    "Gratuidade sem evento"
  ).trim();
}

function descobrirOrgaoGratCejas(obj) {
  return String(
    obj?.orgaoAssociado ||
    obj?.orgao_associado ||
    obj?.orgao ||
    obj?.órgão ||
    obj?.associado ||
    obj?.solicitante ||
    obj?.empresa ||
    obj?.cliente ||
    obj?.responsavel ||
    obj?.referencia ||
    "NÃO INFORMADO"
  ).trim();
}

function descobrirReferenciaGratCejas(obj, fonte) {
  return String(
    obj?.referencia ||
    obj?.origem ||
    obj?.sala ||
    obj?.local ||
    obj?.observacao ||
    obj?.descricao ||
    fonte ||
    ""
  ).trim();
}

function descobrirValorTotalGratCejas(obj) {
  return numeroGratCejas(
    obj?.valorTotal ??
    obj?.valor_total ??
    obj?.valorEvento ??
    obj?.valor_evento ??
    obj?.total ??
    obj?.valor ??
    0
  );
}

function descobrirValorPagoGratCejas(obj) {
  return numeroGratCejas(
    obj?.valorPago ??
    obj?.valor_pago ??
    obj?.pago ??
    obj?.recebido ??
    0
  );
}

function criarItemAutoGratCejas(obj, fonte, referenciaExtra = "") {
  const texto = textoObjetoGratCejas(obj);

  if (!contemGratuidadeCejas(texto)) return null;

  const dataISO = descobrirDataGratCejas(obj);
  const valorTotal = descobrirValorTotalGratCejas(obj);
  const valorPago = descobrirValorPagoGratCejas(obj);
  const valorPerda = calcularPerdaGratCejas(
    valorTotal,
    valorPago,
    obj?.valorPerda ??
    obj?.valor_perda ??
    obj?.perda ??
    obj?.valorGratuidade ??
    obj?.valor_gratuidade
  );

  const base = {
    fonte,
    referenciaExtra,
    dataISO,
    evento: descobrirEventoGratCejas(obj),
    orgaoAssociado: descobrirOrgaoGratCejas(obj),
    valorTotal,
    valorPago,
    valorPerda,
    trecho: texto.slice(0, 700)
  };

  return {
    id: `auto-${fonte}-${hashGratCejas(base)}`,
    origem: fonte,
    tipo: "automatica",
    editavel: false,
    data: isoParaDataBRGratCejas(dataISO),
    dataISO,
    evento: base.evento,
    valorTotal,
    valorPago,
    valorPerda,
    orgaoAssociado: base.orgaoAssociado,
    referencia: descobrirReferenciaGratCejas(obj, fonte) || referenciaExtra || fonte,
    observacao: "Detectado automaticamente pela palavra GRATUIDADE.",
    trecho: base.trecho
  };
}

function coletarGratuidadesObjetoCejas(node, fonte, referencia, resultado = [], depth = 0) {
  if (!node || depth > 8) return resultado;

  if (Array.isArray(node)) {
    node.forEach((item, index) => {
      coletarGratuidadesObjetoCejas(item, fonte, `${referencia}[${index}]`, resultado, depth + 1);
    });

    return resultado;
  }

  if (typeof node === "object") {
    const item = criarItemAutoGratCejas(node, fonte, referencia);

    if (item) {
      resultado.push(item);
      return resultado;
    }

    Object.entries(node).forEach(([key, value]) => {
      if (value && typeof value === "object") {
        coletarGratuidadesObjetoCejas(value, fonte, `${referencia}.${key}`, resultado, depth + 1);
      }
    });
  }

  return resultado;
}

async function gratuidadesAutomaticasCejas() {
  const resultado = [];

  const report = await carregarRelatorioParaGratCejas();
  const eventosRelatorio = Array.isArray(report?.eventos) ? report.eventos : [];

  eventosRelatorio.forEach((evento, index) => {
    const item = criarItemAutoGratCejas(evento, "relatorio", `relatorio.eventos[${index}]`);
    if (item) resultado.push(item);
  });

  const dataDir = path.join(__dirname, "data");
  const arquivos = fs.existsSync(dataDir)
    ? fs.readdirSync(dataDir).filter(name => {
        const lower = name.toLowerCase();

        if (!lower.endsWith(".json")) return false;
        if (lower.includes("gratuidades")) return false;
        if (lower.includes("relatorio-atual")) return false;
        if (lower.includes("relatorio-supera")) return false;

        return lower.includes("agenda") ||
          lower.includes("evento") ||
          lower.includes("calendario") ||
          lower.includes("painel") ||
          lower.includes("tarefas");
      })
    : [];

  for (const file of arquivos) {
    try {
      const full = path.join(dataDir, file);
      const json = JSON.parse(fs.readFileSync(full, "utf8"));
      const fonte = file.includes("agenda") ? "agenda" : "sistema";
      coletarGratuidadesObjetoCejas(json, fonte, file, resultado);
    } catch {}
  }

  const vistos = new Set();

  return resultado.filter(item => {
    if (!item || !item.id) return false;
    if (vistos.has(item.id)) return false;
    vistos.add(item.id);
    return true;
  });
}

function normalizarManualGratCejas(item) {
  const dataISO = dataParaISOGratCejas(item?.dataISO || item?.data || item?.dataEvento || "");

  const valorTotal = numeroGratCejas(
    item?.valorTotal ??
    item?.valorEvento ??
    item?.valor_evento ??
    item?.total
  );

  const valorPago = numeroGratCejas(
    item?.valorPago ??
    item?.valor_pago ??
    item?.pago
  );

  const valorPerda = calcularPerdaGratCejas(
    valorTotal,
    valorPago,
    item?.valorPerda ??
    item?.valor_perda ??
    item?.perda ??
    item?.valorGratuidade ??
    item?.valorAbatido
  );

  return {
    id: item?.id || `manual-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    origem: "manual",
    tipo: "manual",
    editavel: true,
    data: isoParaDataBRGratCejas(dataISO),
    dataISO,
    evento: String(item?.evento || "Gratuidade sem evento").trim(),
    valorTotal,
    valorPago,
    valorPerda,
    orgaoAssociado: String(
      item?.orgaoAssociado ||
      item?.orgao_associado ||
      item?.orgao ||
      item?.associado ||
      item?.empresa ||
      item?.referencia ||
      "NÃO INFORMADO"
    ).trim(),
    referencia: String(item?.referencia || item?.origemReferencia || "").trim(),
    observacao: String(item?.observacao || "").trim(),
    criadoEm: item?.criadoEm || new Date().toISOString(),
    atualizadoEm: new Date().toISOString(),
    sourceId: item?.sourceId || ""
  };
}

function resumirGratuidadesCejas(itens) {
  const resumo = {
    quantidade: itens.length,
    valorTotal: 0,
    valorPago: 0,
    valorPerda: 0,
    manual: 0,
    automatica: 0
  };

  for (const item of itens) {
    resumo.valorTotal += numeroGratCejas(item.valorTotal);
    resumo.valorPago += numeroGratCejas(item.valorPago);
    resumo.valorPerda += perdaNegativaGratCejas(item.valorPerda);

    if (item.tipo === "manual") resumo.manual += 1;
    else resumo.automatica += 1;
  }

  return resumo;
}

function graficosGratuidadesCejas(itens) {
  const porMes = {};
  const porOrigem = {};
  const porOrgao = {};

  for (const item of itens) {
    const mesKey = item.dataISO ? item.dataISO.slice(0, 7) : "SEM DATA";
    const origem = item.origem || "manual";
    const orgao = item.orgaoAssociado || "NÃO INFORMADO";
    const perda = perdaNegativaGratCejas(item.valorPerda);

    porMes[mesKey] = porMes[mesKey] || {
      key: mesKey,
      label: nomeMesGratCejas(mesKey),
      quantidade: 0,
      valorPerda: 0
    };

    porOrigem[origem] = porOrigem[origem] || {
      key: origem,
      label: origem === "agenda" ? "Agenda" : origem === "relatorio" ? "Relatório" : origem === "manual" ? "Manual" : "Sistema",
      quantidade: 0,
      valorPerda: 0
    };

    porOrgao[orgao] = porOrgao[orgao] || {
      key: orgao,
      label: orgao,
      quantidade: 0,
      valorPerda: 0
    };

    porMes[mesKey].quantidade += 1;
    porMes[mesKey].valorPerda += perda;

    porOrigem[origem].quantidade += 1;
    porOrigem[origem].valorPerda += perda;

    porOrgao[orgao].quantidade += 1;
    porOrgao[orgao].valorPerda += perda;
  }

  return {
    porMes: Object.values(porMes).sort((a, b) => String(a.key).localeCompare(String(b.key))),
    porOrigem: Object.values(porOrigem).sort((a, b) => Math.abs(b.valorPerda) - Math.abs(a.valorPerda)),
    porOrgao: Object.values(porOrgao).sort((a, b) => Math.abs(b.valorPerda) - Math.abs(a.valorPerda)).slice(0, 12)
  };
}

async function montarGratuidadesCejas(query = {}) {
  const de = String(query.de || query.inicio || "").slice(0, 10);
  const ate = String(query.ate || query.fim || "").slice(0, 10);
  const origemFiltro = String(query.origem || "todas");
  const busca = normalizarTextoGratCejas(query.busca || "");

  const ocultas = carregarGratuidadesOcultasCejas();
  const manuais = carregarGratuidadesManuaisCejas().map(normalizarManualGratCejas);
  const automaticas = (await gratuidadesAutomaticasCejas()).filter(item => !ocultas.has(item.id));

  let itens = [...automaticas, ...manuais];

  if (origemFiltro !== "todas") {
    if (origemFiltro === "automatica") {
      itens = itens.filter(item => item.tipo !== "manual");
    } else {
      itens = itens.filter(item => item.origem === origemFiltro || item.tipo === origemFiltro);
    }
  }

  if (de || ate) {
    itens = itens.filter(item => dentroPeriodoGratCejas(item.dataISO, de, ate));
  }

  if (busca) {
    itens = itens.filter(item => {
      const texto = normalizarTextoGratCejas(`${item.evento} ${item.orgaoAssociado} ${item.referencia} ${item.observacao}`);
      return texto.includes(busca);
    });
  }

  itens.sort((a, b) => String(b.dataISO || "").localeCompare(String(a.dataISO || "")) || String(a.evento).localeCompare(String(b.evento)));

  return {
    itens,
    resumo: resumirGratuidadesCejas(itens),
    graficos: graficosGratuidadesCejas(itens),
    atualizadoEm: new Date().toISOString()
  };
}

async function montarDashboardFinanceiroCejas() {
  const relatorio = await carregarRelatorioParaGratCejas();
  const eventos = Array.isArray(relatorio?.eventos) ? relatorio.eventos : [];
  const meses = {};

  let totalReceitaConfirmada = 0;
  let totalEventosConfirmados = 0;

  for (const evento of eventos) {
    const status = normalizarTextoGratCejas(evento.status || "");

    if (!status.includes("CONFIRMADO") && status !== "CONFIRMADA") continue;

    const iso = dataParaISOGratCejas(evento.data || evento.dataEvento || "");
    if (!iso) continue;

    const key = iso.slice(0, 7);
    const valor = numeroGratCejas(evento.valor || evento.valorPago || 0);

    meses[key] = meses[key] || {
      key,
      mes: nomeMesGratCejas(key),
      receitaConfirmada: 0,
      eventosConfirmados: 0
    };

    meses[key].receitaConfirmada += valor;
    meses[key].eventosConfirmados += 1;

    totalReceitaConfirmada += valor;
    totalEventosConfirmados += 1;
  }

  const gratuidades = await montarGratuidadesCejas({});

  return {
    ok: true,
    receitaMensal: Object.values(meses).sort((a, b) => String(a.key).localeCompare(String(b.key))),
    resumo: {
      totalReceitaConfirmada,
      totalEventosConfirmados,
      mesesComReceita: Object.keys(meses).length,
      gratuidades: gratuidades.resumo
    },
    graficosGratuidades: gratuidades.graficos,
    atualizadoEm: relatorio?.atualizadoEm || new Date().toISOString()
  };
}

app.get("/api/gratuidades", async (req, res) => {
  try {
    const dados = await montarGratuidadesCejas(req.query || {});
    res.json({ ok: true, ...dados });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar gratuidades: " + error.message
    });
  }
});

app.post("/api/gratuidades", express.json({ limit: "2mb" }), (req, res) => {
  try {
    const lista = carregarGratuidadesManuaisCejas();
    const novo = normalizarManualGratCejas(req.body || {});

    if (!novo.dataISO) {
      return res.status(400).json({ ok: false, message: "Informe a data da gratuidade." });
    }

    if (!novo.evento || novo.evento === "Gratuidade sem evento") {
      return res.status(400).json({ ok: false, message: "Informe o evento." });
    }

    lista.push(novo);
    salvarGratuidadesManuaisCejas(lista);

    res.json({
      ok: true,
      item: novo,
      message: "Gratuidade salva."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao salvar gratuidade: " + error.message
    });
  }
});

app.put("/api/gratuidades/:id", express.json({ limit: "2mb" }), (req, res) => {
  try {
    const id = req.params.id;
    const lista = carregarGratuidadesManuaisCejas();
    const index = lista.findIndex(item => item.id === id);

    if (index >= 0) {
      lista[index] = normalizarManualGratCejas({
        ...lista[index],
        ...req.body,
        id
      });

      salvarGratuidadesManuaisCejas(lista);

      return res.json({
        ok: true,
        item: lista[index],
        message: "Gratuidade atualizada."
      });
    }

    if (String(id).startsWith("auto-")) {
      const ocultas = carregarGratuidadesOcultasCejas();
      ocultas.add(id);
      salvarGratuidadesOcultasCejas(ocultas);

      const novo = normalizarManualGratCejas({
        ...req.body,
        sourceId: id,
        referencia: req.body?.referencia || "Editado a partir de gratuidade automática"
      });

      lista.push(novo);
      salvarGratuidadesManuaisCejas(lista);

      return res.json({
        ok: true,
        item: novo,
        message: "Gratuidade automática editada como lançamento manual."
      });
    }

    res.status(404).json({
      ok: false,
      message: "Gratuidade não encontrada."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao editar gratuidade: " + error.message
    });
  }
});

app.delete("/api/gratuidades/:id", (req, res) => {
  try {
    const id = req.params.id;

    if (String(id).startsWith("auto-")) {
      const ocultas = carregarGratuidadesOcultasCejas();
      ocultas.add(id);
      salvarGratuidadesOcultasCejas(ocultas);

      return res.json({
        ok: true,
        message: "Gratuidade automática ocultada."
      });
    }

    const lista = carregarGratuidadesManuaisCejas();
    const novaLista = lista.filter(item => item.id !== id);

    if (novaLista.length === lista.length) {
      return res.status(404).json({
        ok: false,
        message: "Gratuidade manual não encontrada."
      });
    }

    salvarGratuidadesManuaisCejas(novaLista);

    res.json({
      ok: true,
      message: "Gratuidade apagada."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao apagar gratuidade: " + error.message
    });
  }
});

app.get("/api/dashboard-financeiro", async (_req, res) => {
  try {
    const dados = await montarDashboardFinanceiroCejas();
    res.json(dados);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar dashboard financeiro: " + error.message
    });
  }
});
// CEJAS_GRATUIDADES_API_END
'''

if start_marker in s and end_marker in s:
  start = s.index(start_marker)
  end = s.index(end_marker, start) + len(end_marker)
  s = s[:start] + api_block + s[end:]
else:
  insert_before = 'const USERS_FILE = path.join(__dirname, "data", "usuarios.json");'
  if insert_before not in s:
    raise SystemExit("❌ Não encontrei ponto seguro para inserir API de gratuidades.")
  s = s.replace(insert_before, api_block + "\n\n" + insert_before, 1)

p.write_text(s)
PY

cat > gratuidades.html <<'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />

  <title>CEJAS | Gratuidades</title>

  <style>
    :root {
      --bg: #050505;
      --sidebar: #0b0b10;
      --panel: #111114;
      --card: #17171c;
      --border: rgba(255,255,255,.09);
      --text: #fff;
      --muted: #b3b3b3;
      --green: #22c55e;
      --red: #ef4444;
      --yellow: #facc15;
      --gradient: linear-gradient(135deg, #7B61FF, #FF61D2);
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body,
    input,
    button,
    select,
    textarea {
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    body {
      min-height: 100vh;
      background: var(--bg);
      color: var(--text);
      overflow: hidden;
    }

    .app { display: grid; grid-template-columns: 270px 1fr; min-height: 100vh; }

    .sidebar {
      position: relative;
      background: var(--sidebar);
      border-right: 1px solid var(--border);
      padding: 24px 18px;
    }

    .brand { display: flex; align-items: center; gap: 12px; margin-bottom: 26px; }

    .logo {
      width: 45px;
      height: 45px;
      border-radius: 12px;
      border: 1px solid #9b5cff;
      display: grid;
      place-items: center;
      color: #ff61d2;
      font-weight: 900;
      font-size: 28px;
    }

    .brand h1 { font-size: 16px; line-height: 1.05; }
    .brand p { color: var(--muted); font-size: 12px; margin-top: 5px; }

    .user-card {
      background: #171717;
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 16px;
      margin-bottom: 26px;
      display: flex;
      align-items: center;
      gap: 13px;
    }

    .avatar {
      width: 44px;
      height: 44px;
      border-radius: 999px;
      background: var(--gradient);
      display: grid;
      place-items: center;
      font-weight: 900;
    }

    .user-card strong { display: block; font-size: 15px; }
    .user-card span { color: var(--muted); font-size: 13px; }

    .nav { display: flex; flex-direction: column; gap: 10px; }

    .nav a {
      color: #c7c7c7;
      text-decoration: none;
      padding: 13px 14px;
      border-radius: 13px;
      font-weight: 800;
      font-size: 14px;
    }

    .nav a.active {
      color: #fff;
      background: var(--gradient);
      box-shadow: 0 16px 40px rgba(168,85,247,.22);
    }

    .help {
      position: absolute;
      left: 18px;
      bottom: 18px;
      width: 235px;
      background: rgba(123,97,255,.13);
      border: 1px solid rgba(123,97,255,.28);
      border-radius: 16px;
      padding: 16px;
      color: #ddd;
      font-size: 13px;
    }

    .help strong { display: block; color: #fff; margin-bottom: 6px; font-size: 15px; }

    .main {
      height: 100vh;
      overflow-y: auto;
      padding: 32px;
    }

    .topbar {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 18px;
      margin-bottom: 24px;
    }

    .eyebrow {
      color: #aaa;
      letter-spacing: .45em;
      font-size: 12px;
      font-weight: 900;
      text-transform: uppercase;
      margin-bottom: 8px;
    }

    h2 { font-size: 34px; line-height: 1; }

    .subtitle {
      color: var(--muted);
      margin-top: 9px;
      line-height: 1.45;
    }

    .actions {
      display: flex;
      gap: 10px;
      align-items: center;
      flex-wrap: wrap;
      justify-content: flex-end;
    }

    .btn {
      border: 0;
      border-radius: 12px;
      padding: 13px 17px;
      color: #fff;
      font-weight: 900;
      cursor: pointer;
      background: #1f2937;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
    }

    .btn.gradient { background: var(--gradient); }

    .btn.red {
      background: rgba(239,68,68,.18);
      color: #fecaca;
      border: 1px solid rgba(239,68,68,.28);
    }

    .btn.green {
      background: rgba(34,197,94,.18);
      color: #bbf7d0;
      border: 1px solid rgba(34,197,94,.28);
    }

    .kpis {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 16px;
      margin-bottom: 20px;
    }

    .kpi {
      background: linear-gradient(180deg, rgba(255,255,255,.04), rgba(255,255,255,.015));
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 20px;
      min-height: 128px;
    }

    .kpi span {
      display: block;
      color: var(--muted);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: .13em;
      font-weight: 900;
      margin-bottom: 12px;
    }

    .kpi strong {
      display: block;
      font-size: 27px;
      line-height: 1.05;
    }

    .kpi small {
      display: block;
      margin-top: 9px;
      color: var(--green);
      font-weight: 900;
    }

    .kpi.danger strong,
    .loss {
      color: #ff3333 !important;
    }

    .kpi.danger small { color: #fecaca; }

    .panel {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 20px;
      margin-bottom: 20px;
    }

    .panel-head {
      display: flex;
      justify-content: space-between;
      gap: 14px;
      align-items: flex-start;
      margin-bottom: 16px;
    }

    .panel h3 { font-size: 20px; margin-bottom: 5px; }
    .panel p { color: var(--muted); font-size: 13px; line-height: 1.45; }

    .filters {
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 12px;
      align-items: end;
    }

    label {
      color: var(--muted);
      font-size: 12px;
      font-weight: 900;
      text-transform: uppercase;
      letter-spacing: .08em;
      display: block;
      margin-bottom: 7px;
    }

    input,
    select,
    textarea {
      width: 100%;
      border: 1px solid var(--border);
      background: #0d0d0f;
      color: #fff;
      border-radius: 12px;
      padding: 13px;
      outline: none;
      font-weight: 700;
    }

    textarea { min-height: 82px; resize: vertical; }

    .form-grid {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 12px;
    }

    .form-grid .full { grid-column: 1 / -1; }

    .form-actions {
      display: flex;
      gap: 10px;
      justify-content: flex-end;
      margin-top: 14px;
      flex-wrap: wrap;
    }

    .charts {
      display: grid;
      grid-template-columns: 1.2fr .8fr;
      gap: 16px;
    }

    .chart-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 16px;
    }

    .chart-card h4 {
      font-size: 15px;
      margin-bottom: 14px;
    }

    .bars { display: grid; gap: 10px; }

    .bar-line {
      display: grid;
      grid-template-columns: 160px 1fr 125px;
      gap: 10px;
      align-items: center;
      font-size: 12px;
    }

    .bar-label {
      color: #e5e7eb;
      font-weight: 800;
      overflow: hidden;
      white-space: nowrap;
      text-overflow: ellipsis;
    }

    .bar-track {
      height: 12px;
      background: rgba(255,255,255,.07);
      border-radius: 999px;
      overflow: hidden;
    }

    .bar-fill {
      height: 100%;
      border-radius: 999px;
      background: linear-gradient(135deg, #ef4444, #ff61d2);
      min-width: 3px;
    }

    .bar-value {
      color: #ff3333;
      text-align: right;
      font-weight: 900;
    }

    .table-wrap {
      overflow-x: auto;
      border: 1px solid var(--border);
      border-radius: 16px;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      min-width: 1120px;
    }

    th,
    td {
      padding: 13px 12px;
      text-align: left;
      border-bottom: 1px solid rgba(255,255,255,.06);
      font-size: 13px;
      vertical-align: top;
    }

    th {
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: .08em;
      font-size: 11px;
    }

    td strong {
      display: block;
      color: #fff;
      margin-bottom: 4px;
    }

    .tag {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border-radius: 999px;
      padding: 5px 9px;
      font-size: 11px;
      font-weight: 900;
      background: rgba(123,97,255,.16);
      color: #ddd;
    }

    .tag.manual { background: rgba(34,197,94,.13); color: #bbf7d0; }
    .tag.agenda { background: rgba(59,130,246,.13); color: #bfdbfe; }
    .tag.relatorio { background: rgba(250,204,21,.13); color: #fef08a; }
    .tag.sistema { background: rgba(168,85,247,.13); color: #e9d5ff; }

    .empty {
      color: var(--muted);
      padding: 24px;
      text-align: center;
    }

    .row-actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }

    @media (max-width: 1300px) {
      .kpis { grid-template-columns: repeat(2, 1fr); }
      .filters,
      .form-grid,
      .charts { grid-template-columns: 1fr 1fr; }
    }

    @media (max-width: 760px) {
      body { overflow: auto; }
      .app { display: block; }
      .sidebar { display: none; }
      .main { height: auto; min-height: 100vh; padding: 76px 14px 24px; }
      .topbar,
      .panel-head { display: grid; }
      .actions { justify-content: stretch; }
      .actions .btn,
      .form-actions .btn { width: 100%; }
      .kpis,
      .filters,
      .form-grid,
      .charts { grid-template-columns: 1fr; }
      h2 { font-size: 28px; }

      .bar-line {
        grid-template-columns: 1fr;
        gap: 5px;
      }

      .bar-value {
        text-align: left;
      }
    }
  </style>

  <link rel="stylesheet" href="/css/cejas-mobile-fix.css?v=1">
</head>

<body>
  <div class="app">
    <aside class="sidebar">
      <div class="brand">
        <div class="logo">M</div>
        <div>
          <h1>SISTEMA DE GESTÃO CEJAS</h1>
          <p>Painel Administrativo</p>
        </div>
      </div>

      <div class="user-card">
        <div class="avatar">E</div>
        <div>
          <strong>Eduardo</strong>
          <span>Super Admin</span>
        </div>
      </div>

      <nav class="nav">
        <a href="dashboard.html">▦ Painel Geral</a>
        <a href="agenda.html">▣ Agenda Dinâmica</a>
        <a href="/chat.html">💬 Chat Interno</a>
        <a href="orcamentos.html">◉ Orçamentos</a>
        <a href="financeiro.html">💰 Financeiro</a>
        <a class="active" href="gratuidades.html">🏷 Gratuidades</a>
        <a href="importar-relatorio.html">▤ Importar Relatório (PDF)</a>
        <a href="tarefas.html">☑ Tarefas Pendentes</a>
        <a href="servidor.html">▣ Servidor</a>
        <a href="usuarios.html">◌ Acessos / Usuários</a>
        <a href="contratos.html">Contratos</a>
        <a href="configuracoes.html">⚙ Configurações</a>
      </nav>

      <div class="help">
        <strong>Controle de gratuidades</strong>
        Valor de perda sempre negativo, conforme sua planilha de controle.
      </div>
    </aside>

    <main class="main">
      <header class="topbar">
        <div>
          <div class="eyebrow">Controle comercial</div>
          <h2>Gratuidades</h2>
          <p class="subtitle" id="statusText">
            Controle por data, evento, valor total, valor pago, valor de perda e órgão associado/não associado.
          </p>
        </div>

        <div class="actions">
          <a class="btn" href="dashboard.html">Voltar ao painel</a>
          <button class="btn gradient" onclick="carregarGratuidades()">Atualizar</button>
        </div>
      </header>

      <section class="kpis">
        <article class="kpi danger">
          <span>Valor total de perda</span>
          <strong id="kpiPerda">R$ 0,00</strong>
          <small id="kpiPerdaInfo">0 registro(s)</small>
        </article>

        <article class="kpi">
          <span>Valor total dos eventos</span>
          <strong id="kpiValorTotal">R$ 0,00</strong>
          <small>Valor cheio</small>
        </article>

        <article class="kpi">
          <span>Valor pago</span>
          <strong id="kpiValorPago">R$ 0,00</strong>
          <small>Recebido</small>
        </article>

        <article class="kpi">
          <span>Origem automática</span>
          <strong id="kpiAutomatica">0</strong>
          <small>Agenda, relatório ou sistema</small>
        </article>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div>
            <h3>Filtros</h3>
            <p>Filtre por período, origem, evento ou órgão.</p>
          </div>
        </div>

        <div class="filters">
          <div>
            <label>De</label>
            <input type="date" id="filterDe">
          </div>

          <div>
            <label>Até</label>
            <input type="date" id="filterAte">
          </div>

          <div>
            <label>Origem</label>
            <select id="filterOrigem">
              <option value="todas">Todas</option>
              <option value="manual">Manual</option>
              <option value="automatica">Automática</option>
              <option value="agenda">Agenda</option>
              <option value="relatorio">Relatório</option>
              <option value="sistema">Sistema</option>
            </select>
          </div>

          <div>
            <label>Buscar</label>
            <input id="filterBusca" placeholder="Evento, órgão, associado...">
          </div>

          <button class="btn gradient" onclick="carregarGratuidades()">Filtrar</button>
        </div>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div>
            <h3 id="formTitle">Cadastrar gratuidade</h3>
            <p>O valor de perda é calculado automaticamente como negativo: valor pago menos valor total.</p>
          </div>

          <button class="btn" onclick="limparFormulario()">Novo lançamento</button>
        </div>

        <form id="formGratuidade">
          <input type="hidden" id="gratId">

          <div class="form-grid">
            <div>
              <label>Data</label>
              <input type="date" id="gratData" required>
            </div>

            <div>
              <label>Evento</label>
              <input id="gratEvento" placeholder="Ex: FEMUSC" required>
            </div>

            <div>
              <label>Órgão / associado / não associado</label>
              <input id="gratOrgao" placeholder="Ex: SCAR, SENAI, PMJS, NÃO ASSOCIADO">
            </div>

            <div>
              <label>Valor total</label>
              <input id="gratValorTotal" inputmode="decimal" placeholder="Ex: 4200,00">
            </div>

            <div>
              <label>Valor pago</label>
              <input id="gratValorPago" inputmode="decimal" placeholder="Ex: 0,00">
            </div>

            <div>
              <label>Valor de perda</label>
              <input id="gratValorPerda" inputmode="decimal" placeholder="Ex: -4200,00">
            </div>

            <div class="full">
              <label>Referência</label>
              <input id="gratReferencia" placeholder="Ex: solicitação, diretoria, agenda, entidade...">
            </div>

            <div class="full">
              <label>Observação</label>
              <textarea id="gratObs" placeholder="Motivo da gratuidade, autorização, detalhes..."></textarea>
            </div>
          </div>

          <div class="form-actions">
            <button class="btn" type="button" onclick="calcularPerdaAutomatica()">Calcular perda negativa</button>
            <button class="btn gradient" type="submit">Salvar</button>
          </div>
        </form>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div>
            <h3>Gráficos de déficit por gratuidade</h3>
            <p>Os gráficos mostram os valores de perda sempre negativos.</p>
          </div>
        </div>

        <div class="charts">
          <article class="chart-card">
            <h4>Valor de perda por mês</h4>
            <div class="bars" id="chartMes"></div>
          </article>

          <article class="chart-card">
            <h4>Origem da gratuidade</h4>
            <div class="bars" id="chartOrigem"></div>
          </article>

          <article class="chart-card" style="grid-column:1 / -1;">
            <h4>Órgão / associado / não associado</h4>
            <div class="bars" id="chartOrgao"></div>
          </article>
        </div>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div>
            <h3>Lista de gratuidades</h3>
            <p>Formato igual ao controle da planilha.</p>
          </div>
        </div>

        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Data</th>
                <th>Evento</th>
                <th>Valor total</th>
                <th>Valor pago</th>
                <th>Valor de perda</th>
                <th>Órgão / associado / não associado</th>
                <th>Origem</th>
                <th>Ações</th>
              </tr>
            </thead>

            <tbody id="gratuidadesBody">
              <tr>
                <td colspan="8" class="empty">Carregando...</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </main>
  </div>

  <script>
    let gratuidadesCache = [];

    const money = (value) => Number(value || 0).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });

    function moneyLoss(value) {
      const n = Number(value || 0);
      const abs = Math.abs(n).toLocaleString("pt-BR", {
        style: "currency",
        currency: "BRL"
      });

      return n < 0 ? `-${abs}` : abs;
    }

    const numberBR = (value) => {
      if (typeof value === "number") return value;

      const text = String(value || "")
        .replace(/R\$/gi, "")
        .replace(/\s/g, "")
        .replace(/\./g, "")
        .replace(",", ".");

      const n = Number(text);
      return Number.isFinite(n) ? n : 0;
    };

    function perdaNegativa(value) {
      const n = numberBR(value);
      if (!n) return 0;
      return n > 0 ? -Math.abs(n) : n;
    }

    function escapeHTML(value) {
      return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    function formatInputMoney(value) {
      return Number(value || 0).toLocaleString("pt-BR", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      });
    }

    function calcularPerdaAutomatica() {
      const valorTotal = numberBR(document.getElementById("gratValorTotal").value);
      const valorPago = numberBR(document.getElementById("gratValorPago").value);
      const perda = Math.min(valorPago - valorTotal, 0);

      document.getElementById("gratValorPerda").value = formatInputMoney(perda);
    }

    function limparFormulario() {
      document.getElementById("formGratuidade").reset();
      document.getElementById("gratId").value = "";
      document.getElementById("formTitle").textContent = "Cadastrar gratuidade";
    }

    function payloadFormulario() {
      const valorTotal = numberBR(document.getElementById("gratValorTotal").value);
      const valorPago = numberBR(document.getElementById("gratValorPago").value);
      let valorPerda = numberBR(document.getElementById("gratValorPerda").value);

      if (!valorPerda) {
        valorPerda = Math.min(valorPago - valorTotal, 0);
      }

      valorPerda = perdaNegativa(valorPerda);

      return {
        data: document.getElementById("gratData").value,
        evento: document.getElementById("gratEvento").value,
        orgaoAssociado: document.getElementById("gratOrgao").value,
        valorTotal,
        valorPago,
        valorPerda,
        referencia: document.getElementById("gratReferencia").value,
        observacao: document.getElementById("gratObs").value
      };
    }

    function preencherFormulario(item) {
      document.getElementById("gratId").value = item.id || "";
      document.getElementById("gratData").value = item.dataISO || "";
      document.getElementById("gratEvento").value = item.evento || "";
      document.getElementById("gratOrgao").value = item.orgaoAssociado || "";
      document.getElementById("gratValorTotal").value = formatInputMoney(item.valorTotal || 0);
      document.getElementById("gratValorPago").value = formatInputMoney(item.valorPago || 0);
      document.getElementById("gratValorPerda").value = formatInputMoney(item.valorPerda || 0);
      document.getElementById("gratReferencia").value = item.referencia || "";
      document.getElementById("gratObs").value = item.observacao || "";

      document.getElementById("formTitle").textContent = item.tipo === "manual"
        ? "Editar gratuidade"
        : "Editar gratuidade automática como manual";

      window.scrollTo({ top: 0, behavior: "smooth" });
    }

    function renderResumo(resumo) {
      document.getElementById("kpiPerda").textContent = moneyLoss(resumo.valorPerda || 0);
      document.getElementById("kpiValorTotal").textContent = money(resumo.valorTotal || 0);
      document.getElementById("kpiValorPago").textContent = money(resumo.valorPago || 0);
      document.getElementById("kpiAutomatica").textContent = resumo.automatica || 0;
      document.getElementById("kpiPerdaInfo").textContent = `${resumo.quantidade || 0} registro(s)`;
    }

    function renderBars(containerId, data) {
      const container = document.getElementById(containerId);
      const maior = Math.max(...(data || []).map(item => Math.abs(Number(item.valorPerda || 0))), 1);

      container.innerHTML = (data || []).map(item => {
        const value = Number(item.valorPerda || 0);
        const width = Math.max((Math.abs(value) / maior) * 100, value ? 4 : 0);

        return `
          <div class="bar-line">
            <div class="bar-label" title="${escapeHTML(item.label)}">${escapeHTML(item.label)}</div>
            <div class="bar-track">
              <div class="bar-fill" style="width:${width}%"></div>
            </div>
            <div class="bar-value">${moneyLoss(value)}</div>
          </div>
        `;
      }).join("") || `<div class="empty">Sem dados para este gráfico.</div>`;
    }

    function renderGraficos(graficos) {
      renderBars("chartMes", graficos?.porMes || []);
      renderBars("chartOrigem", graficos?.porOrigem || []);
      renderBars("chartOrgao", graficos?.porOrgao || []);
    }

    function classeOrigem(item) {
      if (item.tipo === "manual") return "manual";
      if (item.origem === "agenda") return "agenda";
      if (item.origem === "relatorio") return "relatorio";
      return "sistema";
    }

    function labelOrigem(item) {
      if (item.tipo === "manual") return "Manual";
      if (item.origem === "agenda") return "Agenda";
      if (item.origem === "relatorio") return "Relatório";
      return "Sistema";
    }

    function renderTabela(itens) {
      gratuidadesCache = itens || [];
      const body = document.getElementById("gratuidadesBody");

      body.innerHTML = gratuidadesCache.map((item) => `
        <tr>
          <td>${escapeHTML(item.data || "")}</td>
          <td>
            <strong>${escapeHTML(item.evento || "Gratuidade")}</strong>
            <span>${escapeHTML(item.referencia || "")}</span>
          </td>
          <td>${money(item.valorTotal)}</td>
          <td>${money(item.valorPago)}</td>
          <td><strong class="loss">${moneyLoss(item.valorPerda)}</strong></td>
          <td><strong>${escapeHTML(item.orgaoAssociado || "NÃO INFORMADO")}</strong></td>
          <td><span class="tag ${classeOrigem(item)}">${labelOrigem(item)}</span></td>
          <td>
            <div class="row-actions">
              <button class="btn green" onclick="editarGratuidade('${item.id}')">Editar</button>
              <button class="btn red" onclick="apagarGratuidade('${item.id}')">${item.tipo === "manual" ? "Apagar" : "Ocultar"}</button>
            </div>
          </td>
        </tr>
      `).join("") || `<tr><td colspan="8" class="empty">Nenhuma gratuidade encontrada.</td></tr>`;
    }

    function editarGratuidade(id) {
      const item = gratuidadesCache.find(item => item.id === id);

      if (!item) {
        alert("Registro não encontrado.");
        return;
      }

      preencherFormulario(item);
    }

    async function apagarGratuidade(id) {
      const item = gratuidadesCache.find(item => item.id === id);
      const texto = item?.tipo === "manual"
        ? "Apagar esta gratuidade?"
        : "Ocultar esta gratuidade automática da visão?";

      if (!confirm(texto)) return;

      const response = await fetch(`/api/gratuidades/${encodeURIComponent(id)}`, {
        method: "DELETE"
      });

      const data = await response.json();

      if (!data.ok) {
        alert(data.message || "Erro ao apagar.");
        return;
      }

      await carregarGratuidades();
    }

    async function carregarGratuidades() {
      const params = new URLSearchParams();

      const de = document.getElementById("filterDe").value;
      const ate = document.getElementById("filterAte").value;
      const origem = document.getElementById("filterOrigem").value;
      const busca = document.getElementById("filterBusca").value;

      if (de) params.set("de", de);
      if (ate) params.set("ate", ate);
      if (origem) params.set("origem", origem);
      if (busca) params.set("busca", busca);

      const response = await fetch(`/api/gratuidades?${params.toString()}`, {
        cache: "no-store"
      });

      const data = await response.json();

      if (!data.ok) {
        alert(data.message || "Erro ao carregar gratuidades.");
        return;
      }

      renderResumo(data.resumo || {});
      renderGraficos(data.graficos || {});
      renderTabela(data.itens || []);

      const atualizado = data.atualizadoEm
        ? new Date(data.atualizadoEm).toLocaleString("pt-BR")
        : "agora";

      document.getElementById("statusText").textContent =
        `Atualizado em ${atualizado}. Valor de perda sempre negativo. Descontos comerciais ficam no financeiro.`;
    }

    document.getElementById("formGratuidade").addEventListener("submit", async (event) => {
      event.preventDefault();

      const id = document.getElementById("gratId").value;
      const payload = payloadFormulario();

      const response = await fetch(id ? `/api/gratuidades/${encodeURIComponent(id)}` : "/api/gratuidades", {
        method: id ? "PUT" : "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      const data = await response.json();

      if (!data.ok) {
        alert(data.message || "Erro ao salvar gratuidade.");
        return;
      }

      limparFormulario();
      await carregarGratuidades();
      alert(data.message || "Gratuidade salva.");
    });

    carregarGratuidades();
  </script>

  <script src="/js/cejas-mobile-menu.js?v=1"></script>
</body>
</html>
EOF

python3 <<'PY'
from pathlib import Path

p = Path("dashboard.html")

if p.exists():
  s = p.read_text()

  s = s.replace("Gratuidades e abatimentos", "Gratuidades")
  s = s.replace("Total em gratuidades", "Déficit em gratuidades")
  s = s.replace("cejasTotalGratuidades", "cejasTotalGratuidades")

  s = s.replace(
    'document.getElementById("cejasTotalGratuidades").textContent = money(grat.valorAbatido || 0);',
    'document.getElementById("cejasTotalGratuidades").textContent = money(grat.valorPerda || grat.valorGratuidade || grat.valorAbatido || 0);'
  )

  s = s.replace(
    'document.getElementById("cejasTotalGratuidades").textContent = money(grat.valorGratuidade || 0);',
    'document.getElementById("cejasTotalGratuidades").textContent = money(grat.valorPerda || grat.valorGratuidade || 0);'
  )

  p.write_text(s)
PY

node --check server.js

node <<'NODE'
const fs = require("fs");

for (const html of ["gratuidades.html", "dashboard.html"]) {
  if (!fs.existsSync(html)) continue;

  const content = fs.readFileSync(html, "utf8");
  const scripts = [...content.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map(match => match[1]);

  fs.mkdirSync(".cejas-local-backups/check-gratuidades-planilha", { recursive: true });

  scripts.forEach((code, index) => {
    fs.writeFileSync(`.cejas-local-backups/check-gratuidades-planilha/${html}-${index + 1}.js`, code);
  });
}
NODE

for f in .cejas-local-backups/check-gratuidades-planilha/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-gratuidades-planilha

echo ""
echo "✅ Aba Gratuidades ajustada no modelo da planilha."
echo ""
echo "Campos agora:"
echo "- Data"
echo "- Evento"
echo "- Valor total"
echo "- Valor pago"
echo "- Valor de perda sempre negativo"
echo "- Órgão / associado / não associado"
echo ""
echo "Rode:"
echo "npm run dev"
echo ""
echo "Abra:"
echo "http://localhost:5500/gratuidades.html"
