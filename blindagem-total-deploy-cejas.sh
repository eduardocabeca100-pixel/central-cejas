#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e package.json."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/blindagem-total-deploy-$STAMP"
mkdir -p "$BACKUP_DIR" lib scripts

cp server.js package.json .gitignore .env.example "$BACKUP_DIR/" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true
[ -d uploads ] && cp -R uploads "$BACKUP_DIR/uploads" 2>/dev/null || true

echo "✅ Backup local criado em: $BACKUP_DIR"

cat > lib/persistencia-total-supabase.js <<'EOF'
const fs = require("fs");
const path = require("path");

const {
  supabaseAdmin,
  isSupabaseConfigured,
  SUPABASE_BUCKET
} = require("./supabase");

const BUCKET = process.env.SUPABASE_STORAGE_BUCKET || SUPABASE_BUCKET || "servidor-cejas";
const PREFIX_DATA = "_SISTEMA/data";

let syncRunning = false;
let restoreRunning = false;
let lastSyncAt = 0;

function ativo() {
  return Boolean(isSupabaseConfigured && isSupabaseConfigured() && supabaseAdmin && BUCKET);
}

function normalizarStoragePath(value = "") {
  return String(value || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => part && part !== "." && part !== "..")
    .join("/");
}

function contentType(filePath = "") {
  const ext = path.extname(String(filePath)).toLowerCase();

  const map = {
    ".json": "application/json",
    ".txt": "text/plain; charset=utf-8",
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".csv": "text/csv",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  };

  return map[ext] || "application/octet-stream";
}

async function garantirBucket() {
  if (!ativo()) {
    throw new Error("Supabase Storage não configurado. Confira SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e SUPABASE_STORAGE_BUCKET.");
  }

  const { data, error } = await supabaseAdmin.storage.listBuckets();

  if (error) {
    throw new Error("Erro ao listar buckets: " + error.message);
  }

  const existe = (data || []).some(bucket => bucket.name === BUCKET);

  if (!existe) {
    const created = await supabaseAdmin.storage.createBucket(BUCKET, {
      public: false,
      fileSizeLimit: null
    });

    if (created.error && !String(created.error.message || "").toLowerCase().includes("already")) {
      throw new Error("Erro ao criar bucket " + BUCKET + ": " + created.error.message);
    }
  }

  return true;
}

function listarArquivosLocais(rootDir, dir = rootDir, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;
    if (entry.name === ".DS_Store") continue;

    const full = path.join(dir, entry.name);
    const rel = path.relative(rootDir, full).replace(/\\/g, "/");

    if (entry.isDirectory()) {
      listarArquivosLocais(rootDir, full, result);
    } else if (entry.isFile()) {
      const stat = fs.statSync(full);
      result.push({
        full,
        rel,
        size: stat.size,
        updatedAt: stat.mtime.toISOString()
      });
    }
  }

  return result;
}

async function uploadArquivo(localPath, storagePath) {
  await garantirBucket();

  if (!fs.existsSync(localPath) || !fs.statSync(localPath).isFile()) {
    return { ok: false, skipped: true };
  }

  const buffer = fs.readFileSync(localPath);
  const cleanPath = normalizarStoragePath(storagePath);

  const { error } = await supabaseAdmin.storage.from(BUCKET).upload(cleanPath, buffer, {
    upsert: true,
    contentType: contentType(cleanPath),
    cacheControl: "3600"
  });

  if (error) {
    throw new Error(`Erro ao enviar ${cleanPath}: ${error.message}`);
  }

  return { ok: true, path: cleanPath };
}

async function downloadArquivo(storagePath) {
  await garantirBucket();

  const cleanPath = normalizarStoragePath(storagePath);
  const { data, error } = await supabaseAdmin.storage.from(BUCKET).download(cleanPath);

  if (error || !data) return null;

  const arrayBuffer = await data.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

async function listarStorage(prefix = "") {
  await garantirBucket();

  const folder = normalizarStoragePath(prefix);
  const result = [];
  let offset = 0;
  const limit = 1000;

  while (true) {
    const { data, error } = await supabaseAdmin.storage.from(BUCKET).list(folder, {
      limit,
      offset,
      sortBy: { column: "name", order: "asc" }
    });

    if (error) {
      throw new Error("Erro ao listar Storage: " + error.message);
    }

    const batch = data || [];

    for (const item of batch) {
      if (!item || !item.name || item.name === ".emptyFolderPlaceholder") continue;

      const itemPath = folder ? `${folder}/${item.name}` : item.name;
      const isFile = item.metadata && typeof item.metadata.size === "number";

      if (isFile) {
        result.push({
          type: "file",
          path: itemPath,
          name: item.name,
          size: Number(item.metadata.size || 0),
          updatedAt: item.updated_at || item.created_at || ""
        });
      } else {
        result.push({
          type: "folder",
          path: itemPath,
          name: item.name,
          children: await listarStorage(itemPath)
        });
      }
    }

    if (batch.length < limit) break;
    offset += limit;
  }

  return result;
}

function achatarArquivosStorage(tree, result = []) {
  for (const item of tree || []) {
    if (item.type === "file") result.push(item);
    if (item.children) achatarArquivosStorage(item.children, result);
  }

  return result;
}

async function listarArquivosStorage(prefix = "") {
  const tree = await listarStorage(prefix);
  return achatarArquivosStorage(tree);
}

async function syncDataParaSupabase() {
  const root = path.join(process.cwd(), "data");
  fs.mkdirSync(root, { recursive: true });

  const arquivos = listarArquivosLocais(root)
    .filter(item => item.rel.endsWith(".json") || item.rel.endsWith(".txt"));

  let enviados = 0;

  for (const item of arquivos) {
    await uploadArquivo(item.full, `${PREFIX_DATA}/${item.rel}`);
    enviados += 1;
  }

  return { ok: true, enviados };
}

async function restoreDataDoSupabase() {
  const root = path.join(process.cwd(), "data");
  fs.mkdirSync(root, { recursive: true });

  const arquivos = await listarArquivosStorage(PREFIX_DATA);
  let restaurados = 0;

  for (const item of arquivos) {
    const rel = item.path.replace(`${PREFIX_DATA}/`, "");
    const destino = path.join(root, rel);

    const buffer = await downloadArquivo(item.path);
    if (!buffer) continue;

    fs.mkdirSync(path.dirname(destino), { recursive: true });
    fs.writeFileSync(destino, buffer);
    restaurados += 1;
  }

  return { ok: true, restaurados, totalStorage: arquivos.length };
}

async function syncServidorParaSupabase() {
  const root = path.join(process.cwd(), "uploads", "servidor");
  fs.mkdirSync(root, { recursive: true });

  const arquivos = listarArquivosLocais(root);
  let enviados = 0;

  for (const item of arquivos) {
    if (item.rel.startsWith("_SISTEMA/")) continue;
    await uploadArquivo(item.full, item.rel);
    enviados += 1;
  }

  return { ok: true, enviados };
}

async function restoreServidorDoSupabase() {
  const root = path.join(process.cwd(), "uploads", "servidor");
  fs.mkdirSync(root, { recursive: true });

  const arquivos = (await listarArquivosStorage(""))
    .filter(item => !item.path.startsWith("_SISTEMA/"));

  let restaurados = 0;

  for (const item of arquivos) {
    const destino = path.join(root, item.path);

    if (fs.existsSync(destino)) continue;

    const buffer = await downloadArquivo(item.path);
    if (!buffer) continue;

    fs.mkdirSync(path.dirname(destino), { recursive: true });
    fs.writeFileSync(destino, buffer);
    restaurados += 1;
  }

  return { ok: true, restaurados, totalStorage: arquivos.length };
}

async function syncTudoCejas(motivo = "manual") {
  if (!ativo()) {
    return {
      ok: false,
      skipped: true,
      motivo,
      message: "Supabase Storage não configurado."
    };
  }

  if (syncRunning) {
    return {
      ok: true,
      skipped: true,
      motivo,
      message: "Sync já em andamento."
    };
  }

  const now = Date.now();

  if (motivo === "auto" && now - lastSyncAt < 8000) {
    return {
      ok: true,
      skipped: true,
      motivo,
      message: "Sync ignorado por intervalo curto."
    };
  }

  syncRunning = true;
  lastSyncAt = now;

  try {
    await garantirBucket();

    const data = await syncDataParaSupabase();
    const servidor = await syncServidorParaSupabase();

    return {
      ok: true,
      motivo,
      bucket: BUCKET,
      data,
      servidor,
      syncedAt: new Date().toISOString()
    };
  } finally {
    syncRunning = false;
  }
}

async function restoreTudoCejas(motivo = "startup") {
  if (!ativo()) {
    return {
      ok: false,
      skipped: true,
      motivo,
      message: "Supabase Storage não configurado."
    };
  }

  if (restoreRunning) {
    return {
      ok: true,
      skipped: true,
      motivo,
      message: "Restore já em andamento."
    };
  }

  restoreRunning = true;

  try {
    await garantirBucket();

    const data = await restoreDataDoSupabase();
    const servidor = await restoreServidorDoSupabase();

    return {
      ok: true,
      motivo,
      bucket: BUCKET,
      data,
      servidor,
      restoredAt: new Date().toISOString()
    };
  } finally {
    restoreRunning = false;
  }
}

async function statusPersistenciaCejas() {
  if (!ativo()) {
    return {
      ok: false,
      bucket: BUCKET,
      ativo: false,
      message: "Supabase Storage não configurado."
    };
  }

  await garantirBucket();

  const dataFiles = await listarArquivosStorage(PREFIX_DATA);
  const servidorFiles = (await listarArquivosStorage(""))
    .filter(item => !item.path.startsWith("_SISTEMA/"));

  const localData = listarArquivosLocais(path.join(process.cwd(), "data"));
  const localServidor = listarArquivosLocais(path.join(process.cwd(), "uploads", "servidor"));

  return {
    ok: true,
    ativo: true,
    bucket: BUCKET,
    storage: {
      data: dataFiles.length,
      servidor: servidorFiles.length
    },
    local: {
      data: localData.length,
      servidor: localServidor.length
    },
    checkedAt: new Date().toISOString()
  };
}

module.exports = {
  BUCKET,
  PREFIX_DATA,
  ativo,
  garantirBucket,
  syncTudoCejas,
  restoreTudoCejas,
  statusPersistenciaCejas,
  syncDataParaSupabase,
  restoreDataDoSupabase,
  syncServidorParaSupabase,
  restoreServidorDoSupabase
};
EOF

cat > scripts/start-seguro-cejas.js <<'EOF'
const {
  restoreTudoCejas,
  statusPersistenciaCejas
} = require("../lib/persistencia-total-supabase");

(async () => {
  console.log("🛡️ Iniciando CEJAS com restauração segura do Supabase...");

  try {
    const statusAntes = await statusPersistenciaCejas().catch((error) => ({
      ok: false,
      message: error.message
    }));

    console.log("📊 Status Supabase antes do start:", statusAntes);

    const restore = await restoreTudoCejas("startup");
    console.log("✅ Restore antes do start:", restore);
  } catch (error) {
    console.error("⚠️ Falha ao restaurar dados antes do start:", error.message);
    console.error("⚠️ O sistema vai iniciar, mas você precisa verificar a persistência.");
  }

  require("../server.js");
})();
EOF

cat > scripts/persistencia-sync.js <<'EOF'
const { syncTudoCejas } = require("../lib/persistencia-total-supabase");

(async () => {
  const result = await syncTudoCejas("manual-script");
  console.log(JSON.stringify(result, null, 2));

  if (!result.ok && !result.skipped) {
    process.exit(1);
  }
})().catch((error) => {
  console.error("❌ Erro no sync:", error.message);
  process.exit(1);
});
EOF

cat > scripts/persistencia-restore.js <<'EOF'
const { restoreTudoCejas } = require("../lib/persistencia-total-supabase");

(async () => {
  const result = await restoreTudoCejas("manual-script");
  console.log(JSON.stringify(result, null, 2));

  if (!result.ok && !result.skipped) {
    process.exit(1);
  }
})().catch((error) => {
  console.error("❌ Erro no restore:", error.message);
  process.exit(1);
});
EOF

cat > scripts/persistencia-check.js <<'EOF'
const { statusPersistenciaCejas } = require("../lib/persistencia-total-supabase");

(async () => {
  const result = await statusPersistenciaCejas();
  console.log(JSON.stringify(result, null, 2));

  if (!result.ok) {
    process.exit(1);
  }
})().catch((error) => {
  console.error("❌ Erro no check:", error.message);
  process.exit(1);
});
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())

scripts = pkg.setdefault("scripts", {})

scripts["start"] = "node scripts/start-seguro-cejas.js"
scripts["dev"] = "node scripts/start-seguro-cejas.js"
scripts["dev:local"] = "node server.js"
scripts["persist:sync"] = "node scripts/persistencia-sync.js"
scripts["persist:restore"] = "node scripts/persistencia-restore.js"
scripts["persist:check"] = "node scripts/persistencia-check.js"

p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const persistenciaTotalCejas = require("./lib/persistencia-total-supabase");'

if require_line not in s:
    anchor = 'const path = require("path");'

    if anchor in s:
        s = s.replace(anchor, anchor + "\n" + require_line, 1)
    else:
        s = require_line + "\n" + s

middleware_marker = "// CEJAS_PERSISTENCIA_TOTAL_DEPLOY_START"

if middleware_marker not in s:
    app_marker = "const app = express();"

    bloco = r'''
// CEJAS_PERSISTENCIA_TOTAL_DEPLOY_START
const CEJAS_ROTAS_QUE_SALVAM_DADOS = [
  "/api/servidor",
  "/api/gratuidades",
  "/api/importar-relatorio",
  "/api/relatorio",
  "/api/agenda",
  "/api/tarefas",
  "/api/usuarios",
  "/api/configuracoes",
  "/api/chat",
  "/api/orcamentos",
  "/api/financeiro"
];

app.use((req, res, next) => {
  const metodoMudaDados = ["POST", "PUT", "PATCH", "DELETE"].includes(req.method);
  const rotaMudaDados = CEJAS_ROTAS_QUE_SALVAM_DADOS.some(prefix => req.path.startsWith(prefix));

  if (metodoMudaDados && rotaMudaDados) {
    res.on("finish", () => {
      if (res.statusCode < 400) {
        setTimeout(() => {
          persistenciaTotalCejas.syncTudoCejas("auto").catch((error) => {
            console.warn("⚠️ Sync automático pós-alteração falhou:", error.message);
          });
        }, 1200);
      }
    });
  }

  next();
});

app.get("/api/persistencia/status", async (_req, res) => {
  try {
    const status = await persistenciaTotalCejas.statusPersistenciaCejas();
    res.json(status);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});

app.post("/api/persistencia/sync", async (_req, res) => {
  try {
    const result = await persistenciaTotalCejas.syncTudoCejas("api");
    res.json(result);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});

app.post("/api/persistencia/restore", async (_req, res) => {
  try {
    const result = await persistenciaTotalCejas.restoreTudoCejas("api");
    res.json(result);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_PERSISTENCIA_TOTAL_DEPLOY_END

'''

    if app_marker not in s:
        raise SystemExit("❌ Não encontrei const app = express(); no server.js.")

    s = s.replace(app_marker, app_marker + "\n" + bloco, 1)

p.write_text(s)
PY

if [ -f ".env.example" ] && ! grep -q "SUPABASE_STORAGE_BUCKET" .env.example; then
  cat >> .env.example <<'EOF'

# Storage permanente do sistema CEJAS
SUPABASE_STORAGE_BUCKET=servidor-cejas
EOF
fi

cat > .gitignore <<'EOF'
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*

.env
.env.*
!.env.example
*.local

.DS_Store
Thumbs.db
.vscode/*
!.vscode/settings.json
*.swp
*.swo
*~

uploads/
backups-cejas/
.cejas-local-backups/
*.backup-*.html
*.backup-*.js
*.backup-*.json
.env.backup-*
diagnostico-*.zip

data/usuarios.json
data/redefinicoes-senha-local.json
data/chat-mensagens-local.json
data/relatorio-supera.json
data/relatorio-atual.json
data/ultimo-relatorio-texto-extraido.txt
data/agenda-manual-local.json
data/gratuidades-manuais.json
data/gratuidades-ocultas.json
data/historico-relatorios/
EOF

node --check lib/persistencia-total-supabase.js
node --check scripts/start-seguro-cejas.js
node --check scripts/persistencia-sync.js
node --check scripts/persistencia-restore.js
node --check scripts/persistencia-check.js
node --check server.js

echo ""
echo "✅ Blindagem total aplicada."
echo ""
echo "Agora rode nesta ordem:"
echo "npm run persist:sync"
echo "npm run persist:check"
echo "npm run dev"
echo ""
echo "No deploy, o Start Command precisa ser:"
echo "npm start"
