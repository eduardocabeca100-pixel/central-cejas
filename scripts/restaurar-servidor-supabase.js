const path = require("path");
const {
  BUCKET,
  restaurarSupabaseParaDiretorioServidor
} = require("../lib/servidor-storage-persistente");

(async () => {
  const root = path.join(process.cwd(), "uploads", "servidor");
  const result = await restaurarSupabaseParaDiretorioServidor(root);
  console.log("✅ Restore Supabase → local concluído:", result);
  console.log("Bucket:", BUCKET);
})().catch((error) => {
  console.error("❌ Erro no restore Supabase → local:", error.message);
  process.exit(1);
});
