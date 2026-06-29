const { garantirBucket, listarArquivos } = require("../lib/servidor-supabase-definitivo");

(async () => {
  await garantirBucket();
  const arquivos = await listarArquivos();

  console.log("✅ Servidor conectado ao Supabase Storage definitivo.");
  console.log("Arquivos no Storage:", arquivos.length);
  arquivos.slice(0, 30).forEach(item => console.log("-", item));
})().catch(error => {
  console.error("❌ Erro no servidor definitivo:", error.message);
  process.exit(1);
});
