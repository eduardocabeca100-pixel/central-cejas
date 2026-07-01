const {
  statusRelatorioOficialSupabase,
  restaurarRelatorioOficialDoSupabase
} = require("../lib/relatorio-oficial-supabase-cejas");

(async () => {
  console.log("📊 Status relatório oficial:", statusRelatorioOficialSupabase());
  const result = await restaurarRelatorioOficialDoSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro ao restaurar relatório oficial:", error.message);
  process.exit(1);
});
