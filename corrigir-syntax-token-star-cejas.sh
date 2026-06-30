#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/fix-token-star-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js "$BACKUP_DIR/server.js"
[ -f lib/servidor-supabase-definitivo.js ] && cp lib/servidor-supabase-definitivo.js "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

echo ""
echo "🔎 Procurando linhas suspeitas com */ solto..."
grep -n "^\s*\*/" server.js || true

python3 <<'PY'
from pathlib import Path
import re

p = Path("server.js")
s = p.read_text()

# Remove blocos antigos que foram comentados por patches anteriores e podem ter quebrado a sintaxe.
s = re.sub(
    r'/\*\s*ROTA ANTIGA[^*]*\*/',
    '',
    s,
    flags=re.S
)

s = re.sub(
    r'/\*\s*ROTA ANTIGA DESATIVADA RESET SUPABASE ONLY[\s\S]*?\*/',
    '',
    s
)

s = re.sub(
    r'/\*\s*ROTA ANTIGA SERVIDOR DESATIVADA PELO PATCH SUPABASE DEFINITIVO[\s\S]*?\*/',
    '',
    s
)

# Remove qualquer fechamento de comentário solto no começo de linha.
s = re.sub(r'^\s*\*/\s*$', '', s, flags=re.M)

# Remove qualquer abertura de comentário solta que ficou sem fechamento em linha isolada.
s = re.sub(r'^\s*/\*\s*$', '', s, flags=re.M)

# Garante require único.
require_line = 'const { registrarRotasServidorSupabaseDefinitivo } = require("./lib/servidor-supabase-definitivo");'
s = s.replace(require_line, "")

if 'const path = require("path");' in s:
    s = s.replace(
        'const path = require("path");',
        'const path = require("path");\n' + require_line,
        1
    )
else:
    s = require_line + "\n" + s

# Remove registros duplicados.
s = re.sub(r'\n\s*registrarRotasServidorSupabaseDefinitivo\(app\);\s*', '\n', s)

# Insere registro único após const app = express().
marker = "const app = express();"
if marker not in s:
    raise SystemExit("❌ Não encontrei const app = express(); no server.js.")

s = s.replace(marker, marker + "\nregistrarRotasServidorSupabaseDefinitivo(app);", 1)

p.write_text(s)
PY

echo ""
echo "🔎 Verificando sintaxe do server.js..."
node --check server.js

echo ""
echo "🔎 Verificando módulo Supabase Storage..."
node --check lib/servidor-supabase-definitivo.js

echo ""
echo "🧪 Testando start por 5 segundos..."
PORT=5999 node -e '
process.env.PORT = "5999";
require("./server.js");
setTimeout(() => {
  console.log("✅ Servidor iniciou sem SyntaxError.");
  process.exit(0);
}, 5000);
' || {
  echo ""
  echo "❌ Ainda quebrou. Rode:"
  echo "node --check server.js"
  echo "e me mande o erro completo com linha/coluna."
  exit 1
}

echo ""
echo "✅ SyntaxError corrigido."
echo ""
echo "Agora rode:"
echo "npm start"
