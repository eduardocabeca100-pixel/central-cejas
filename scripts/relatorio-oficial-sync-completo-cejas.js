const {
  syncRelatorioCompletoParaSupabase
} = require("../lib/relatorio-oficial-sync-cejas");

(async () => {
  const result = await syncRelatorioCompletoParaSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro ao sincronizar relatório completo:", error.message);
  process.exit(1);
});
