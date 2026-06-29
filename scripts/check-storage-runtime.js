require("dotenv").config();

const {
  getSupabaseRuntimeStatus
} = require("../lib/supabase-runtime-cejas");

const status = getSupabaseRuntimeStatus();

console.log("");
console.log("🔎 Runtime Supabase Storage CEJAS");
console.log(JSON.stringify(status, null, 2));
console.log("");

if (!status.ok) {
  console.error("❌ O runtime ainda não está enxergando as variáveis.");
  process.exit(1);
}

console.log("✅ Runtime Supabase Storage configurado.");
