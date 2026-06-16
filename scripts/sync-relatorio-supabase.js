const fs = require("fs");
const path = require("path");
const { supabaseAdmin, isSupabaseConfigured } = require("../lib/supabase");

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

async function main() {
  if (!isSupabaseConfigured()) {
    console.error("❌ Supabase não configurado no .env.");
    process.exit(1);
  }

  const reportPath = path.join(__dirname, "..", "data", "relatorio-supera.json");

  if (!fs.existsSync(reportPath)) {
    console.error("❌ Nenhum relatório local encontrado.");
    console.error("Importe primeiro o PDF do Supera em importar-relatorio.html");
    process.exit(1);
  }

  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  const resumo = report.resumo || {};

  console.log("📄 Relatório local encontrado.");
  console.log(`📌 Eventos detectados: ${(report.eventos || []).length}`);

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

  if (relatorioError) throw new Error(relatorioError.message);

  const totalInserido = await inserirEventos(relatorio.id, report.eventos || []);

  console.log("✅ Relatório sincronizado com o Supabase.");
  console.log(`✅ Relatório ID: ${relatorio.id}`);
  console.log(`✅ Eventos inseridos: ${totalInserido}`);
}

main().catch((error) => {
  console.error("❌ Erro ao sincronizar:", error.message);
  process.exit(1);
});
