#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "lib/servidor-supabase-definitivo.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/runtime-supabase-render-$STAMP"
mkdir -p "$BACKUP_DIR" scripts
cp server.js lib/servidor-supabase-definitivo.js package.json "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("lib/servidor-supabase-definitivo.js")
s = p.read_text()

# Garante imports necessários.
if 'const express = require("express");' not in s:
    s = s.replace('const fs = require("fs");', 'const fs = require("fs");\nconst express = require("express");', 1)

if 'const { createClient } = require("@supabase/supabase-js");' not in s:
    s = s.replace('const path = require("path");', 'const path = require("path");\nconst { createClient } = require("@supabase/supabase-js");', 1)

# Remove dependência antiga da lib/supabase dentro do servidor definitivo.
s = re.sub(
    r'''const\s*\{\s*supabaseAdmin,\s*isSupabaseConfigured,\s*SUPABASE_BUCKET\s*\}\s*=\s*require\(["']\.\/supabase["']\);\s*
const BUCKET\s*=\s*process\.env\.SUPABASE_STORAGE_BUCKET\s*\|\|\s*SUPABASE_BUCKET\s*\|\|\s*["']servidor-cejas["'];''',
    r'''function limparEnvServidorCejas(value) {
  return String(value || "").trim().replace(/^["']|["']$/g, "");
}

function getSupabaseRuntimeEnvRawServidor() {
  const url =
    limparEnvServidorCejas(process.env.SUPABASE_URL) ||
    limparEnvServidorCejas(process.env.NEXT_PUBLIC_SUPABASE_URL) ||
    limparEnvServidorCejas(process.env.PUBLIC_SUPABASE_URL);

  const serviceRole =
    limparEnvServidorCejas(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    limparEnvServidorCejas(process.env.SUPABASE_SERVICE_KEY) ||
    limparEnvServidorCejas(process.env.SUPABASE_SERVICE_ROLE);

  const bucket =
    limparEnvServidorCejas(process.env.SUPABASE_STORAGE_BUCKET) ||
    limparEnvServidorCejas(process.env.SUPABASE_BUCKET) ||
    "servidor-cejas";

  return { url, serviceRole, bucket };
}

function getSupabaseRuntimeEnvServidor() {
  const env = getSupabaseRuntimeEnvRawServidor();

  return {
    ok: Boolean(env.url && env.serviceRole && env.bucket),
    has_SUPABASE_URL: Boolean(process.env.SUPABASE_URL),
    has_NEXT_PUBLIC_SUPABASE_URL: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    has_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    has_SUPABASE_STORAGE_BUCKET: Boolean(process.env.SUPABASE_STORAGE_BUCKET),
    resolvedUrl: Boolean(env.url),
    resolvedServiceRole: Boolean(env.serviceRole),
    resolvedBucket: Boolean(env.bucket),
    bucket: env.bucket,
    lengths: {
      url: env.url ? env.url.length : 0,
      serviceRole: env.serviceRole ? env.serviceRole.length : 0,
      bucket: env.bucket ? env.bucket.length : 0
    }
  };
}

let supabaseAdminSingletonServidor = null;
let supabaseAdminSignatureServidor = "";

function getSupabaseAdminServidor() {
  const env = getSupabaseRuntimeEnvRawServidor();

  if (!env.url || !env.serviceRole) {
    const status = getSupabaseRuntimeEnvServidor();

    throw new Error(
      "Supabase Storage não configurado no runtime. " +
      "Status: " + JSON.stringify(status)
    );
  }

  const signature = `${env.url}::${env.serviceRole.slice(0, 12)}::${env.bucket}`;

  if (!supabaseAdminSingletonServidor || supabaseAdminSignatureServidor !== signature) {
    supabaseAdminSingletonServidor = createClient(env.url, env.serviceRole, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });

    supabaseAdminSignatureServidor = signature;
  }

  return supabaseAdminSingletonServidor;
}

const BUCKET = getSupabaseRuntimeEnvRawServidor().bucket || "servidor-cejas";''',
    s,
    count=1,
    flags=re.S
)

# Substitui uso antigo do cliente.
s = s.replace("supabaseAdmin.", "getSupabaseAdminServidor().")

# Corrige função storageAtivo para não depender da lib antiga.
s = re.sub(
    r'''function storageAtivo\(\)\s*\{\s*return Boolean\([\s\S]*?\);\s*\}''',
    r'''function storageAtivo() {
  const env = getSupabaseRuntimeEnvRawServidor();
  return Boolean(env.url && env.serviceRole && env.bucket);
}''',
    s,
    count=1
)

# Exporta diagnóstico.
if "getSupabaseRuntimeEnvServidor" not in s.split("module.exports")[-1]:
    s = s.replace(
        "destinoInteligente\n};",
        "destinoInteligente,\n  getSupabaseRuntimeEnvServidor\n};"
    )

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

route = r'''
// CEJAS_DEBUG_STORAGE_RUNTIME_START
app.get("/api/debug/storage-runtime", (_req, res) => {
  try {
    const { getSupabaseRuntimeEnvServidor } = require("./lib/servidor-supabase-definitivo");

    res.json({
      ok: true,
      storage: getSupabaseRuntimeEnvServidor()
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

if "CEJAS_DEBUG_STORAGE_RUNTIME_START" not in s:
    marker = "const app = express();"

    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express();")

    s = s.replace(marker, marker + "\n" + route, 1)

p.write_text(s)
PY

cat > scripts/check-storage-runtime.js <<'EOF'
require("dotenv").config();

const {
  getSupabaseRuntimeEnvServidor
} = require("../lib/servidor-supabase-definitivo");

const status = getSupabaseRuntimeEnvServidor();

console.log("");
console.log("🔎 Runtime Supabase Storage CEJAS");
console.log(JSON.stringify(status, null, 2));
console.log("");

if (!status.ok) {
  console.error("❌ O runtime ainda não está enxergando as variáveis.");
  process.exit(1);
}

console.log("✅ Runtime Supabase Storage configurado.");
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["storage:runtime"] = "node scripts/check-storage-runtime.js"
p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

echo ""
echo "🔎 Verificando sintaxe..."

node --check lib/servidor-supabase-definitivo.js
node --check server.js
node --check scripts/check-storage-runtime.js

echo ""
echo "🧪 Testando runtime local..."
npm run storage:runtime || true

echo ""
echo "✅ Hotfix aplicado."
echo ""
echo "Agora rode:"
echo "npm run dev"
