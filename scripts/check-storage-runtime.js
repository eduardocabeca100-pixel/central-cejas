require("dotenv").config();

const {
  getSupabaseRuntimeEnvServidor
} = require("../lib/servidor-supabase-definitivo");

const status = getSupabaseRuntimeEnvServidor();

console.log("");
console.log("🔎 Runtime Supabase Storage CEJAS");
console.log(JSON.stringify(status, null, 2));
console.log("");

if (!status.ok) {
  console.error("❌ O runtime ainda não está enxergando as variáveis.");
  process.exit(1);
}

console.log("✅ Runtime Supabase Storage configurado.");
