#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "scripts/start-seguro-cejas.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/start-sem-restore-servidor-$STAMP"
mkdir -p "$BACKUP_DIR"

cp scripts/start-seguro-cejas.js "$BACKUP_DIR/start-seguro-cejas.js" 2>/dev/null || true
cp package.json "$BACKUP_DIR/package.json" 2>/dev/null || true

cat > scripts/start-seguro-cejas.js <<'EOF'
require("dotenv").config();

(async () => {
  console.log("🛡️ Iniciando CEJAS em modo seguro...");
  console.log("📦 Servidor de arquivos: Supabase Storage direto.");
  console.log("⚠️ Não será feita restauração de uploads locais no start.");

  try {
    const { statusPersistenciaCejas } = require("../lib/persistencia-total-supabase");

    const status = await statusPersistenciaCejas().catch((error) => ({
      ok: false,
      message: error.message
    }));

    console.log("📊 Status de persistência:", status);
  } catch (error) {
    console.warn("⚠️ Check de persistência ignorado:", error.message);
  }

  try {
    const { getSupabaseRuntimeStatus } = require("../lib/servidor-supabase-definitivo");
    console.log("📊 Status Storage runtime:", getSupabaseRuntimeStatus());
  } catch (error) {
    console.warn("⚠️ Check Storage runtime ignorado:", error.message);
  }

  console.log("🚀 Abrindo servidor...");
  require("../server.js");
})();
EOF

node --check scripts/start-seguro-cejas.js
node --check server.js
node --check lib/servidor-supabase-definitivo.js

echo ""
echo "✅ Start corrigido."
echo ""
echo "Agora teste:"
echo "npm start"
