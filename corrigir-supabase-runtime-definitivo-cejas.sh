#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "lib/servidor-supabase-definitivo.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/correcao-supabase-runtime-definitivo-$STAMP"
mkdir -p "$BACKUP_DIR" lib scripts

cp server.js lib/servidor-supabase-definitivo.js package.json "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

cat > lib/supabase-runtime-cejas.js <<'EOF'
require("dotenv").config();

const { createClient } = require("@supabase/supabase-js");

let cachedAdmin = null;
let cachedSignature = "";

function cleanEnv(value) {
  return String(value || "")
    .trim()
    .replace(/^["']|["']$/g, "");
}

function getRuntimeEnv() {
  const url =
    cleanEnv(process.env.SUPABASE_URL) ||
    cleanEnv(process.env.NEXT_PUBLIC_SUPABASE_URL) ||
    cleanEnv(process.env.PUBLIC_SUPABASE_URL);

  const serviceRole =
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE);

  const bucket =
    cleanEnv(process.env.SUPABASE_STORAGE_BUCKET) ||
    cleanEnv(process.env.SUPABASE_BUCKET) ||
    "servidor-cejas";

  return {
    url,
    serviceRole,
    bucket
  };
}

function getSupabaseRuntimeStatus() {
  const env = getRuntimeEnv();

  return {
    ok: Boolean(env.url && env.serviceRole && env.bucket),
    bucket: env.bucket,
    resolvedUrl: Boolean(env.url),
    resolvedServiceRole: Boolean(env.serviceRole),
    resolvedBucket: Boolean(env.bucket),
    has_SUPABASE_URL: Boolean(process.env.SUPABASE_URL),
    has_NEXT_PUBLIC_SUPABASE_URL: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    has_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    has_SUPABASE_STORAGE_BUCKET: Boolean(process.env.SUPABASE_STORAGE_BUCKET),
    lengths: {
      url: env.url ? env.url.length : 0,
      serviceRole: env.serviceRole ? env.serviceRole.length : 0,
      bucket: env.bucket ? env.bucket.length : 0
    }
  };
}

function getSupabaseAdmin() {
  const env = getRuntimeEnv();

  if (!env.url || !env.serviceRole) {
    throw new Error(
      "Supabase Storage não configurado no runtime. Status: " +
      JSON.stringify(getSupabaseRuntimeStatus())
    );
  }

  const signature = `${env.url}::${env.serviceRole.slice(0, 12)}::${env.bucket}`;

  if (!cachedAdmin || cachedSignature !== signature) {
    cachedAdmin = createClient(env.url, env.serviceRole, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });

    cachedSignature = signature;
  }

  return cachedAdmin;
}

function getStorageBucket() {
  return getRuntimeEnv().bucket || "servidor-cejas";
}

module.exports = {
  getRuntimeEnv,
  getSupabaseRuntimeStatus,
  getSupabaseAdmin,
  getStorageBucket
};
EOF

python3 <<'PY'
from pathlib import Path
import re

p = Path("lib/servidor-supabase-definitivo.js")
s = p.read_text()

# Imports obrigatórios
if 'const express = require("express");' not in s:
    s = s.replace('const fs = require("fs");', 'const fs = require("fs");\nconst express = require("express");', 1)

if 'const { getSupabaseAdmin, getStorageBucket, getSupabaseRuntimeStatus } = require("./supabase-runtime-cejas");' not in s:
    s = s.replace(
        'const path = require("path");',
        'const path = require("path");\nconst { getSupabaseAdmin, getStorageBucket, getSupabaseRuntimeStatus } = require("./supabase-runtime-cejas");',
        1
    )

# Remove import antigo da lib/supabase, se existir
s = re.sub(
    r'\nconst\s*\{\s*supabaseAdmin,\s*isSupabaseConfigured,\s*SUPABASE_BUCKET\s*\}\s*=\s*require\(["\']\.\/supabase["\']\);\s*',
    '\n',
    s,
    flags=re.S
)

# Remove definições antigas de BUCKET e injeta a nova
s = re.sub(r'\nconst BUCKET\s*=\s*[^;]+;', '', s)

runtime_import = 'const { getSupabaseAdmin, getStorageBucket, getSupabaseRuntimeStatus } = require("./supabase-runtime-cejas");'
if runtime_import in s and 'const BUCKET = getStorageBucket();' not in s:
    s = s.replace(runtime_import, runtime_import + '\nconst BUCKET = getStorageBucket();', 1)

# Troca todos os usos antigos do client
s = s.replace("supabaseAdmin.storage", "getSupabaseAdmin().storage")
s = s.replace("getSupabaseAdminServidor().storage", "getSupabaseAdmin().storage")

def replace_function(source, name, replacement):
    marker = f"function {name}("
    start = source.find(marker)
    if start == -1:
        return source

    brace = source.find("{", start)
    if brace == -1:
        return source

    depth = 0
    i = brace

    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[:start] + replacement + source[i + 1:]
        i += 1

    return source

def replace_async_function(source, name, replacement):
    marker = f"async function {name}("
    start = source.find(marker)
    if start == -1:
        return source

    brace = source.find("{", start)
    if brace == -1:
        return source

    depth = 0
    i = brace

    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[:start] + replacement + source[i + 1:]
        i += 1

    return source

s = replace_function(s, "storageAtivo", '''function storageAtivo() {
  const status = getSupabaseRuntimeStatus();
  return Boolean(status.ok);
}''')

s = replace_async_function(s, "garantirBucket", '''async function garantirBucket() {
  const status = getSupabaseRuntimeStatus();

  if (!status.ok) {
    throw new Error(
      "Supabase Storage não configurado no runtime. Status: " +
      JSON.stringify(status)
    );
  }

  const admin = getSupabaseAdmin();
  const bucketName = getStorageBucket();

  const { data, error } = await admin.storage.listBuckets();

  if (error) {
    throw new Error("Erro ao listar buckets do Supabase: " + error.message);
  }

  const existe = (data || []).some(bucket => bucket.name === bucketName);

  if (!existe) {
    const created = await admin.storage.createBucket(bucketName, {
      public: false,
      fileSizeLimit: null
    });

    if (created.error && !String(created.error.message || "").toLowerCase().includes("already")) {
      throw new Error("Erro ao criar bucket " + bucketName + ": " + created.error.message);
    }
  }

  return true;
}''')

# Garante export do diagnóstico
if "getSupabaseRuntimeStatus" not in s.split("module.exports")[-1]:
    s = s.replace(
        "destinoInteligente\n};",
        "destinoInteligente,\n  getSupabaseRuntimeStatus\n};"
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
    const { getSupabaseRuntimeStatus } = require("./lib/supabase-runtime-cejas");

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

if "CEJAS_DEBUG_STORAGE_RUNTIME_START" not in s:
    marker = "const app = express();"

    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express(); no server.js.")

    s = s.replace(marker, marker + "\n" + route, 1)

p.write_text(s)
PY

cat > scripts/check-storage-runtime.js <<'EOF'
require("dotenv").config();

const {
  getSupabaseRuntimeStatus
} = require("../lib/supabase-runtime-cejas");

const status = getSupabaseRuntimeStatus();

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
node --check lib/supabase-runtime-cejas.js
node --check lib/servidor-supabase-definitivo.js
node --check server.js
node --check scripts/check-storage-runtime.js

echo ""
echo "🧪 Testando variáveis localmente..."
npm run storage:runtime || true

echo ""
echo "✅ Hotfix aplicado."
echo ""
echo "Agora rode:"
echo "npm run dev"
