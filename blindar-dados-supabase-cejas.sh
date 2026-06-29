#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e package.json."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/blindagem-supabase-$STAMP"
mkdir -p "$BACKUP_DIR" lib scripts
cp server.js package.json .env.example .gitignore "$BACKUP_DIR/" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true

echo "✅ Backup do código criado em: $BACKUP_DIR"

cat > lib/servidor-storage-persistente.js <<'EOF'
const fs = require("fs");
const path = require("path");
const {
  supabaseAdmin,
  isSupabaseConfigured,
  SUPABASE_BUCKET
} = require("./supabase");

const BUCKET = process.env.SUPABASE_STORAGE_BUCKET || SUPABASE_BUCKET || "servidor-cejas";
let bucketReady = false;
let syncRunning = false;
let lastSyncStartedAt = 0;

function storageAtivoServidor() {
  return Boolean(isSupabaseConfigured && isSupabaseConfigured() && supabaseAdmin && BUCKET);
}

function limparStoragePathServidor(relativePath = "") {
  return String(relativePath || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => part && part !== "." && part !== "..")
    .join("/");
}

function contentTypeServidor(filePath = "") {
  const ext = path.extname(String(filePath)).toLowerCase();
  const map = {
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".txt": "text/plain; charset=utf-8",
    ".json": "application/json",
    ".csv": "text/csv",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  };

  return map[ext] || "application/octet-stream";
}

async function garantirBucketServidor() {
  if (!storageAtivoServidor()) return false;
  if (bucketReady) return true;

  const { data: buckets, error: listError } = await supabaseAdmin.storage.listBuckets();
  if (listError) throw new Error("Erro ao listar buckets do Supabase: " + listError.message);

  const existe = (buckets || []).some(bucket => bucket.name === BUCKET);

  if (!existe) {
    const { error: createError } = await supabaseAdmin.storage.createBucket(BUCKET, {
      public: false,
      fileSizeLimit: null
    });

    if (createError && !String(createError.message || "").toLowerCase().includes("already")) {
      throw new Error("Erro ao criar bucket " + BUCKET + ": " + createError.message);
    }
  }

  bucketReady = true;
  return true;
}

async function uploadBufferSupabaseServidor(relativePath, buffer, contentType) {
  if (!(await garantirBucketServidor())) {
    return { ok: false, skipped: true, message: "Supabase Storage não configurado." };
  }

  const storagePath = limparStoragePathServidor(relativePath);
  if (!storagePath) throw new Error("Caminho inválido para Storage.");

  const { error } = await supabaseAdmin.storage
    .from(BUCKET)
    .upload(storagePath, buffer, {
      contentType: contentType || contentTypeServidor(storagePath),
      upsert: true,
      cacheControl: "3600"
    });

  if (error) throw new Error("Erro ao enviar para Supabase Storage: " + error.message);

  return { ok: true, path: storagePath, bucket: BUCKET };
}

async function uploadLocalFileSupabaseServidor(localPath, relativePath) {
  if (!fs.existsSync(localPath) || !fs.statSync(localPath).isFile()) {
    return { ok: false, skipped: true, message: "Arquivo local não encontrado." };
  }

  const buffer = fs.readFileSync(localPath);
  return uploadBufferSupabaseServidor(relativePath, buffer, contentTypeServidor(relativePath));
}

async function downloadBufferSupabaseServidor(relativePath) {
  if (!(await garantirBucketServidor())) return null;

  const storagePath = limparStoragePathServidor(relativePath);
  const { data, error } = await supabaseAdmin.storage.from(BUCKET).download(storagePath);

  if (error) return null;
  if (!data) return null;

  const arrayBuffer = await data.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

async function moverSupabaseServidor(origem, destino) {
  if (!(await garantirBucketServidor())) return { ok: false, skipped: true };

  const origemPath = limparStoragePathServidor(origem);
  const destinoPath = limparStoragePathServidor(destino);

  if (!origemPath || !destinoPath) return { ok: false, skipped: true };

  const { error } = await supabaseAdmin.storage.from(BUCKET).move(origemPath, destinoPath);

  if (error) {
    const msg = String(error.message || "").toLowerCase();
    if (msg.includes("not found") || msg.includes("does not exist") || msg.includes("object not found")) {
      return { ok: false, skipped: true, message: "Origem não existia no Storage." };
    }

    throw new Error("Erro ao mover no Supabase Storage: " + error.message);
  }

  return { ok: true, origem: origemPath, destino: destinoPath };
}

async function listarStorageServidor(prefix = "") {
  if (!(await garantirBucketServidor())) return [];

  const folder = limparStoragePathServidor(prefix);
  let offset = 0;
  const limit = 1000;
  const all = [];

  while (true) {
    const { data, error } = await supabaseAdmin.storage.from(BUCKET).list(folder, {
      limit,
      offset,
      sortBy: { column: "name", order: "asc" }
    });

    if (error) throw new Error("Erro ao listar Storage: " + error.message);

    const batch = data || [];
    all.push(...batch);

    if (batch.length < limit) break;
    offset += limit;
  }

  const result = [];

  for (const item of all) {
    if (!item || !item.name || item.name === ".emptyFolderPlaceholder") continue;

    const rel = folder ? `${folder}/${item.name}` : item.name;
    const isFile = item.metadata && typeof item.metadata.size === "number";

    if (isFile) {
      result.push({
        type: "file",
        name: item.name,
        path: rel,
        size: Number(item.metadata.size || 0),
        updatedAt: item.updated_at || item.created_at || new Date().toISOString()
      });
    } else {
      result.push({
        type: "folder",
        name: item.name,
        path: rel,
        size: 0,
        updatedAt: item.updated_at || item.created_at || new Date().toISOString(),
        children: await listarStorageServidor(rel)
      });
    }
  }

  return result.sort((a, b) => {
    if (a.type !== b.type) return a.type === "folder" ? -1 : 1;
    return a.name.localeCompare(b.name, "pt-BR");
  });
}

async function listarArquivosStorageServidor(prefix = "") {
  const tree = await listarStorageServidor(prefix);
  const arquivos = [];

  function walk(items) {
    for (const item of items || []) {
      if (item.type === "file") arquivos.push(item.path);
      if (item.children) walk(item.children);
    }
  }

  walk(tree);
  return arquivos;
}

function listarArquivosLocaisServidor(rootDir, dir = rootDir, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;

    const full = path.join(dir, entry.name);
    const rel = path.relative(rootDir, full).replace(/\\/g, "/");

    if (entry.isDirectory()) {
      listarArquivosLocaisServidor(rootDir, full, result);
    } else if (entry.isFile()) {
      result.push({ full, rel, mtimeMs: fs.statSync(full).mtimeMs });
    }
  }

  return result;
}

async function enviarDiretorioParaSupabaseServidor(rootDir) {
  if (!(await garantirBucketServidor())) return { ok: false, skipped: true };

  const arquivos = listarArquivosLocaisServidor(rootDir);
  let enviados = 0;

  for (const arquivo of arquivos) {
    await uploadLocalFileSupabaseServidor(arquivo.full, arquivo.rel);
    enviados += 1;
  }

  return { ok: true, enviados, bucket: BUCKET };
}

async function restaurarSupabaseParaDiretorioServidor(rootDir) {
  if (!(await garantirBucketServidor())) return { ok: false, skipped: true };

  fs.mkdirSync(rootDir, { recursive: true });

  const arquivos = await listarArquivosStorageServidor();
  let restaurados = 0;

  for (const rel of arquivos) {
    const localPath = path.join(rootDir, limparStoragePathServidor(rel));

    if (fs.existsSync(localPath)) continue;

    const buffer = await downloadBufferSupabaseServidor(rel);
    if (!buffer) continue;

    fs.mkdirSync(path.dirname(localPath), { recursive: true });
    fs.writeFileSync(localPath, buffer);
    restaurados += 1;
  }

  return { ok: true, restaurados, totalStorage: arquivos.length, bucket: BUCKET };
}

async function iniciarProtecaoServidorSupabase(rootDir) {
  if (!storageAtivoServidor()) {
    console.warn("⚠️ Supabase Storage do servidor não está ativo. Verifique SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e SUPABASE_STORAGE_BUCKET.");
    return;
  }

  const executarSync = async (motivo = "auto") => {
    if (syncRunning) return;

    const now = Date.now();
    if (motivo === "auto" && now - lastSyncStartedAt < 20000) return;

    syncRunning = true;
    lastSyncStartedAt = now;

    try {
      await garantirBucketServidor();
      const restore = await restaurarSupabaseParaDiretorioServidor(rootDir);
      const upload = await enviarDiretorioParaSupabaseServidor(rootDir);
      console.log(`✅ Proteção Supabase Storage ativa (${motivo}): restaurados=${restore.restaurados || 0}, enviados=${upload.enviados || 0}, bucket=${BUCKET}`);
    } catch (error) {
      console.warn("⚠️ Falha na proteção Supabase Storage:", error.message);
    } finally {
      syncRunning = false;
    }
  };

  setTimeout(() => executarSync("inicial"), 1800);
  setInterval(() => executarSync("auto"), 60000).unref?.();
}

module.exports = {
  BUCKET,
  storageAtivoServidor,
  garantirBucketServidor,
  uploadBufferSupabaseServidor,
  uploadLocalFileSupabaseServidor,
  downloadBufferSupabaseServidor,
  moverSupabaseServidor,
  listarStorageServidor,
  listarArquivosStorageServidor,
  enviarDiretorioParaSupabaseServidor,
  restaurarSupabaseParaDiretorioServidor,
  iniciarProtecaoServidorSupabase,
  limparStoragePathServidor
};
EOF

cat > scripts/sync-servidor-supabase.js <<'EOF'
const path = require("path");
const {
  BUCKET,
  enviarDiretorioParaSupabaseServidor
} = require("../lib/servidor-storage-persistente");

(async () => {
  const root = path.join(process.cwd(), "uploads", "servidor");
  const result = await enviarDiretorioParaSupabaseServidor(root);
  console.log("✅ Sync local → Supabase concluído:", result);
  console.log("Bucket:", BUCKET);
})().catch((error) => {
  console.error("❌ Erro no sync local → Supabase:", error.message);
  process.exit(1);
});
EOF

cat > scripts/restaurar-servidor-supabase.js <<'EOF'
const path = require("path");
const {
  BUCKET,
  restaurarSupabaseParaDiretorioServidor
} = require("../lib/servidor-storage-persistente");

(async () => {
  const root = path.join(process.cwd(), "uploads", "servidor");
  const result = await restaurarSupabaseParaDiretorioServidor(root);
  console.log("✅ Restore Supabase → local concluído:", result);
  console.log("Bucket:", BUCKET);
})().catch((error) => {
  console.error("❌ Erro no restore Supabase → local:", error.message);
  process.exit(1);
});
EOF

cat > scripts/check-servidor-storage.js <<'EOF'
const {
  BUCKET,
  garantirBucketServidor,
  listarArquivosStorageServidor
} = require("../lib/servidor-storage-persistente");

(async () => {
  await garantirBucketServidor();
  const arquivos = await listarArquivosStorageServidor();
  console.log("✅ Supabase Storage conectado.");
  console.log("Bucket:", BUCKET);
  console.log("Arquivos no Storage:", arquivos.length);
  arquivos.slice(0, 30).forEach((item) => console.log("-", item));
})().catch((error) => {
  console.error("❌ Falha no Supabase Storage:", error.message);
  process.exit(1);
});
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["servidor:sync-supabase"] = "node scripts/sync-servidor-supabase.js"
scripts["servidor:restore-supabase"] = "node scripts/restaurar-servidor-supabase.js"
scripts["servidor:check-storage"] = "node scripts/check-servidor-storage.js"
p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("server.js")
s = p.read_text()

req = 'const { iniciarProtecaoServidorSupabase, uploadBufferSupabaseServidor, uploadLocalFileSupabaseServidor, downloadBufferSupabaseServidor, moverSupabaseServidor, listarStorageServidor } = require("./lib/servidor-storage-persistente");'
if req not in s:
    anchor = 'const { syncRelatorioAtualComSupabase } = require("./lib/sync-relatorio-supabase");'
    if anchor in s:
        s = s.replace(anchor, anchor + "\n" + req, 1)
    else:
        s = s.replace('const path = require("path");', 'const path = require("path");\n' + req, 1)

if "iniciarProtecaoServidorSupabase(SERVIDOR_DIR);" not in s:
    s = s.replace(
        'fs.mkdirSync(SERVIDOR_DIR, { recursive: true });',
        'fs.mkdirSync(SERVIDOR_DIR, { recursive: true });\niniciarProtecaoServidorSupabase(SERVIDOR_DIR);',
        1
    )

if "CEJAS_SYNC_SERVIDOR_STORAGE_AFTER_MUTATION" not in s:
    marker = 'iniciarProtecaoServidorSupabase(SERVIDOR_DIR);'
    middleware = r'''
// CEJAS_SYNC_SERVIDOR_STORAGE_AFTER_MUTATION
app.use((req, res, next) => {
  if (req.path.startsWith("/api/servidor") && ["POST", "DELETE", "PUT", "PATCH"].includes(req.method)) {
    res.on("finish", () => {
      if (res.statusCode < 400) {
        setTimeout(() => {
          try {
            const { enviarDiretorioParaSupabaseServidor } = require("./lib/servidor-storage-persistente");
            enviarDiretorioParaSupabaseServidor(SERVIDOR_DIR).catch((error) => {
              console.warn("⚠️ Sync pós-alteração do servidor falhou:", error.message);
            });
          } catch (error) {
            console.warn("⚠️ Sync pós-alteração do servidor não iniciou:", error.message);
          }
        }, 800);
      }
    });
  }

  next();
});
'''
    s = s.replace(marker, marker + "\n" + middleware, 1)

pattern_tree = r'app\.get\("/api/servidor/tree",[\s\S]*?\n\}\);'
new_tree = r'''app.get("/api/servidor/tree", async (_req, res) => {
  try {
    const cloudTree = await listarStorageServidor();

    if (Array.isArray(cloudTree) && cloudTree.length) {
      return res.json({
        ok: true,
        origem: "supabase-storage",
        root: cloudTree
      });
    }

    fs.mkdirSync(SERVIDOR_DIR, { recursive: true });

    res.json({
      ok: true,
      origem: "local-fallback",
      root: buildServidorTree(SERVIDOR_DIR)
    });
  } catch (error) {
    try {
      return res.json({
        ok: true,
        origem: "local-fallback-erro-storage",
        aviso: error.message,
        root: buildServidorTree(SERVIDOR_DIR)
      });
    } catch (localError) {
      res.status(500).json({
        ok: false,
        message: "Erro ao carregar servidor: " + localError.message
      });
    }
  }
});'''
if re.search(pattern_tree, s):
    s = re.sub(pattern_tree, lambda _m: new_tree, s, count=1)

pattern_arquivo = r'app\.get\("/api/servidor/arquivo",[\s\S]*?\n\}\);'
new_arquivo = r'''app.get("/api/servidor/arquivo", async (req, res) => {
  try {
    const relativePath = req.query.path || "";
    const filePath = safeServidorPath(relativePath);

    if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
      return res.sendFile(filePath);
    }

    const buffer = await downloadBufferSupabaseServidor(relativePath);

    if (!buffer) {
      return res.status(404).send("Arquivo não encontrado.");
    }

    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, buffer);

    res.sendFile(filePath);
  } catch (error) {
    res.status(500).send("Erro ao abrir arquivo: " + error.message);
  }
});'''
if re.search(pattern_arquivo, s):
    s = re.sub(pattern_arquivo, lambda _m: new_arquivo, s, count=1)

pattern_delete = r'app\.delete\("/api/servidor/item",[\s\S]*?\n\}\);'
new_delete = r'''app.delete("/api/servidor/item", async (req, res) => {
  try {
    const relativePath = String(req.query.path || "").trim();
    const itemPath = safeServidorPath(relativePath);

    if (relativePath.startsWith("_LIXEIRA/")) {
      return res.status(400).json({
        ok: false,
        message: "Exclusão definitiva bloqueada. Este item já está na lixeira de segurança."
      });
    }

    const hoje = new Date().toISOString().slice(0, 10);
    const destinoRelativo = path.join("_LIXEIRA", hoje, relativePath).replace(/\\/g, "/");
    const destinoPath = safeServidorPath(destinoRelativo);

    if (fs.existsSync(itemPath)) {
      fs.mkdirSync(path.dirname(destinoPath), { recursive: true });
      fs.renameSync(itemPath, destinoPath);
    }

    await moverSupabaseServidor(relativePath, destinoRelativo);

    res.json({
      ok: true,
      destino: destinoRelativo,
      message: "Item movido para _LIXEIRA. Nada foi apagado definitivamente."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao mover item para lixeira: " + error.message
    });
  }
});'''
if re.search(pattern_delete, s):
    s = re.sub(pattern_delete, lambda _m: new_delete, s, count=1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path("lib/sync-relatorio-supabase.js")
if p.exists():
    s = p.read_text()

    if "CEJAS_RELATORIO_NAO_APAGAR_HISTORICO" not in s:
        s = s.replace(
            "  // Para economizar banco: antes de salvar o novo relatório,\n  // apaga o relatório anterior e todos os eventos antigos.\n  await apagarRelatoriosSupabase();",
            "  // CEJAS_RELATORIO_NAO_APAGAR_HISTORICO\n  // Não apagar histórico: apenas marca relatórios anteriores como inativos.\n  await supabaseAdmin\n    .from(\"cejas_relatorios\")\n    .update({ ativo: false })\n    .eq(\"ativo\", true);",
            1
        )

    p.write_text(s)
PY

if [ -f ".env.example" ] && ! grep -q "SUPABASE_STORAGE_BUCKET" .env.example; then
  cat >> .env.example <<'EOF'

# Storage permanente dos arquivos do servidor
SUPABASE_STORAGE_BUCKET=servidor-cejas
EOF
fi

node --check lib/servidor-storage-persistente.js
node --check scripts/sync-servidor-supabase.js
node --check scripts/restaurar-servidor-supabase.js
node --check scripts/check-servidor-storage.js
node --check server.js
[ -f lib/sync-relatorio-supabase.js ] && node --check lib/sync-relatorio-supabase.js || true

echo ""
echo "✅ Blindagem aplicada."
echo ""
echo "Agora rode, nesta ordem:"
echo "npm run servidor:sync-supabase"
echo "npm run servidor:check-storage"
echo "npm run dev"
echo ""
echo "Antes de qualquer deploy, rode sempre: npm run servidor:sync-supabase"
