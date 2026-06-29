const { syncTudoCejas } = require("../lib/persistencia-total-supabase");

(async () => {
  const result = await syncTudoCejas("manual-script");
  console.log(JSON.stringify(result, null, 2));

  if (!result.ok && !result.skipped) {
    process.exit(1);
  }
})().catch((error) => {
  console.error("❌ Erro no sync:", error.message);
  process.exit(1);
});
