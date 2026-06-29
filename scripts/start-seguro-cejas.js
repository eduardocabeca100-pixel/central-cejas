const {
  restoreTudoCejas,
  statusPersistenciaCejas
} = require("../lib/persistencia-total-supabase");

(async () => {
  console.log("🛡️ Iniciando CEJAS com restauração segura do Supabase...");

  try {
    const statusAntes = await statusPersistenciaCejas().catch((error) => ({
      ok: false,
      message: error.message
    }));

    console.log("📊 Status Supabase antes do start:", statusAntes);

    const restore = await restoreTudoCejas("startup");
    console.log("✅ Restore antes do start:", restore);
  } catch (error) {
    console.error("⚠️ Falha ao restaurar dados antes do start:", error.message);
    console.error("⚠️ O sistema vai iniciar, mas você precisa verificar a persistência.");
  }

  require("../server.js");
})();
