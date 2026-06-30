const { restoreDataDoSupabase, statusDadosSupabase } = require("../lib/dados-supabase-cejas");

(async () => {
  console.log("Status:", statusDadosSupabase());
  const result = await restoreDataDoSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro ao restaurar data/:", error.message);
  process.exit(1);
});
