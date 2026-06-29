#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "lib/servidor-supabase-definitivo.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/debug-auth-storage-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js lib/servidor-supabase-definitivo.js lib/supabase-runtime-cejas.js package.json "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

# 1) Corrige lib/servidor-supabase-definitivo.js
p = Path("lib/servidor-supabase-definitivo.js")
s = p.read_text()

# Garante função de compatibilidade com o nome antigo.
if "function getSupabaseRuntimeEnvServidor" not in s:
    insert_before = "module.exports ="
    compat = r'''
function getSupabaseRuntimeEnvServidor() {
  return getSupabaseRuntimeStatus();
}

'''
    if insert_before in s:
        s = s.replace(insert_before, compat + insert_before, 1)

# Garante export da função antiga e da nova.
if "getSupabaseRuntimeEnvServidor" not in s.split("module.exports")[-1]:
    s = s.replace(
        "getSupabaseRuntimeStatus\n};",
        "getSupabaseRuntimeStatus,\n  getSupabaseRuntimeEnvServidor\n};"
    )

# Corrige headers do Supabase Storage: precisa Authorization.
pattern = r'''function storageHeaders\(extra = \{\}\) \{[\s\S]*?\n\}'''

new_headers = r'''function storageHeaders(extra = {}) {
  const env = assertStorageEnv();

  return {
    apikey: env.serviceRole,
    Authorization: `Bearer ${env.serviceRole}`,
    ...extra
  };
}'''

if re.search(pattern, s):
    s = re.sub(pattern, new_headers, s, count=1)

p.write_text(s)

# 2) Corrige lib/supabase-runtime-cejas.js, se existir.
p2 = Path("lib/supabase-runtime-cejas.js")
if p2.exists():
    s2 = p2.read_text()

    if "function getSupabaseRuntimeEnvServidor" not in s2:
        if "module.exports =" in s2:
            s2 = s2.replace(
                "module.exports =",
                "function getSupabaseRuntimeEnvServidor() {\n  return getSupabaseRuntimeStatus();\n}\n\nmodule.exports =",
                1
            )

    if "getSupabaseRuntimeEnvServidor" not in s2.split("module.exports")[-1]:
        s2 = s2.replace(
            "getStorageBucket\n};",
            "getStorageBucket,\n  getSupabaseRuntimeEnvServidor\n};"
        )
        s2 = s2.replace(
            "getSupabaseRuntimeStatus,",
            "getSupabaseRuntimeStatus,\n  getSupabaseRuntimeEnvServidor,"
        )

    p2.write_text(s2)

# 3) Remove rotas antigas de debug que chamam função inexistente.
server = Path("server.js")
ss = server.read_text()

ss = re.sub(
    r'\n// CEJAS_DEBUG_STORAGE_RUNTIME_START[\s\S]*?// CEJAS_DEBUG_STORAGE_RUNTIME_END',
    '',
    ss
)

ss = re.sub(
    r'\n// CEJAS_SUPABASE_ENV_DEBUG_START[\s\S]*?// CEJAS_SUPABASE_ENV_DEBUG_END',
    '',
    ss
)

# 4) Insere uma única rota de debug correta.
debug_route = r'''
// CEJAS_DEBUG_STORAGE_RUNTIME_START
app.get("/api/debug/storage-runtime", (_req, res) => {
  try {
    const { getSupabaseRuntimeStatus } = require("./lib/servidor-supabase-definitivo");

    res.json({
      ok: true,
      storage: getSupabaseRuntimeStatus()
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_DEBUG_STORAGE_RUNTIME_END

'''

marker = "const app = express();"

if marker not in ss:
    raise SystemExit("❌ Não encontrei const app = express(); no server.js.")

ss = ss.replace(marker, marker + "\n" + debug_route, 1)

server.write_text(ss)
PY

echo ""
echo "🔎 Verificando sintaxe..."

node --check lib/servidor-supabase-definitivo.js
[ -f lib/supabase-runtime-cejas.js ] && node --check lib/supabase-runtime-cejas.js || true
node --check server.js

echo ""
echo "🔎 Procurando chamadas antigas quebradas..."
grep -R "getSupabaseRuntimeEnvServidor" -n server.js lib || true

echo ""
echo "✅ Correção aplicada."
echo ""
echo "Agora rode:"
echo "npm run dev"
