#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "lib/dashboard-relatorio-oficial-cejas.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/dashboard-rota-publica-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js "$BACKUP_DIR/server.js"

python3 <<'PY'
from pathlib import Path
import re

p = Path("server.js")
s = p.read_text()

# Remove bloco antigo se já existir
s = re.sub(
    r'\n?// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_START[\s\S]*?// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_END\n?',
    '\n',
    s
)

require_line = 'const { montarDashboard: montarDashboardRelatorioOficialCejasPublico } = require("./lib/dashboard-relatorio-oficial-cejas");'

if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace(
            'const path = require("path");',
            'const path = require("path");\n' + require_line,
            1
        )
    elif 'const express = require("express");' in s:
        s = s.replace(
            'const express = require("express");',
            'const express = require("express");\n' + require_line,
            1
        )
    else:
        s = require_line + "\n" + s

bloco = '''
// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_START
// Esta rota precisa ficar ANTES das travas de sessão.
// Ela só entrega o resumo do relatório oficial restaurado do Supabase.
app.use("/api/dashboard/relatorio-oficial", (req, res, next) => {
  if (req.method !== "GET") return next();

  try {
    res.set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
    res.set("Pragma", "no-cache");
    res.set("Expires", "0");
    return res.json(montarDashboardRelatorioOficialCejasPublico());
  } catch (error) {
    return res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_DASHBOARD_OFICIAL_PUBLIC_ROUTE_END

'''

marker = "const app = express();"

if marker not in s:
    raise SystemExit("❌ Não encontrei const app = express();")

s = s.replace(marker, marker + "\n" + bloco, 1)

p.write_text(s)
PY

echo ""
echo "🔎 Verificando sintaxe..."
node --check server.js
node --check lib/dashboard-relatorio-oficial-cejas.js

echo ""
echo "✅ Rota pública do dashboard corrigida."
echo ""
echo "Agora rode:"
echo "npm start"
