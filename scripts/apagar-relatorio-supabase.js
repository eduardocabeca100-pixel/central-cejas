const fs = require("fs");
const path = require("path");
const { apagarRelatoriosSupabase } = require("../lib/sync-relatorio-supabase");

async function main() {
  const dataDir = path.join(__dirname, "..", "data");
  const relatorioPath = path.join(dataDir, "relatorio-supera.json");
  const textoPath = path.join(dataDir, "ultimo-relatorio-texto-extraido.txt");

  if (fs.existsSync(relatorioPath)) {
    fs.unlinkSync(relatorioPath);
    console.log("🗑️ Relatório local apagado.");
  }

  if (fs.existsSync(textoPath)) {
    fs.unlinkSync(textoPath);
    console.log("🗑️ Texto extraído local apagado.");
  }

  const result = await apagarRelatoriosSupabase();

  if (!result.ok && !result.skipped) {
    throw new Error(result.message || "Erro ao apagar Supabase.");
  }

  console.log("✅", result.message || "Relatório apagado do Supabase.");
}

main().catch((error) => {
  console.error("❌ Erro ao apagar relatório:", error.message);
  process.exit(1);
});
