const {
  statusRelatoriosSuperaStorage,
  syncRelatoriosSuperaParaStorage
} = require("../lib/relatorios-supera-storage-cejas");

(async () => {
  console.log("📊 Status relatórios Supera Storage:", statusRelatoriosSuperaStorage());
  const result = await syncRelatoriosSuperaParaStorage();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro no sync dos relatórios Supera:", error.message);
  process.exit(1);
});
