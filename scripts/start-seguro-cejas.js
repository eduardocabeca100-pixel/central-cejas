require("dotenv").config();

(async () => {
  console.log("🛡️ Iniciando CEJAS em modo seguro...");
  console.log("📦 Dados JSON oficiais: Supabase cejas_json_store.");

  try {
    const {
      statusJsonStore,
      restaurarJsonsDoSupabase,
      aplicarPatchWriteFileJsonStore
    } = require("../lib/json-store-supabase-cejas");

    console.log("📊 Status JSON Store:", statusJsonStore());

    const restore = await restaurarJsonsDoSupabase();
    console.log("✅ JSONs restaurados do Supabase:", restore);

    aplicarPatchWriteFileJsonStore();
    console.log("✅ Sync automático de JSONs ativado.");
  } catch (error) {
    console.warn("⚠️ JSON Store Supabase ignorado:", error.message);
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
