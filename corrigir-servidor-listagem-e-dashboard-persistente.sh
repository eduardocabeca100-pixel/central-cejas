#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "dashboard.html" ] || [ ! -f "lib/servidor-supabase-definitivo.js" ]; then
  echo "❌ Rode dentro da raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/fix-listagem-dashboard-persistente-$STAMP"
mkdir -p "$BACKUP_DIR" lib scripts

cp server.js dashboard.html package.json "$BACKUP_DIR/" 2>/dev/null || true
cp lib/servidor-supabase-definitivo.js "$BACKUP_DIR/" 2>/dev/null || true
[ -f scripts/start-seguro-cejas.js ] && cp scripts/start-seguro-cejas.js "$BACKUP_DIR/start-seguro-cejas.js" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

p = Path("lib/servidor-supabase-definitivo.js")
s = p.read_text()

def replace_async_function(source, name, replacement):
    marker = f"async function {name}("
    start = source.find(marker)
    if start == -1:
        return source, False

    brace = source.find("{", start)
    if brace == -1:
        return source, False

    depth = 0
    i = brace

    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[:start] + replacement + source[i + 1:], True
        i += 1

    return source, False

new_listar_objetos = r'''async function listarObjetosPlanos() {
  const env = assertStorageEnv();
  const todos = [];
  const visitados = new Set();

  async function listarPrefixo(prefix = "") {
    const folder = limparPath(prefix);

    if (visitados.has(folder)) return;
    visitados.add(folder);

    let offset = 0;
    const limit = 1000;

    while (true) {
      const batch = await storageRequest(`/object/list/${encodeURIComponent(env.bucket)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prefix: folder,
          limit,
          offset,
          sortBy: {
            column: "name",
            order: "asc"
          }
        })
      });

      const items = Array.isArray(batch) ? batch : [];

      for (const item of items) {
        if (!item || !item.name || item.name === ".emptyFolderPlaceholder") continue;

        const rel = folder ? `${folder}/${item.name}` : item.name;
        const isFile = item.metadata && typeof item.metadata.size === "number";

        if (isFile) {
          todos.push({
            type: "file",
            name: item.name,
            path: rel,
            size: Number(item.metadata.size || 0),
            updatedAt: item.updated_at || item.created_at || new Date().toISOString()
          });
        } else {
          await listarPrefixo(rel);
        }
      }

      if (items.length < limit) break;
      offset += limit;
    }
  }

  await listarPrefixo("");

  return todos.sort((a, b) => a.path.localeCompare(b.path, "pt-BR"));
}'''

s, ok = replace_async_function(s, "listarObjetosPlanos", new_listar_objetos)

if not ok:
    raise SystemExit("❌ Não consegui trocar listarObjetosPlanos.")

p.write_text(s)
PY

cat > lib/dados-supabase-cejas.js <<'EOF'
require("dotenv").config();

const fs = require("fs");
const path = require("path");

const DATA_ROOT = path.join(process.cwd(), "data");
const PREFIX = "_SISTEMA/data";

function cleanEnv(value) {
  return String(value || "").trim().replace(/^["']|["']$/g, "");
}

function getRuntimeEnv() {
  const url =
    cleanEnv(process.env.SUPABASE_URL) ||
    cleanEnv(process.env.NEXT_PUBLIC_SUPABASE_URL) ||
    cleanEnv(process.env.PUBLIC_SUPABASE_URL);

  const serviceRole =
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.CEJAS_SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE) ||
    cleanEnv(process.env.SUPABASE_SECRET_KEY);

  const bucket =
    cleanEnv(process.env.SUPABASE_STORAGE_BUCKET) ||
    cleanEnv(process.env.SUPABASE_BUCKET) ||
    "servidor-cejas";

  return { url, serviceRole, bucket };
}

function statusDadosSupabase() {
  const env = getRuntimeEnv();

  return {
    ok: Boolean(env.url && env.serviceRole && env.bucket),
    bucket: env.bucket,
    prefix: PREFIX,
    resolvedUrl: Boolean(env.url),
    resolvedServiceRole: Boolean(env.serviceRole),
    resolvedBucket: Boolean(env.bucket)
  };
}

function assertEnv() {
  const status = statusDadosSupabase();

  if (!status.ok) {
    throw new Error("Supabase não configurado para persistência de data/: " + JSON.stringify(status));
  }

  return getRuntimeEnv();
}

function headers(extra = {}) {
  const env = assertEnv();

  return {
    apikey: env.serviceRole,
    Authorization: `Bearer ${env.serviceRole}`,
    ...extra
  };
}

function limparPath(value = "") {
  return String(value || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => part && part !== "." && part !== "..")
    .join("/");
}

function encodeStoragePath(value = "") {
  return limparPath(value).split("/").map(encodeURIComponent).join("/");
}

async function storageRequest(route, options = {}) {
  const env = assertEnv();
  const url = `${env.url.replace(/\/$/, "")}/storage/v1${route}`;

  const response = await fetch(url, {
    ...options,
    headers: headers(options.headers || {})
  });

  const contentType = response.headers.get("content-type") || "";
  const isJson = contentType.includes("application/json");

  if (!response.ok) {
    const body = isJson
      ? await response.json().catch(() => null)
      : await response.text().catch(() => "");

    const msg = body?.message || body?.error || body?.msg || body || `HTTP ${response.status}`;
    throw new Error(String(msg));
  }

  if (options.raw) {
    const arrayBuffer = await response.arrayBuffer();
    return Buffer.from(arrayBuffer);
  }

  if (response.status === 204) return null;
  return isJson ? response.json() : response.text();
}

function listarArquivosLocais(dir = DATA_ROOT, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".DS_Store") continue;

    const full = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      listarArquivosLocais(full, result);
    } else if (entry.isFile()) {
      const rel = path.relative(DATA_ROOT, full).replace(/\\/g, "/");

      if (
        rel.endsWith(".json") ||
        rel.endsWith(".txt") ||
        rel.endsWith(".csv")
      ) {
        result.push({ full, rel });
      }
    }
  }

  return result;
}

async function listarStorageData() {
  const env = assertEnv();
  const todos = [];
  const visitados = new Set();

  async function listarPrefixo(prefix) {
    const folder = limparPath(prefix);

    if (visitados.has(folder)) return;
    visitados.add(folder);

    let offset = 0;
    const limit = 1000;

    while (true) {
      const batch = await storageRequest(`/object/list/${encodeURIComponent(env.bucket)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prefix: folder,
          limit,
          offset,
          sortBy: {
            column: "name",
            order: "asc"
          }
        })
      });

      const items = Array.isArray(batch) ? batch : [];

      for (const item of items) {
        if (!item || !item.name || item.name === ".emptyFolderPlaceholder") continue;

        const rel = folder ? `${folder}/${item.name}` : item.name;
        const isFile = item.metadata && typeof item.metadata.size === "number";

        if (isFile) {
          todos.push(rel);
        } else {
          await listarPrefixo(rel);
        }
      }

      if (items.length < limit) break;
      offset += limit;
    }
  }

  await listarPrefixo(PREFIX);
  return todos;
}

async function uploadArquivoData(localFile, rel) {
  const env = assertEnv();
  const storagePath = limparPath(`${PREFIX}/${rel}`);
  const buffer = fs.readFileSync(localFile);

  await storageRequest(`/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(storagePath)}`, {
    method: "POST",
    headers: {
      "Content-Type": rel.endsWith(".json") ? "application/json" : "text/plain; charset=utf-8",
      "Cache-Control": "3600",
      "x-upsert": "true"
    },
    body: buffer
  });

  return storagePath;
}

async function baixarArquivoData(storagePath) {
  const env = assertEnv();

  return storageRequest(`/object/${encodeURIComponent(env.bucket)}/${encodeStoragePath(storagePath)}`, {
    method: "GET",
    raw: true
  });
}

async function syncDataParaSupabase() {
  fs.mkdirSync(DATA_ROOT, { recursive: true });

  const arquivos = listarArquivosLocais();
  const enviados = [];

  for (const item of arquivos) {
    try {
      const pathStorage = await uploadArquivoData(item.full, item.rel);
      enviados.push(pathStorage);
    } catch (error) {
      console.warn("⚠️ Falha ao sincronizar data/" + item.rel + ":", error.message);
    }
  }

  return {
    ok: true,
    enviados: enviados.length,
    arquivos: enviados
  };
}

async function restoreDataDoSupabase() {
  fs.mkdirSync(DATA_ROOT, { recursive: true });

  const arquivos = await listarStorageData();
  let restaurados = 0;

  for (const storagePath of arquivos) {
    try {
      const rel = storagePath.replace(`${PREFIX}/`, "");
      const destino = path.join(DATA_ROOT, rel);
      const buffer = await baixarArquivoData(storagePath);

      fs.mkdirSync(path.dirname(destino), { recursive: true });
      fs.writeFileSync(destino, buffer);
      restaurados += 1;
    } catch (error) {
      console.warn("⚠️ Falha ao restaurar " + storagePath + ":", error.message);
    }
  }

  return {
    ok: true,
    restaurados,
    totalStorage: arquivos.length
  };
}

module.exports = {
  statusDadosSupabase,
  syncDataParaSupabase,
  restoreDataDoSupabase
};
EOF

cat > scripts/data-sync-cejas.js <<'EOF'
const { syncDataParaSupabase, statusDadosSupabase } = require("../lib/dados-supabase-cejas");

(async () => {
  console.log("Status:", statusDadosSupabase());
  const result = await syncDataParaSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro ao sincronizar data/:", error.message);
  process.exit(1);
});
EOF

cat > scripts/data-restore-cejas.js <<'EOF'
const { restoreDataDoSupabase, statusDadosSupabase } = require("../lib/dados-supabase-cejas");

(async () => {
  console.log("Status:", statusDadosSupabase());
  const result = await restoreDataDoSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro ao restaurar data/:", error.message);
  process.exit(1);
});
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())
scripts = pkg.setdefault("scripts", {})

scripts["data:sync"] = "node scripts/data-sync-cejas.js"
scripts["data:restore"] = "node scripts/data-restore-cejas.js"

p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

cat > scripts/start-seguro-cejas.js <<'EOF'
require("dotenv").config();

(async () => {
  console.log("🛡️ Iniciando CEJAS em modo seguro...");
  console.log("📦 Servidor de arquivos: Supabase Storage direto.");

  try {
    const { restoreDataDoSupabase, statusDadosSupabase } = require("../lib/dados-supabase-cejas");

    console.log("📊 Status data/Supabase:", statusDadosSupabase());

    const restore = await restoreDataDoSupabase();
    console.log("✅ data/ restaurado do Supabase:", restore);
  } catch (error) {
    console.warn("⚠️ Restore de data/ ignorado:", error.message);
  }

  try {
    const { getSupabaseRuntimeStatus } = require("../lib/servidor-supabase-definitivo");
    console.log("📊 Status Storage runtime:", getSupabaseRuntimeStatus());
  } catch (error) {
    console.warn("⚠️ Check Storage runtime ignorado:", error.message);
  }

  console.log("🚀 Abrindo servidor...");
  require("../server.js");
})();
EOF

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const { syncDataParaSupabase } = require("./lib/dados-supabase-cejas");'
if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace('const path = require("path");', 'const path = require("path");\n' + require_line, 1)
    else:
        s = require_line + "\n" + s

middleware = r'''
// CEJAS_SYNC_DATA_SUPABASE_START
app.use((req, res, next) => {
  const mudaDados = ["POST", "PUT", "PATCH", "DELETE"].includes(req.method);
  const rotasData = [
    "/api/importar-relatorio",
    "/api/relatorio",
    "/api/dashboard",
    "/api/gratuidades",
    "/api/agenda",
    "/api/tarefas",
    "/api/configuracoes"
  ];

  if (mudaDados && rotasData.some(prefix => req.path.startsWith(prefix))) {
    res.on("finish", () => {
      if (res.statusCode < 400) {
        setTimeout(() => {
          syncDataParaSupabase().catch(error => {
            console.warn("⚠️ Sync data/ pós alteração falhou:", error.message);
          });
        }, 1200);
      }
    });
  }

  next();
});

app.post("/api/sistema/sync-data", async (_req, res) => {
  try {
    const result = await syncDataParaSupabase();
    res.json({ ok: true, ...result });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});
// CEJAS_SYNC_DATA_SUPABASE_END

'''

if "CEJAS_SYNC_DATA_SUPABASE_START" not in s:
    marker = "const app = express();"
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express(); no server.js.")
    s = s.replace(marker, marker + "\n" + middleware, 1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("dashboard.html")
s = p.read_text()

s = re.sub(
    r'\s*<script>\s*// CEJAS_RECEITA_MENSAL_VISIVEL_START[\s\S]*?// CEJAS_RECEITA_MENSAL_VISIVEL_END\s*</script>',
    '',
    s
)

js = r'''
<script>
// CEJAS_RECEITA_MENSAL_VISIVEL_START
(function () {
  if (window.__CEJAS_RECEITA_MENSAL_VISIVEL__) return;
  window.__CEJAS_RECEITA_MENSAL_VISIVEL__ = true;

  function dinheiroBR(valor) {
    return Number(valor || 0).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });
  }

  function acharBlocoReceita() {
    const blocos = [...document.querySelectorAll("section, article, div")]
      .filter(el => {
        const txt = String(el.textContent || "").toLowerCase();
        return txt.includes("receita mensal confirmada") || txt.includes("receita confirmada por mês");
      });

    return blocos[0] || null;
  }

  function lerReceitaTotalTela() {
    const texto = document.body.innerText || "";
    const match = texto.match(/RECEITA CONFIRMADA\s*R\$\s*([\d.]+,\d{2})/i);

    if (!match) return 0;

    return Number(match[1].replace(/\./g, "").replace(",", "."));
  }

  function renderMesesFallback() {
    const bloco = acharBlocoReceita();
    if (!bloco) return;

    if (document.getElementById("cejasReceitaMesesVisivel")) return;

    const total = lerReceitaTotalTela();

    const box = document.createElement("div");
    box.id = "cejasReceitaMesesVisivel";
    box.style.cssText = `
      margin-top:14px;
      padding:16px;
      border:1px solid rgba(34,197,94,.22);
      border-radius:16px;
      background:rgba(34,197,94,.08);
      color:white;
    `;

    box.innerHTML = `
      <div style="font-size:11px;text-transform:uppercase;letter-spacing:.16em;color:rgba(255,255,255,.65);font-weight:900;margin-bottom:6px;">
        Receita mensal restaurada
      </div>
      <div style="font-size:24px;font-weight:950;color:#22c55e;margin-bottom:8px;">
        ${dinheiroBR(total)}
      </div>
      <div style="font-size:12px;color:rgba(255,255,255,.70);line-height:1.35;">
        O painel mensal foi recolocado. Se o detalhamento por mês não aparecer após trocar o PDF, clique em
        <strong>Atualizar dados</strong> ou importe o relatório novamente. A base agora será restaurada do Supabase após deploy.
      </div>
    `;

    bloco.appendChild(box);
  }

  document.addEventListener("DOMContentLoaded", () => {
    setTimeout(renderMesesFallback, 400);
    setTimeout(renderMesesFallback, 1400);
    setTimeout(renderMesesFallback, 3000);
  });
})();
// CEJAS_RECEITA_MENSAL_VISIVEL_END
</script>
'''

if "</body>" in s:
    s = s.replace("</body>", js + "\n</body>", 1)
else:
    s += js

p.write_text(s)
PY

echo ""
echo "🔎 Verificando sintaxe..."

node --check lib/servidor-supabase-definitivo.js
node --check lib/dados-supabase-cejas.js
node --check scripts/data-sync-cejas.js
node --check scripts/data-restore-cejas.js
node --check scripts/start-seguro-cejas.js
node --check server.js

node <<'NODE'
const fs = require("fs");
const html = fs.readFileSync("dashboard.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-dashboard-persistente", { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-dashboard-persistente/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-dashboard-persistente/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-dashboard-persistente

echo ""
echo "✅ Correções aplicadas."
echo ""
echo "Agora rode antes do deploy:"
echo "npm run data:sync"
echo "npm start"
