const { statusPersistenciaCejas } = require("../lib/persistencia-total-supabase");

(async () => {
  const result = await statusPersistenciaCejas();
  console.log(JSON.stringify(result, null, 2));

  if (!result.ok) {
    process.exit(1);
  }
})().catch((error) => {
  console.error("❌ Erro no check:", error.message);
  process.exit(1);
});
