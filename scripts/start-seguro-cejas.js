require("dotenv").config();

(async () => {
  console.log("🛡️ Iniciando CEJAS em modo seguro...");
  console.log("📦 Servidor de arquivos: Supabase Storage direto.");

  try {
    const { restoreDataDoSupabase, statusDadosSupabase } = require("../lib/dados-supabase-cejas");

    console.log("📊 Status data/Supabase:", statusDadosSupabase());

    const restore = await restoreDataDoSupabase();
    console.log("✅ data/ restaurado do Supabase:", restore);
  } catch (error) {
    console.warn("⚠️ Restore de data/ ignorado:", error.message);
  }

  try {
    const { getSupabaseRuntimeStatus } = require("../lib/servidor-supabase-definitivo");
    console.log("📊 Status Storage runtime:", getSupabaseRuntimeStatus());
  } catch (error) {
    console.warn("⚠️ Check Storage runtime ignorado:", error.message);
  }

  console.log("🚀 Abrindo servidor...");
  require("../server.js");
})();
