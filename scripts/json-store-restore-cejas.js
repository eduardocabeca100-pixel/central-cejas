const {
  statusJsonStore,
  restaurarJsonsDoSupabase
} = require("../lib/json-store-supabase-cejas");

(async () => {
  console.log("📊 Status JSON Store:", statusJsonStore());
  const result = await restaurarJsonsDoSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro no restore JSON Store:", error.message);
  process.exit(1);
});
