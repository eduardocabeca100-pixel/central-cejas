#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde fica server.js."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/correcao-regex-server-$STAMP"
mkdir -p "$BACKUP_DIR"
cp server.js "$BACKUP_DIR/server.js"

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

antes = s

# Corrige regex quebrado que aparece como: replace(/\/g, "/")
# O correto para trocar barra invertida por barra normal é: replace(/\\/g, "/")
s = s.replace('replace(/\\/g, "/")', 'replace(/\\\\/g, "/")')
s = s.replace("replace(/\\/g, '/')", "replace(/\\\\/g, '/')")

# Correções específicas caso tenha ficado quebrado em linhas do servidor.
s = s.replace('relativePath.replace(/\\/g, "/")', 'relativePath.replace(/\\\\/g, "/")')
s = s.replace('path.join(relPath, entry.name).replace(/\\/g, "/")', 'path.join(relPath, entry.name).replace(/\\\\/g, "/")')
s = s.replace('path.relative(SERVIDOR_DIR, target).replace(/\\/g, "/")', 'path.relative(SERVIDOR_DIR, target).replace(/\\\\/g, "/")')
s = s.replace('path.relative(SERVIDOR_DIR, destino).replace(/\\/g, "/")', 'path.relative(SERVIDOR_DIR, destino).replace(/\\\\/g, "/")')

p.write_text(s)

print("✅ Correções aplicadas:", "sim" if s != antes else "nenhuma alteração necessária")
PY

echo ""
echo "🔎 Verificando sintaxe do server.js..."

if node --check server.js; then
  echo ""
  echo "✅ server.js corrigido e sem erro de sintaxe."
else
  echo ""
  echo "❌ Ainda existe erro. Mostrando região provável:"
  nl -ba server.js | sed -n '3400,3445p'
  exit 1
fi

echo ""
echo "🔎 Verificando arquivos principais..."

[ -f lib/servidor-storage-persistente.js ] && node --check lib/servidor-storage-persistente.js || true
[ -f lib/sync-relatorio-supabase.js ] && node --check lib/sync-relatorio-supabase.js || true

echo ""
echo "✅ Correção finalizada."
echo ""
echo "Agora rode:"
echo "npm run dev"
