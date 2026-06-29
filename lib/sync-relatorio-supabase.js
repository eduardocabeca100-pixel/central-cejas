const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

function dataBRParaISO(dataBR) {
  if (!dataBR || !String(dataBR).includes("/")) return null;

  const [dia, mes, ano] = String(dataBR).split("/");

  if (!dia || !mes || !ano) return null;

  return `${ano}-${mes.padStart(2, "0")}-${dia.padStart(2, "0")}`;
}

function valorNumero(value) {
  const numero = Number(value || 0);
  return Number.isFinite(numero) ? numero : 0;
}

function gerarHashRelatorio(report) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify({
      arquivo: report.arquivo || "",
      resumo: report.resumo || {},
      eventos: report.eventos || []
    }))
    .digest("hex");
}

async function apagarRelatoriosSupabase() {
  if (!isSupabaseConfigured()) {
    return {
      ok: false,
      skipped: true,
      message: "Supabase não configurado no .env."
    };
  }

  const zeroUuid = "00000000-0000-0000-0000-000000000000";

  const eventosDelete = await supabaseAdmin
    .from("cejas_eventos")
    .delete()
    .neq("id", zeroUuid);

  if (eventosDelete.error) {
    throw new Error("Erro ao apagar eventos do Supabase: " + eventosDelete.error.message);
  }

  const relatoriosDelete = await supabaseAdmin
    .from("cejas_relatorios")
    .delete()
    .neq("id", zeroUuid);

  if (relatoriosDelete.error) {
    throw new Error("Erro ao apagar relatórios do Supabase: " + relatoriosDelete.error.message);
  }

  return {
    ok: true,
    message: "Relatórios e eventos apagados do Supabase."
  };
}

async function inserirEventos(relatorioId, eventos) {
  const linhas = (eventos || []).map((evento) => ({
    relatorio_id: relatorioId,
    data_evento: dataBRParaISO(evento.data),
    hora_inicial: evento.horaInicial || null,
    hora_final: evento.horaFinal || null,
    sala: evento.sala || null,
    empresa: evento.empresa || null,
    evento: evento.evento || null,
    status: evento.status || null,
    participantes: Number(evento.participantes || 0),
    valor: valorNumero(evento.valor),
    desconto: valorNumero(evento.desconto),
    produtos: evento.produtos || [],
    bloco_original: evento.blocoOriginal || null
  }));

  const chunkSize = 500;

  for (let i = 0; i < linhas.length; i += chunkSize) {
    const chunk = linhas.slice(i, i + chunkSize);

    const { error } = await supabaseAdmin
      .from("cejas_eventos")
      .insert(chunk);

    if (error) throw new Error(error.message);
  }

  return linhas.length;
}

async function syncRelatorioAtualComSupabase(options = {}) {
  if (!isSupabaseConfigured()) {
    return {
      ok: false,
      skipped: true,
      message: "Supabase não configurado no .env."
    };
  }

  const reportPath = options.reportPath || path.join(__dirname, "..", "data", "relatorio-supera.json");

  if (!fs.existsSync(reportPath)) {
    return {
      ok: false,
      skipped: true,
      message: "Nenhum relatório local encontrado."
    };
  }

  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  const resumo = report.resumo || {};
  const eventos = report.eventos || [];

  if (!eventos.length) {
    return {
      ok: true,
      skipped: true,
      eventosInseridos: 0,
      message: "Relatório vazio. Nada foi enviado ao Supabase."
    };
  }

  const hash = gerarHashRelatorio(report);

  // CEJAS_RELATORIO_NAO_APAGAR_HISTORICO
  // Não apagar histórico: apenas marca relatórios anteriores como inativos.
  await supabaseAdmin
    .from("cejas_relatorios")
    .update({ ativo: false })
    .eq("ativo", true);

  const { data: relatorio, error: relatorioError } = await supabaseAdmin
    .from("cejas_relatorios")
    .insert({
      nome_arquivo: report.arquivo || "relatorio-supera.pdf",
      total_eventos: Number(resumo.totalEventos || 0),
      eventos_confirmados: Number(resumo.eventosConfirmados || 0),
      eventos_em_espera: Number(resumo.eventosPendentes || 0),
      eventos_cancelados: Number(resumo.eventosCancelados || 0),
      faturamento_previsto: valorNumero(resumo.faturamentoPrevisto),
      receita_confirmada: valorNumero(resumo.receitaConfirmada),
      descontos_aplicados: valorNumero(resumo.descontosAplicados),
      ativo: true
    })
    .select("id")
    .single();

  if (relatorioError) {
    throw new Error(relatorioError.message);
  }

  const totalInserido = await inserirEventos(relatorio.id, eventos);

  return {
    ok: true,
    relatorioId: relatorio.id,
    eventosInseridos: totalInserido,
    hash,
    mensagem: "Relatório sincronizado com o Supabase."
  };
}

module.exports = {
  syncRelatorioAtualComSupabase,
  apagarRelatoriosSupabase
};
