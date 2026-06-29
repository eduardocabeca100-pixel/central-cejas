require("dotenv").config();

const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRole = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE;
const bucket = process.env.SUPABASE_STORAGE_BUCKET || process.env.SUPABASE_BUCKET || "servidor-cejas";

console.log("");
console.log("🔎 Check de ambiente Supabase/Render");
console.log("");

console.log("SUPABASE_URL / NEXT_PUBLIC_SUPABASE_URL:", url ? "✅ configurado" : "❌ faltando");
console.log("SUPABASE_SERVICE_ROLE_KEY:", serviceRole ? "✅ configurado" : "❌ faltando");
console.log("SUPABASE_STORAGE_BUCKET:", bucket ? `✅ ${bucket}` : "❌ faltando");

console.log("");

if (!url || !serviceRole || !bucket) {
  console.error("❌ Ambiente incompleto. Corrija no Render > Environment.");
  process.exit(1);
}

console.log("✅ Ambiente mínimo configurado.");
