#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "dashboard.html" ]; then
  echo "❌ Rode este comando dentro da pasta raiz do projeto, onde ficam server.js e dashboard.html."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/gratuidades-dashboard-$STAMP"
mkdir -p "$BACKUP_DIR"
cp server.js dashboard.html "$BACKUP_DIR/" 2>/dev/null || true
cp *.html "$BACKUP_DIR/" 2>/dev/null || true
[ -d css ] && cp -R css "$BACKUP_DIR/css" 2>/dev/null || true
[ -d js ] && cp -R js "$BACKUP_DIR/js" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

server = Path('server.js')
s = server.read_text()

marker = '// CEJAS_GRATUIDADES_API_START'
insert_before = 'const USERS_FILE = path.join(__dirname, "data", "usuarios.json");'

api_block = r'''
// CEJAS_GRATUIDADES_API_START
const GRATUIDADES_FILE = path.join(__dirname, "data", "gratuidades-manuais.json");

function ensureGratuidadesFile() {
  fs.mkdirSync(path.join(__dirname, "data"), { recursive: true });

  if (!fs.existsSync(GRATUIDADES_FILE)) {
    fs.writeFileSync(GRATUIDADES_FILE, "[]", "utf8");
  }
}

function carregarGratuidadesManuais() {
  ensureGratuidadesFile();

  try {
    const lista = JSON.parse(fs.readFileSync(GRATUIDADES_FILE, "utf8"));
    return Array.isArray(lista) ? lista : [];
  } catch {
    return [];
  }
}

function salvarGratuidadesManuais(lista) {
  ensureGratuidadesFile();
  fs.writeFileSync(GRATUIDADES_FILE, JSON.stringify(lista, null, 2), "utf8");
}

function numeroFinanceiroCejas(valor) {
  if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

  const texto = String(valor || "")
    .replace(/R\$/gi, "")
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".");

  const numero = Number(texto);
  return Number.isFinite(numero) ? numero : 0;
}

function statusConfirmadoCejas(status) {
  const texto = String(status || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();

  return texto.includes("confirmado") || texto === "confirmada";
}

function dataEventoParaISOCejas(data) {
  const texto = String(data || "").trim();

  if (!texto) return "";

  if (/^\d{4}-\d{2}-\d{2}/.test(texto)) {
    return texto.slice(0, 10);
  }

  let match = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/);
  if (match) {
    const dia = String(match[1]).padStart(2, "0");
    const mes = String(match[2]).padStart(2, "0");
    const ano = match[3];
    return `${ano}-${mes}-${dia}`;
  }

  match = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2})\b/);
  if (match) {
    const dia = String(match[1]).padStart(2, "0");
    const mes = String(match[2]).padStart(2, "0");
    const ano = `20${match[3]}`;
    return `${ano}-${mes}-${dia}`;
  }

  return "";
}

function isoParaDataBRCejas(iso) {
  if (!iso || !String(iso).includes("-")) return "";
  const [ano, mes, dia] = String(iso).slice(0, 10).split("-");
  if (!ano || !mes || !dia) return "";
  return `${dia}/${mes}/${ano}`;
}

function nomeMesCejas(key) {
  const nomes = [
    "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
    "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
  ];

  const [ano, mes] = String(key || "").split("-");
  const idx = Number(mes) - 1;

  if (!ano || idx < 0 || idx > 11) return key || "Sem mês";
  return `${nomes[idx]} de ${ano}`;
}

function dentroPeriodoCejas(iso, de, ate) {
  if (!iso) return false;
  if (de && iso < de) return false;
  if (ate && iso > ate) return false;
  return true;
}

async function carregarRelatorioParaAnaliseCejas() {
  let report = null;

  if (fs.existsSync(RELATORIO_FILE)) {
    try {
      report = JSON.parse(fs.readFileSync(RELATORIO_FILE, "utf8"));
    } catch {
      report = null;
    }
  }

  if ((!report || relatorioCejasVazioServidor(report)) && typeof carregarRelatorioAtualDoSupabaseServidor === "function") {
    const supabaseReport = await carregarRelatorioAtualDoSupabaseServidor();
    if (supabaseReport && !relatorioCejasVazioServidor(supabaseReport)) {
      report = supabaseReport;
    }
  }

  return report || emptySuperaReport();
}

function gratuidadesDoRelatorioCejas(report) {
  const eventos = Array.isArray(report?.eventos) ? report.eventos : [];

  return eventos
    .map((evento, index) => {
      const desconto = numeroFinanceiroCejas(evento.desconto || evento.valorAbatido || 0);
      const pago = numeroFinanceiroCejas(evento.valorPago || evento.valor || 0);
      const valorEvento = numeroFinanceiroCejas(evento.valorEvento || (pago + desconto));
      const iso = dataEventoParaISOCejas(evento.data || evento.dataEvento || "");

      return {
        id: `relatorio-${index}-${iso || "sem-data"}`,
        origem: "relatorio",
        data: isoParaDataBRCejas(iso),
        dataISO: iso,
        evento: evento.evento || evento.nome || evento.empresa || "Evento do relatório",
        empresa: evento.empresa || "",
        status: evento.status || "",
        valorEvento,
        valorPago: pago,
        valorAbatido: desconto,
        observacao: "Detectado automaticamente pelo desconto do relatório importado."
      };
    })
    .filter(item => item.valorAbatido > 0);
}

function normalizarGratuidadeManualCejas(item) {
  const iso = dataEventoParaISOCejas(item.dataISO || item.data || item.dataEvento || "");
  const valorEvento = numeroFinanceiroCejas(item.valorEvento);
  const valorPago = numeroFinanceiroCejas(item.valorPago);
  const valorAbatido = numeroFinanceiroCejas(item.valorAbatido || Math.max(valorEvento - valorPago, 0));

  return {
    id: item.id || `grat-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    origem: "manual",
    data: isoParaDataBRCejas(iso),
    dataISO: iso,
    evento: String(item.evento || "Evento sem nome").trim(),
    empresa: String(item.empresa || "").trim(),
    status: String(item.status || "manual").trim(),
    valorEvento,
    valorPago,
    valorAbatido,
    observacao: String(item.observacao || "").trim(),
    criadoEm: item.criadoEm || new Date().toISOString(),
    atualizadoEm: new Date().toISOString()
  };
}

async function montarGratuidadesCejas(query = {}) {
  const de = String(query.de || query.inicio || "").slice(0, 10);
  const ate = String(query.ate || query.fim || "").slice(0, 10);
  const origem = String(query.origem || "todas");

  const report = await carregarRelatorioParaAnaliseCejas();
  const manuais = carregarGratuidadesManuais().map(normalizarGratuidadeManualCejas);
  const relatorio = gratuidadesDoRelatorioCejas(report);

  let itens = [...relatorio, ...manuais];

  if (origem === "manual") itens = manuais;
  if (origem === "relatorio") itens = relatorio;

  if (de || ate) {
    itens = itens.filter(item => dentroPeriodoCejas(item.dataISO, de, ate));
  }

  itens.sort((a, b) => String(b.dataISO || "").localeCompare(String(a.dataISO || "")) || String(a.evento).localeCompare(String(b.evento)));

  const porMesMap = {};
  let totalValorEvento = 0;
  let totalPago = 0;
  let totalAbatido = 0;

  for (const item of itens) {
    totalValorEvento += numeroFinanceiroCejas(item.valorEvento);
    totalPago += numeroFinanceiroCejas(item.valorPago);
    totalAbatido += numeroFinanceiroCejas(item.valorAbatido);

    const key = item.dataISO ? item.dataISO.slice(0, 7) : "SEM DATA";
    porMesMap[key] = porMesMap[key] || {
      key,
      mes: nomeMesCejas(key),
      quantidade: 0,
      valorEvento: 0,
      valorPago: 0,
      valorAbatido: 0
    };

    porMesMap[key].quantidade += 1;
    porMesMap[key].valorEvento += numeroFinanceiroCejas(item.valorEvento);
    porMesMap[key].valorPago += numeroFinanceiroCejas(item.valorPago);
    porMesMap[key].valorAbatido += numeroFinanceiroCejas(item.valorAbatido);
  }

  const porMes = Object.values(porMesMap).sort((a, b) => String(a.key).localeCompare(String(b.key)));

  return {
    itens,
    porMes,
    resumo: {
      quantidade: itens.length,
      valorEvento: totalValorEvento,
      valorPago: totalPago,
      valorAbatido: totalAbatido,
      percentualPerda: totalValorEvento > 0 ? (totalAbatido / totalValorEvento) * 100 : 0
    },
    atualizadoEm: new Date().toISOString()
  };
}

async function montarDashboardFinanceiroCejas() {
  const report = await carregarRelatorioParaAnaliseCejas();
  const eventos = Array.isArray(report.eventos) ? report.eventos : [];
  const meses = {};

  let totalReceitaConfirmada = 0;
  let totalEventosConfirmados = 0;

  for (const evento of eventos) {
    if (!statusConfirmadoCejas(evento.status)) continue;

    const iso = dataEventoParaISOCejas(evento.data || "");
    if (!iso) continue;

    const key = iso.slice(0, 7);
    const valor = numeroFinanceiroCejas(evento.valor || evento.valorPago || 0);

    meses[key] = meses[key] || {
      key,
      mes: nomeMesCejas(key),
      receitaConfirmada: 0,
      eventosConfirmados: 0
    };

    meses[key].receitaConfirmada += valor;
    meses[key].eventosConfirmados += 1;
    totalReceitaConfirmada += valor;
    totalEventosConfirmados += 1;
  }

  const receitaMensal = Object.values(meses).sort((a, b) => String(a.key).localeCompare(String(b.key)));
  const gratuidades = await montarGratuidadesCejas({});

  return {
    ok: true,
    receitaMensal,
    resumo: {
      totalReceitaConfirmada,
      totalEventosConfirmados,
      mesesComReceita: receitaMensal.length,
      gratuidades: gratuidades.resumo
    },
    atualizadoEm: report.atualizadoEm || new Date().toISOString()
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
    const atual = carregarGratuidadesManuais();
    const novo = normalizarGratuidadeManualCejas(req.body || {});

    if (!novo.dataISO) {
      return res.status(400).json({ ok: false, message: "Informe a data da gratuidade." });
    }

    if (!novo.evento || novo.evento === "Evento sem nome") {
      return res.status(400).json({ ok: false, message: "Informe o nome do evento." });
    }

    if (novo.valorAbatido <= 0) {
      return res.status(400).json({ ok: false, message: "Informe o valor abatido/gratuidade." });
    }

    atual.push(novo);
    salvarGratuidadesManuais(atual);

    res.json({ ok: true, item: novo, message: "Gratuidade registrada com sucesso." });
  } catch (error) {
    res.status(500).json({ ok: false, message: "Erro ao salvar gratuidade: " + error.message });
  }
});

app.delete("/api/gratuidades/:id", (req, res) => {
  try {
    const id = req.params.id;

    if (String(id || "").startsWith("relatorio-")) {
      return res.status(400).json({
        ok: false,
        message: "Esta gratuidade vem do relatório. Para remover, importe um relatório corrigido."
      });
    }

    const atual = carregarGratuidadesManuais();
    const novaLista = atual.filter(item => item.id !== id);

    if (novaLista.length === atual.length) {
      return res.status(404).json({ ok: false, message: "Gratuidade manual não encontrada." });
    }

    salvarGratuidadesManuais(novaLista);
    res.json({ ok: true, message: "Gratuidade excluída." });
  } catch (error) {
    res.status(500).json({ ok: false, message: "Erro ao excluir gratuidade: " + error.message });
  }
});

app.get("/api/dashboard-financeiro", async (_req, res) => {
  try {
    const dados = await montarDashboardFinanceiroCejas();
    res.json(dados);
  } catch (error) {
    res.status(500).json({ ok: false, message: "Erro ao carregar dashboard financeiro: " + error.message });
  }
});
// CEJAS_GRATUIDADES_API_END

'''

if marker not in s:
    if insert_before not in s:
        raise SystemExit('❌ Não encontrei o ponto para inserir a API de gratuidades no server.js.')
    s = s.replace(insert_before, api_block + insert_before, 1)

if '{ id: "gratuidades", nome: "Gratuidades" }' not in s:
    s = s.replace('{ id: "financeiro", nome: "Financeiro" },', '{ id: "financeiro", nome: "Financeiro" },\n  { id: "gratuidades", nome: "Gratuidades" },', 1)

if '"/gratuidades.html": "gratuidades"' not in s:
    s = s.replace('"/financeiro.html": "financeiro",', '"/financeiro.html": "financeiro",\n  "/gratuidades.html": "gratuidades",', 1)

server.write_text(s)
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
      --purple: #a855f7;
      --pink: #ff61d2;
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
    .sidebar { position: relative; background: var(--sidebar); border-right: 1px solid var(--border); padding: 24px 18px; }
    .brand { display: flex; align-items: center; gap: 12px; margin-bottom: 26px; }
    .logo { width: 45px; height: 45px; border-radius: 12px; border: 1px solid #9b5cff; display: grid; place-items: center; color: #ff61d2; font-weight: 900; font-size: 28px; }
    .brand h1 { font-size: 16px; line-height: 1.05; }
    .brand p { color: var(--muted); font-size: 12px; margin-top: 5px; }

    .user-card { background: #171717; border: 1px solid var(--border); border-radius: 16px; padding: 16px; margin-bottom: 26px; display: flex; align-items: center; gap: 13px; }
    .avatar { width: 44px; height: 44px; border-radius: 999px; background: var(--gradient); display: grid; place-items: center; font-weight: 900; }
    .user-card strong { display: block; font-size: 15px; }
    .user-card span { color: var(--muted); font-size: 13px; }

    .nav { display: flex; flex-direction: column; gap: 10px; }
    .nav a { color: #c7c7c7; text-decoration: none; padding: 13px 14px; border-radius: 13px; font-weight: 800; font-size: 14px; }
    .nav a.active { color: #fff; background: var(--gradient); box-shadow: 0 16px 40px rgba(168,85,247,.22); }

    .help { position: absolute; left: 18px; bottom: 18px; width: 235px; background: rgba(123,97,255,.13); border: 1px solid rgba(123,97,255,.28); border-radius: 16px; padding: 16px; color: #ddd; font-size: 13px; }
    .help strong { display: block; color: #fff; margin-bottom: 6px; font-size: 15px; }

    .main { height: 100vh; overflow-y: auto; padding: 32px; }

    .topbar { display: flex; justify-content: space-between; align-items: flex-start; gap: 18px; margin-bottom: 24px; }
    .eyebrow { color: #aaa; letter-spacing: .45em; font-size: 12px; font-weight: 900; text-transform: uppercase; margin-bottom: 8px; }
    h2 { font-size: 34px; line-height: 1; }
    .subtitle { color: var(--muted); margin-top: 9px; }

    .actions { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; justify-content: flex-end; }

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
    .btn.red { background: rgba(239,68,68,.18); color: #fecaca; border: 1px solid rgba(239,68,68,.28); }

    .kpis { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 20px; }

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

    .kpi strong { display: block; font-size: 28px; line-height: 1.05; }
    .kpi small { display: block; margin-top: 9px; color: var(--green); font-weight: 900; }
    .kpi.danger small { color: var(--red); }
    .kpi.warning small { color: var(--yellow); }

    .panel {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 20px;
      margin-bottom: 20px;
    }

    .panel h3 { font-size: 20px; margin-bottom: 16px; }

    .filters {
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 12px;
      align-items: end;
      margin-bottom: 18px;
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

    .monthly-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 12px;
    }

    .month-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 16px;
    }

    .month-card strong {
      display: block;
      font-size: 20px;
      margin-top: 8px;
      color: #fff;
    }

    .month-card span,
    .month-card small {
      color: var(--muted);
      font-size: 12px;
      font-weight: 800;
    }

    .table-wrap {
      overflow-x: auto;
      border: 1px solid var(--border);
      border-radius: 16px;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      min-width: 980px;
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
    .tag.relatorio { background: rgba(250,204,21,.13); color: #fef08a; }

    .empty {
      color: var(--muted);
      padding: 24px;
      text-align: center;
    }

    @media (max-width: 1300px) {
      .kpis,
      .monthly-grid {
        grid-template-columns: repeat(2, 1fr);
      }

      .filters,
      .form-grid {
        grid-template-columns: 1fr 1fr;
      }
    }

    @media (max-width: 760px) {
      body { overflow: auto; }
      .app { display: block; }
      .sidebar { display: none; }
      .main { height: auto; min-height: 100vh; padding: 76px 14px 24px; }
      .topbar { display: grid; }
      .actions { justify-content: stretch; }
      .actions .btn,
      .form-actions .btn { width: 100%; }
      .kpis,
      .monthly-grid,
      .filters,
      .form-grid { grid-template-columns: 1fr; }
      h2 { font-size: 28px; }
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
        <strong>Controle de perdas</strong>
        Acompanhe abatimentos, gratuidades e valores que deixaram de entrar no caixa.
      </div>
    </aside>

    <main class="main">
      <header class="topbar">
        <div>
          <div class="eyebrow">Controle financeiro</div>
          <h2>Gratuidades e abatimentos</h2>
          <p class="subtitle" id="statusText">Carregando dados do relatório e lançamentos manuais...</p>
        </div>

        <div class="actions">
          <a class="btn" href="dashboard.html">Voltar ao painel</a>
          <button class="btn gradient" onclick="carregarGratuidades()">Atualizar</button>
        </div>
      </header>

      <section class="kpis">
        <article class="kpi danger">
          <span>Total abatido</span>
          <strong id="kpiAbatido">R$ 0,00</strong>
          <small id="kpiAbatidoInfo">0 gratuidades</small>
        </article>

        <article class="kpi">
          <span>Valor cheio dos eventos</span>
          <strong id="kpiValorEvento">R$ 0,00</strong>
          <small>Antes da gratuidade</small>
        </article>

        <article class="kpi">
          <span>Valor pago</span>
          <strong id="kpiValorPago">R$ 0,00</strong>
          <small>Depois da gratuidade</small>
        </article>

        <article class="kpi warning">
          <span>Percentual perdido</span>
          <strong id="kpiPercentual">0%</strong>
          <small>Abatido sobre valor cheio</small>
        </article>
      </section>

      <section class="panel">
        <h3>Filtros</h3>

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
              <option value="relatorio">Relatório importado</option>
              <option value="manual">Manual</option>
            </select>
          </div>

          <button class="btn gradient" onclick="carregarGratuidades()">Filtrar</button>
          <button class="btn" onclick="limparFiltros()">Limpar</button>
        </div>
      </section>

      <section class="panel">
        <h3>Lançar gratuidade manual</h3>

        <form id="formGratuidade">
          <div class="form-grid">
            <div>
              <label>Data</label>
              <input type="date" id="gratData" required>
            </div>

            <div>
              <label>Evento</label>
              <input id="gratEvento" placeholder="Ex: Café OAB" required>
            </div>

            <div>
              <label>Empresa/cliente</label>
              <input id="gratEmpresa" placeholder="Opcional">
            </div>

            <div>
              <label>Valor do evento</label>
              <input id="gratValorEvento" inputmode="decimal" placeholder="Ex: 2500,00" required>
            </div>

            <div>
              <label>Valor pago</label>
              <input id="gratValorPago" inputmode="decimal" placeholder="Ex: 1500,00" required>
            </div>

            <div>
              <label>Valor abatido</label>
              <input id="gratValorAbatido" inputmode="decimal" placeholder="Ex: 1000,00" required>
            </div>

            <div class="full">
              <label>Observação</label>
              <textarea id="gratObs" placeholder="Motivo da gratuidade, autorização, condição comercial..."></textarea>
            </div>
          </div>

          <div class="form-actions">
            <button class="btn" type="button" onclick="calcularAbatidoAutomatico()">Calcular abatido</button>
            <button class="btn gradient" type="submit">Salvar gratuidade</button>
          </div>
        </form>
      </section>

      <section class="panel">
        <h3>Resumo mensal</h3>
        <div class="monthly-grid" id="monthlyGrid"></div>
      </section>

      <section class="panel">
        <h3>Lista de gratuidades</h3>

        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Data</th>
                <th>Evento</th>
                <th>Origem</th>
                <th>Valor evento</th>
                <th>Valor pago</th>
                <th>Valor abatido</th>
                <th>Observação</th>
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
    const money = (value) => Number(value || 0).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });

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

    function escapeHTML(value) {
      return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    function calcularAbatidoAutomatico() {
      const valorEvento = numberBR(document.getElementById("gratValorEvento").value);
      const valorPago = numberBR(document.getElementById("gratValorPago").value);
      const abatido = Math.max(valorEvento - valorPago, 0);

      document.getElementById("gratValorAbatido").value = abatido.toLocaleString("pt-BR", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      });
    }

    function limparFiltros() {
      document.getElementById("filterDe").value = "";
      document.getElementById("filterAte").value = "";
      document.getElementById("filterOrigem").value = "todas";
      carregarGratuidades();
    }

    async function carregarGratuidades() {
      const params = new URLSearchParams();
      const de = document.getElementById("filterDe").value;
      const ate = document.getElementById("filterAte").value;
      const origem = document.getElementById("filterOrigem").value;

      if (de) params.set("de", de);
      if (ate) params.set("ate", ate);
      if (origem) params.set("origem", origem);

      const response = await fetch(`/api/gratuidades?${params.toString()}`, {
        cache: "no-store"
      });

      const data = await response.json();

      if (!data.ok) {
        alert(data.message || "Erro ao carregar gratuidades.");
        return;
      }

      renderResumo(data.resumo || {});
      renderMensal(data.porMes || []);
      renderTabela(data.itens || []);

      const atualizado = data.atualizadoEm
        ? new Date(data.atualizadoEm).toLocaleString("pt-BR")
        : "agora";

      document.getElementById("statusText").textContent =
        `Dados atualizados em ${atualizado}. Inclui descontos do relatório e lançamentos manuais.`;
    }

    function renderResumo(resumo) {
      document.getElementById("kpiAbatido").textContent = money(resumo.valorAbatido || 0);
      document.getElementById("kpiValorEvento").textContent = money(resumo.valorEvento || 0);
      document.getElementById("kpiValorPago").textContent = money(resumo.valorPago || 0);
      document.getElementById("kpiPercentual").textContent = `${Number(resumo.percentualPerda || 0).toFixed(1).replace(".", ",")}%`;
      document.getElementById("kpiAbatidoInfo").textContent = `${resumo.quantidade || 0} registro(s)`;
    }

    function renderMensal(meses) {
      const container = document.getElementById("monthlyGrid");

      container.innerHTML = meses.map((mes) => `
        <article class="month-card">
          <span>${escapeHTML(mes.mes)}</span>
          <strong>${money(mes.valorAbatido)}</strong>
          <small>${mes.quantidade} registro(s) • pago ${money(mes.valorPago)}</small>
        </article>
      `).join("") || `<div class="empty">Nenhuma gratuidade no período selecionado.</div>`;
    }

    function renderTabela(itens) {
      const body = document.getElementById("gratuidadesBody");

      body.innerHTML = itens.map((item) => {
        const manual = item.origem === "manual";
        const obs = item.observacao || (manual ? "Lançamento manual" : "Detectado pelo relatório");

        return `
          <tr>
            <td>${escapeHTML(item.data || "")}</td>
            <td>
              <strong>${escapeHTML(item.evento || "Evento")}</strong>
              <span>${escapeHTML(item.empresa || item.status || "")}</span>
            </td>
            <td>
              <span class="tag ${manual ? "manual" : "relatorio"}">${manual ? "Manual" : "Relatório"}</span>
            </td>
            <td>${money(item.valorEvento)}</td>
            <td>${money(item.valorPago)}</td>
            <td><strong>${money(item.valorAbatido)}</strong></td>
            <td>${escapeHTML(obs)}</td>
            <td>
              ${manual ? `<button class="btn red" onclick="excluirGratuidade('${item.id}')">Excluir</button>` : `<span class="tag relatorio">Automático</span>`}
            </td>
          </tr>
        `;
      }).join("") || `<tr><td colspan="8" class="empty">Nenhuma gratuidade encontrada.</td></tr>`;
    }

    async function excluirGratuidade(id) {
      if (!confirm("Excluir esta gratuidade manual?")) return;

      const response = await fetch(`/api/gratuidades/${encodeURIComponent(id)}`, {
        method: "DELETE"
      });

      const data = await response.json();

      if (!data.ok) {
        alert(data.message || "Erro ao excluir.");
        return;
      }

      await carregarGratuidades();
    }

    document.getElementById("formGratuidade").addEventListener("submit", async (event) => {
      event.preventDefault();

      const payload = {
        data: document.getElementById("gratData").value,
        evento: document.getElementById("gratEvento").value,
        empresa: document.getElementById("gratEmpresa").value,
        valorEvento: document.getElementById("gratValorEvento").value,
        valorPago: document.getElementById("gratValorPago").value,
        valorAbatido: document.getElementById("gratValorAbatido").value,
        observacao: document.getElementById("gratObs").value
      };

      const response = await fetch("/api/gratuidades", {
        method: "POST",
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

      event.target.reset();
      await carregarGratuidades();
      alert("Gratuidade salva.");
    });

    carregarGratuidades();
  </script>

  <script>
    (function () {
      const PAGE_PERMS = {
        "dashboard.html": "painel",
        "agenda.html": "agenda",
        "orcamentos.html": "orcamentos",
        "importar-relatorio.html": "relatorios",
        "tarefas.html": "tarefas",
        "servidor.html": "servidor",
        "financeiro.html": "financeiro",
        "gratuidades.html": "gratuidades",
        "usuarios.html": "usuarios",
        "configuracoes.html": "configuracoes"
      };

      async function aplicarPermissoesMenu() {
        try {
          const response = await fetch("/api/me", {
            cache: "no-store"
          });

          const data = await response.json();

          if (!data.ok || !data.user) return;

          const permissoes = data.user.permissoes || [];
          const admin = permissoes.includes("*");

          document.querySelectorAll("a[href$='.html']").forEach(link => {
            const href = link.getAttribute("href");
            const page = href.split("/").pop();
            const required = PAGE_PERMS[page];

            if (required && !admin && !permissoes.includes(required)) {
              link.remove();
            }
          });
        } catch {}
      }

      aplicarPermissoesMenu();
    })();
  </script>

  <script src="/js/cejas-mobile-menu.js?v=1"></script>
</body>
</html>
EOF

python3 <<'PY'
from pathlib import Path

html_files = [p for p in Path('.').glob('*.html') if p.name not in {'login.html'}]

for p in html_files:
    s = p.read_text()

    if 'href="gratuidades.html"' not in s and 'href="/gratuidades.html"' not in s:
        replacements = [
            ('<a href="financeiro.html">💰 Financeiro</a>', '<a href="financeiro.html">💰 Financeiro</a>\n        <a href="gratuidades.html">🏷 Gratuidades</a>'),
            ('<a href="/financeiro.html">💰 Financeiro</a>', '<a href="/financeiro.html">💰 Financeiro</a>\n        <a href="/gratuidades.html">🏷 Gratuidades</a>'),
            ('<a href="importar-relatorio.html">▤ Importar Relatório (PDF)</a>', '<a href="gratuidades.html">🏷 Gratuidades</a>\n        <a href="importar-relatorio.html">▤ Importar Relatório (PDF)</a>'),
            ('<a href="/importar-relatorio.html">▤ Importar Relatório (PDF)</a>', '<a href="/gratuidades.html">🏷 Gratuidades</a>\n        <a href="/importar-relatorio.html">▤ Importar Relatório (PDF)</a>')
        ]

        for old, new in replacements:
            if old in s:
                s = s.replace(old, new, 1)
                break

    if p.name == 'gratuidades.html':
        s = s.replace('<a href="gratuidades.html">🏷 Gratuidades</a>', '<a class="active" href="gratuidades.html">🏷 Gratuidades</a>')
        s = s.replace('<a class="active" class="active" href="gratuidades.html">', '<a class="active" href="gratuidades.html">')

    if '"gratuidades.html": "gratuidades"' not in s and 'const PAGE_PERMS' in s:
        s = s.replace('"financeiro.html": "financeiro",', '"financeiro.html": "financeiro",\n      "gratuidades.html": "gratuidades",')

    p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path('js/cejas-mobile-menu.js')

if p.exists():
    s = p.read_text()

    if 'Gratuidades' not in s:
        s = s.replace(
            '{ href: "/financeiro.html", texto: "💰 Financeiro" },',
            '{ href: "/financeiro.html", texto: "💰 Financeiro" },\n      { href: "/gratuidades.html", texto: "🏷 Gratuidades" },'
        )

        p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path('dashboard.html')
s = p.read_text()

css_marker = '    @media (max-width: 1300px) {'

css = r'''
    .cejas-financeiro-real {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 20px;
      margin-bottom: 20px;
    }

    .cejas-financeiro-head {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 14px;
      margin-bottom: 16px;
    }

    .cejas-financeiro-head h3 {
      font-size: 20px;
      margin-bottom: 7px;
    }

    .cejas-financeiro-head p {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.45;
    }

    .cejas-monthly-revenue {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 12px;
    }

    .cejas-month-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 16px;
      cursor: pointer;
      transition: .2s ease;
    }

    .cejas-month-card:hover {
      transform: translateY(-2px);
      border-color: rgba(255,255,255,.18);
    }

    .cejas-month-card span {
      color: var(--muted);
      font-size: 12px;
      font-weight: 900;
      text-transform: uppercase;
      letter-spacing: .08em;
    }

    .cejas-month-card strong {
      display: block;
      font-size: 24px;
      margin: 9px 0 7px;
    }

    .cejas-month-card small {
      color: var(--green);
      font-weight: 900;
    }

    .cejas-loss-card {
      margin-top: 14px;
      background: rgba(239,68,68,.08);
      border: 1px solid rgba(239,68,68,.18);
      border-radius: 16px;
      padding: 16px;
      display: flex;
      justify-content: space-between;
      gap: 14px;
      align-items: center;
    }

    .cejas-loss-card span {
      color: var(--muted);
      display: block;
      font-size: 12px;
      font-weight: 900;
      text-transform: uppercase;
      letter-spacing: .08em;
      margin-bottom: 6px;
    }

    .cejas-loss-card strong {
      font-size: 24px;
      color: #fecaca;
    }

'''

if 'cejas-financeiro-real' not in s and css_marker in s:
    s = s.replace(css_marker, css + css_marker, 1)

section_marker = '      <section class="modules">'

section = r'''      <section class="cejas-financeiro-real">
        <div class="cejas-financeiro-head">
          <div>
            <h3>Receita mensal confirmada</h3>
            <p>Valores calculados somente com eventos confirmados do relatório importado. Ao trocar o PDF, este painel atualiza junto.</p>
          </div>

          <a class="btn gradient" href="gratuidades.html">Abrir gratuidades</a>
        </div>

        <div class="cejas-monthly-revenue" id="cejasReceitaMensal">
          <div style="color:var(--muted);">Importe um relatório para carregar a receita mensal.</div>
        </div>

        <div class="cejas-loss-card" onclick="location.href='gratuidades.html'">
          <div>
            <span>Gratuidades e abatimentos</span>
            <strong id="cejasTotalGratuidades">R$ 0,00</strong>
          </div>

          <button class="btn">Ver detalhes →</button>
        </div>
      </section>

'''

if 'id="cejasReceitaMensal"' not in s and section_marker in s:
    s = s.replace(section_marker, section + section_marker, 1)

if 'Gratuidades</h4>' not in s:
    module_marker = '          <article class="module-card">\n            <div class="icon">📄</div>'

    module = '''          <article class="module-card">
            <div class="icon">🏷</div>
            <h4>Gratuidades</h4>
            <p>Controle valores abatidos, pagos e perdas por mês ou período.</p>
            <a href="gratuidades.html">Abrir gratuidades →</a>
          </article>

'''

    if module_marker in s:
        s = s.replace(module_marker, module + module_marker, 1)

script_marker = '    function renderBars(eventos) {'

extra_js = r'''    function nomeMesDashboardCejas(key) {
      const nomes = [
        "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
        "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
      ];

      const [ano, mes] = String(key || "").split("-");
      const idx = Number(mes) - 1;

      return nomes[idx] ? `${nomes[idx]} de ${ano}` : key;
    }

    async function atualizarFinanceiroDashboardCejas() {
      try {
        const response = await fetch("/api/dashboard-financeiro", {
          cache: "no-store"
        });

        const data = await response.json();

        if (!data.ok) return;

        const container = document.getElementById("cejasReceitaMensal");
        const meses = data.receitaMensal || [];
        const recentes = meses.slice(-12);

        container.innerHTML = recentes.map((mes) => `
          <article class="cejas-month-card" onclick="location.href='gratuidades.html'" title="Clique para abrir o controle financeiro">
            <span>${nomeMesDashboardCejas(mes.key)}</span>
            <strong>${money(mes.receitaConfirmada || 0)}</strong>
            <small>${mes.eventosConfirmados || 0} evento(s) confirmado(s)</small>
          </article>
        `).join("") || `<div style="color:var(--muted);">Nenhuma receita confirmada encontrada no relatório atual.</div>`;

        const grat = data.resumo?.gratuidades || {};
        document.getElementById("cejasTotalGratuidades").textContent = money(grat.valorAbatido || 0);
      } catch (error) {
        const container = document.getElementById("cejasReceitaMensal");

        if (container) {
          container.innerHTML = `<div style="color:var(--muted);">Não foi possível carregar a receita mensal.</div>`;
        }
      }
    }

'''

if 'atualizarFinanceiroDashboardCejas' not in s and script_marker in s:
    s = s.replace(script_marker, extra_js + script_marker, 1)

s = s.replace('<h3>Receitas vs. Despesas</h3>', '<h3>Receita confirmada por mês</h3>')

old = '''        if (evento.status === "em_espera") {
          meses[key].pendente += Number(evento.valor || 0);
        }
'''

if old in s:
    s = s.replace(old, '''        // O dashboard financeiro mostra somente receita confirmada. Pendentes ficam fora deste gráfico.
''', 1)

old_return = '''          `<div class="bar" style="height:${hReceita}px" title="Receita ${money(v.receita)}"></div>`,
          `<div class="bar red" style="height:${hPendente}px" title="Em espera ${money(v.pendente)}"></div>`'''

if old_return in s:
    s = s.replace(old_return, '''          `<div class="bar" style="height:${hReceita}px" title="Receita confirmada ${money(v.receita)}"></div>`''', 1)

if 'atualizarFinanceiroDashboardCejas();' not in s:
    s = s.replace(
        '    atualizarDashboardReal();',
        '    atualizarDashboardReal();\n    atualizarFinanceiroDashboardCejas();',
        1
    )

    s = s.replace(
        '    window.addEventListener("focus", atualizarDashboardReal);',
        '    window.addEventListener("focus", () => {\n      atualizarDashboardReal();\n      atualizarFinanceiroDashboardCejas();\n    });',
        1
    )

    s = s.replace(
        '    setInterval(atualizarDashboardReal, 30000);',
        '    setInterval(() => {\n      atualizarDashboardReal();\n      atualizarFinanceiroDashboardCejas();\n    }, 30000);',
        1
    )

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path('README.md')

if p.exists():
    s = p.read_text()

    if 'Gratuidades' not in s:
        s = s.replace(
            '- **Financeiro**: demonstrativos, controle e leitura de relatórios.',
            '- **Financeiro**: demonstrativos, controle e leitura de relatórios.\n- **Gratuidades**: controle de abatimentos por evento, valor cheio, valor pago, valor perdido, filtros mensais, anuais e por período.'
        )

        p.write_text(s)
PY

node --check server.js

[ -f js/cejas-mobile-menu.js ] && node --check js/cejas-mobile-menu.js || true

python3 <<'PY'
from pathlib import Path
import re

Path('.cejas-local-backups').mkdir(exist_ok=True)

for html in ['dashboard.html', 'gratuidades.html']:
    s = Path(html).read_text()

    for i, script in enumerate(re.findall(r'<script[^>]*>(.*?)</script>', s, re.S), 1):
        test = Path(f'.cejas-local-backups/check-{html}-{i}.js')
        test.write_text(script)
PY

for f in .cejas-local-backups/check-dashboard.html-*.js .cejas-local-backups/check-gratuidades.html-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -f .cejas-local-backups/check-dashboard.html-*.js .cejas-local-backups/check-gratuidades.html-*.js

echo ""
echo "✅ Patch aplicado: aba Gratuidades + filtros + dashboard com receita mensal confirmada."
echo ""
echo "Agora rode: npm run dev"
echo "Abra: http://localhost:5500/gratuidades.html"
echo "Dashboard: http://localhost:5500/dashboard.html"
