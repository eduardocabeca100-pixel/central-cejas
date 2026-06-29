const {
  BUCKET,
  garantirBucketServidor,
  listarArquivosStorageServidor
} = require("../lib/servidor-storage-persistente");

(async () => {
  await garantirBucketServidor();
  const arquivos = await listarArquivosStorageServidor();
  console.log("✅ Supabase Storage conectado.");
  console.log("Bucket:", BUCKET);
  console.log("Arquivos no Storage:", arquivos.length);
  arquivos.slice(0, 30).forEach((item) => console.log("-", item));
})().catch((error) => {
  console.error("❌ Falha no Supabase Storage:", error.message);
  process.exit(1);
});
