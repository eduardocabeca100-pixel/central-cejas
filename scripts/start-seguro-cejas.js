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

  
  // CEJAS_RESTORE_RELATORIOS_SUPERA_STORAGE_START
  try {
    const {
      statusRelatoriosSuperaStorage,
      restaurarRelatoriosSuperaDoStorage
    } = require("../lib/relatorios-supera-storage-cejas");

    console.log("📊 Status relatórios Supera Storage:", statusRelatoriosSuperaStorage());

    const restoreRelatorios = await restaurarRelatoriosSuperaDoStorage();
    console.log("✅ Relatórios Supera restaurados do Storage:", restoreRelatorios);
  } catch (error) {
    console.warn("⚠️ Restore relatórios Supera ignorado:", error.message);
  }
  // CEJAS_RESTORE_RELATORIOS_SUPERA_STORAGE_END

  console.log("🚀 Abrindo servidor...");
  require("../server.js");
})();
