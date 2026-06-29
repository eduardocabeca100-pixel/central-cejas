const path = require("path");
const {
  BUCKET,
  enviarDiretorioParaSupabaseServidor
} = require("../lib/servidor-storage-persistente");

(async () => {
  const root = path.join(process.cwd(), "uploads", "servidor");
  const result = await enviarDiretorioParaSupabaseServidor(root);
  console.log("✅ Sync local → Supabase concluído:", result);
  console.log("Bucket:", BUCKET);
})().catch((error) => {
  console.error("❌ Erro no sync local → Supabase:", error.message);
  process.exit(1);
});
