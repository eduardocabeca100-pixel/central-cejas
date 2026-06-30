const { syncDataParaSupabase, statusDadosSupabase } = require("../lib/dados-supabase-cejas");

(async () => {
  console.log("Status:", statusDadosSupabase());
  const result = await syncDataParaSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro ao sincronizar data/:", error.message);
  process.exit(1);
});
