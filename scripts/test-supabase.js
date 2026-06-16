const {
  supabaseAdmin,
  SUPABASE_BUCKET,
  isSupabaseConfigured
} = require("../lib/supabase");

async function main() {
  if (!isSupabaseConfigured()) {
    console.error("❌ Supabase não configurado. Confira SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no .env");
    process.exit(1);
  }

  const dbTest = await supabaseAdmin
    .from("cejas_configuracoes")
    .select("id")
    .limit(1);

  if (dbTest.error) {
    console.error("❌ Erro no banco:", dbTest.error.message);
    process.exit(1);
  }

  const storageTest = await supabaseAdmin
    .storage
    .from(SUPABASE_BUCKET)
    .list("", { limit: 1 });

  if (storageTest.error) {
    console.error("❌ Erro no storage:", storageTest.error.message);
    process.exit(1);
  }

  console.log("✅ Supabase conectado com sucesso.");
  console.log("✅ Banco OK.");
  console.log(`✅ Storage OK: ${SUPABASE_BUCKET}`);
}

main();
