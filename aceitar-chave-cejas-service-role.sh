#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "lib/supabase-runtime-cejas.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/service-role-env-$STAMP"
mkdir -p "$BACKUP_DIR"
cp lib/supabase-runtime-cejas.js "$BACKUP_DIR/" 2>/dev/null || true

python3 <<'PY'
from pathlib import Path

p = Path("lib/supabase-runtime-cejas.js")
s = p.read_text()

s = s.replace(
'''  const serviceRole =
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE);''',
'''  const serviceRole =
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.CEJAS_SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE) ||
    cleanEnv(process.env.SUPABASE_SECRET_KEY);'''
)

s = s.replace(
'''    has_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),''',
'''    has_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    has_CEJAS_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.CEJAS_SUPABASE_SERVICE_ROLE_KEY),'''
)

p.write_text(s)
PY

node --check lib/supabase-runtime-cejas.js

echo ""
echo "✅ Sistema agora aceita também CEJAS_SUPABASE_SERVICE_ROLE_KEY."
echo ""
echo "Agora rode:"
echo "git add ."
echo "git commit -m \"fix: aceita chave service role alternativa no Render\""
echo "git push -u origin main"
