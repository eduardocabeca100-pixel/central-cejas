const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(process.cwd(), "data");
const RELATORIO_SUPERA_FILE = path.join(DATA_DIR, "relatorio-supera.json");
const RELATORIO_ATUAL_FILE = path.join(DATA_DIR, "relatorio-atual.json");

function numero(valor) {
  if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

  const s = String(valor || "")
    .replace(/R\$/gi, "")
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".")
    .replace(/[^\d.-]/g, "");

  const n = Number(s);
  return Number.isFinite(n) ? n : 0;
}

function pareceEvento(item) {
  if (!item || typeof item !== "object" || Array.isArray(item)) return false;

  return Boolean(
    item.evento ||
    item.nomeEvento ||
    item.titulo ||
    item.title ||
    item.data ||
    item.dataEvento ||
    item.sala ||
    item.local ||
    item.status ||
    item.valorTotal ||
    item.valor_total ||
    item.receitaConfirmada ||
    item.valorPago ||
    item.empresa ||
    item.solicitante
  );
}

function extrairEventos(obj, lista = [], visitados = new Set()) {
  if (!obj || typeof obj !== "object") return lista;
  if (visitados.has(obj)) return lista;

  visitados.add(obj);

  if (Array.isArray(obj)) {
    const eventosDaLista = obj.filter(pareceEvento);

    if (eventosDaLista.length >= 10) {
      lista.push(...eventosDaLista);
      return lista;
    }

    obj.forEach(item => extrairEventos(item, lista, visitados));
    return lista;
  }

  Object.values(obj).forEach(value => {
    if (value && typeof value === "object") {
      extrairEventos(value, lista, visitados);
    }
  });

  return lista;
}

function lerRelatorio() {
  const arquivos = [RELATORIO_SUPERA_FILE, RELATORIO_ATUAL_FILE];

  for (const arquivo of arquivos) {
    try {
      if (!fs.existsSync(arquivo)) continue;

      const dados = JSON.parse(fs.readFileSync(arquivo, "utf8"));
      const eventos = Array.isArray(dados.eventos) && dados.eventos.length
        ? dados.eventos
        : extrairEventos(dados);

      if (eventos.length || dados.totalEventos || dados.total_eventos || dados.resumo) {
        return {
          arquivo,
          dados,
          eventos
        };
      }
    } catch {}
  }

  return {
    arquivo: null,
    dados: {},
    eventos: []
  };
}

function statusTexto(item) {
  return String(
    item.status ||
    item.situacao ||
    item.estado ||
    item.confirmacao ||
    item.tipoStatus ||
    ""
  ).toUpperCase();
}

function isConfirmado(item) {
  const s = statusTexto(item);

  if (!s) return false;

  return s.includes("CONFIRM") ||
    s.includes("REALIZAD") ||
    s.includes("APROVAD") ||
    s.includes("LIBERAD") ||
    s.includes("PAGO");
}

function isCancelado(item) {
  const s = statusTexto(item);

  return s.includes("CANCEL");
}

function isPendente(item) {
  const s = statusTexto(item);

  return s.includes("PEND") ||
    s.includes("ESPERA") ||
    s.includes("AGUARD") ||
    s.includes("ORÇAMENTO") ||
    s.includes("ORCAMENTO");
}

function valorEvento(item) {
  const campos = [
    item.valorTotal,
    item.valor_total,
    item.total,
    item.valor,
    item.valorPrevisto,
    item.valor_previsto,
    item.faturamentoPrevisto,
    item.faturamento_previsto,
    item.preco,
    item.preço
  ];

  for (const c of campos) {
    const n = numero(c);
    if (n > 0) return n;
  }

  return 0;
}

function receitaEvento(item) {
  const campos = [
    item.receitaConfirmada,
    item.receita_confirmada,
    item.valorConfirmado,
    item.valor_confirmado,
    item.valorPago,
    item.valor_pago,
    item.pago,
    item.recebido
  ];

  for (const c of campos) {
    const n = numero(c);
    if (n > 0) return n;
  }

  if (isConfirmado(item)) return valorEvento(item);

  return 0;
}

function descontoEvento(item) {
  const campos = [
    item.desconto,
    item.descontos,
    item.valorDesconto,
    item.valor_desconto,
    item.gratuidade,
    item.valorGratuidade,
    item.valor_gratuidade
  ];

  for (const c of campos) {
    const n = Math.abs(numero(c));
    if (n > 0) return n;
  }

  return 0;
}

function dataEvento(item) {
  const candidatos = [
    item.data,
    item.dataEvento,
    item.data_evento,
    item.inicio,
    item.start,
    item.date
  ];

  for (const c of candidatos) {
    if (!c) continue;

    if (typeof c === "string") {
      const br = c.match(/\b(\d{1,2})[\/.-](\d{1,2})[\/.-](20\d{2})\b/);
      if (br) return new Date(Number(br[3]), Number(br[2]) - 1, Number(br[1]));

      const iso = Date.parse(c);
      if (Number.isFinite(iso)) return new Date(iso);
    }
  }

  return null;
}

function resumoNumero(dados, ...chaves) {
  const fontes = [dados, dados.resumo, dados.totais, dados.dashboard].filter(Boolean);

  for (const fonte of fontes) {
    for (const chave of chaves) {
      const n = numero(fonte[chave]);
      if (n > 0) return n;
    }
  }

  return 0;
}

function montarDashboard() {
  const { arquivo, dados, eventos } = lerRelatorio();

  const totalEventos =
    resumoNumero(dados, "totalEventos", "total_eventos") ||
    eventos.length;

  const eventosConfirmados =
    resumoNumero(dados, "eventosConfirmados", "eventos_confirmados") ||
    eventos.filter(isConfirmado).length;

  const eventosEmEspera =
    resumoNumero(dados, "eventosEmEspera", "eventos_em_espera") ||
    eventos.filter(isPendente).length;

  const eventosCancelados =
    resumoNumero(dados, "eventosCancelados", "eventos_cancelados") ||
    eventos.filter(isCancelado).length;

  let faturamentoPrevisto =
    resumoNumero(
      dados,
      "faturamentoPrevisto",
      "faturamento_previsto",
      "valorPrevisto",
      "valor_previsto",
      "totalPrevisto",
      "total_previsto"
    );

  let receitaConfirmada =
    resumoNumero(
      dados,
      "receitaConfirmada",
      "receita_confirmada",
      "receita",
      "totalConfirmado",
      "total_confirmado",
      "valorConfirmado",
      "valor_confirmado"
    );

  let descontosAplicados =
    resumoNumero(
      dados,
      "descontosAplicados",
      "descontos_aplicados",
      "descontos",
      "totalDescontos",
      "total_descontos"
    );

  if (!faturamentoPrevisto) {
    faturamentoPrevisto = eventos.reduce((s, e) => s + valorEvento(e), 0);
  }

  if (!receitaConfirmada) {
    receitaConfirmada = eventos.reduce((s, e) => s + receitaEvento(e), 0);
  }

  if (!descontosAplicados) {
    descontosAplicados = eventos.reduce((s, e) => s + descontoEvento(e), 0);
  }

  const meses = Array.from({ length: 12 }, (_, i) => ({
    mes: i + 1,
    nome: [
      "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
      "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    ][i],
    receita: 0,
    eventos: 0
  }));

  eventos.forEach(evento => {
    const d = dataEvento(evento);
    if (!d) return;

    const idx = d.getMonth();
    meses[idx].eventos += 1;
    meses[idx].receita += receitaEvento(evento);
  });

  return {
    ok: true,
    fonte: arquivo,
    atualizadoEm: new Date().toISOString(),
    nomeArquivo: dados.nomeArquivo || dados.nome_arquivo || "relatorio-supera.json",
    totalEventos,
    eventosConfirmados,
    eventosEmEspera,
    eventosCancelados,
    eventosNaLista: eventos.length,
    faturamentoPrevisto,
    receitaConfirmada,
    descontosAplicados,
    fluxoCaixa: receitaConfirmada - descontosAplicados,
    meses
  };
}

function registrarDashboardRelatorioOficialCejas(app) {
  if (!app || app.__CEJAS_DASHBOARD_RELATORIO_OFICIAL__) return;

  app.__CEJAS_DASHBOARD_RELATORIO_OFICIAL__ = true;

  app.get("/api/dashboard/relatorio-oficial", (_req, res) => {
    try {
      res.set("Cache-Control", "no-store");
      res.json(montarDashboard());
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });
}

module.exports = {
  montarDashboard,
  registrarDashboardRelatorioOficialCejas
};
