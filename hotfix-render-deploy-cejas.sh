#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "lib/servidor-supabase-definitivo.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/hotfix-render-deploy-$STAMP"
mkdir -p "$BACKUP_DIR"
cp server.js lib/servidor-supabase-definitivo.js package.json "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("lib/servidor-supabase-definitivo.js")
s = p.read_text()

# Corrige erro principal: express usado no arquivo sem import.
if 'const express = require("express");' not in s:
    s = s.replace(
        'const fs = require("fs");',
        'const fs = require("fs");\nconst express = require("express");',
        1
    )

# Evita quebrar o start se o Storage não estiver disponível no primeiro segundo.
# As rotas continuam existindo, mas erro de Supabase aparece como resposta da API, não derruba o deploy.
s = s.replace(
'''function registrarRotasServidorSupabaseDefinitivo(app) {
  app.get("/api/servidor/tree", async (_req, res) => {''',
'''function registrarRotasServidorSupabaseDefinitivo(app) {
  if (!app) {
    throw new Error("App Express não informado para registrar rotas do servidor.");
  }

  app.get("/api/servidor/tree", async (_req, res) => {''',
1
)

p.write_text(s)

# Garante que o server.js registra as rotas uma única vez.
server = Path("server.js")
ss = server.read_text()

ss = re.sub(
    r'\nregistrarRotasServidorSupabaseDefinitivo\(app\);\n(?:\s*registrarRotasServidorSupabaseDefinitivo\(app\);\n)+',
    '\nregistrarRotasServidorSupabaseDefinitivo(app);\n',
    ss
)

server.write_text(ss)
PY

echo ""
echo "🔎 Verificando sintaxe..."

node --check lib/servidor-supabase-definitivo.js
node --check server.js
node --check scripts/check-servidor-definitivo.js 2>/dev/null || true

echo ""
echo "🧪 Testando se o servidor consegue iniciar por alguns segundos..."

PORT=5999 node -e '
process.env.PORT = process.env.PORT || "5999";
require("./server.js");
setTimeout(() => {
  console.log("✅ Servidor iniciou sem quebrar.");
  process.exit(0);
}, 3500);
' || {
  echo ""
  echo "❌ O servidor ainda quebrou ao iniciar."
  echo "Mostre o erro acima ou copie o log do Render."
  exit 1
}

echo ""
echo "✅ Hotfix aplicado."
echo ""
echo "Agora rode:"
echo "git add ."
echo "git commit -m \"fix: corrige deploy Render do servidor Supabase\""
echo "git push -u origin main"
