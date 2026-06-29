#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "lib/servidor-storage-persistente.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e lib/servidor-storage-persistente.js."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/apagar-definitivo-supabase-$STAMP"
mkdir -p "$BACKUP_DIR"
cp server.js lib/servidor-storage-persistente.js "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("lib/servidor-storage-persistente.js")
s = p.read_text()

if "async function deletarSupabaseServidor" not in s:
    insert_after = '''async function moverSupabaseServidor(origem, destino) {'''
    start = s.index(insert_after)
    next_fn = s.index('async function listarStorageServidor', start)

    delete_fns = r'''
async function deletarSupabaseServidor(paths) {
  if (!(await garantirBucketServidor())) {
    return { ok: false, skipped: true, message: "Supabase Storage não configurado." };
  }

  const lista = Array.isArray(paths) ? paths : [paths];
  const limpos = lista
    .map(limparStoragePathServidor)
    .filter(Boolean);

  if (!limpos.length) {
    return { ok: true, deleted: 0, paths: [] };
  }

  const chunks = [];

  for (let i = 0; i < limpos.length; i += 100) {
    chunks.push(limpos.slice(i, i + 100));
  }

  let deleted = 0;

  for (const chunk of chunks) {
    const { error } = await supabaseAdmin.storage.from(BUCKET).remove(chunk);

    if (error) {
      throw new Error("Erro ao apagar do Supabase Storage: " + error.message);
    }

    deleted += chunk.length;
  }

  return {
    ok: true,
    deleted,
    paths: limpos,
    bucket: BUCKET
  };
}

async function deletarPrefixoSupabaseServidor(prefix) {
  if (!(await garantirBucketServidor())) {
    return { ok: false, skipped: true, message: "Supabase Storage não configurado." };
  }

  const prefixLimpo = limparStoragePathServidor(prefix);
  const arquivos = await listarArquivosStorageServidor(prefixLimpo);

  if (!arquivos.length) {
    return { ok: true, deleted: 0, paths: [] };
  }

  return deletarSupabaseServidor(arquivos);
}

'''
    s = s[:next_fn] + delete_fns + s[next_fn:]

# Exporta funções novas.
if "deletarSupabaseServidor," not in s:
    s = s.replace(
        "moverSupabaseServidor,",
        "moverSupabaseServidor,\n  deletarSupabaseServidor,\n  deletarPrefixoSupabaseServidor,",
        1
    )

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("server.js")
s = p.read_text()

# Ajusta require para incluir funções de apagar.
s = s.replace(
    "moverSupabaseServidor, listarStorageServidor",
    "moverSupabaseServidor, deletarSupabaseServidor, deletarPrefixoSupabaseServidor, listarStorageServidor"
)

s = s.replace(
    "moverSupabaseServidor, listarStorageServidor }",
    "moverSupabaseServidor, deletarSupabaseServidor, deletarPrefixoSupabaseServidor, listarStorageServidor }"
)

# Garante helpers para listar arquivos locais de uma pasta antes de apagar.
if "function listarArquivosParaDeleteServidorCejas" not in s:
    marker = 'app.delete("/api/servidor/item"'
    helper = r'''
function listarArquivosParaDeleteServidorCejas(absPath, relPath, resultado = []) {
  if (!fs.existsSync(absPath)) return resultado;

  const stat = fs.statSync(absPath);

  if (stat.isFile()) {
    resultado.push(String(relPath || "").replace(/\\/g, "/"));
    return resultado;
  }

  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(absPath, { withFileTypes: true })) {
      const childAbs = path.join(absPath, entry.name);
      const childRel = path.join(relPath, entry.name).replace(/\\/g, "/");
      listarArquivosParaDeleteServidorCejas(childAbs, childRel, resultado);
    }
  }

  return resultado;
}

'''
    if marker in s:
        s = s.replace(marker, helper + marker, 1)

# Troca rota DELETE por exclusão definitiva local + Supabase.
pattern = r'app\.delete\("/api/servidor/item",[\s\S]*?\n\}\);'

new_route = r'''app.delete("/api/servidor/item", async (req, res) => {
  try {
    const relativePath = String(req.query.path || "").trim();

    if (!relativePath) {
      return res.status(400).json({
        ok: false,
        message: "Informe o caminho do item."
      });
    }

    const itemPath = safeServidorPath(relativePath);
    const apagadosStorage = [];
    let apagouLocal = false;

    if (fs.existsSync(itemPath)) {
      const stat = fs.statSync(itemPath);

      if (stat.isDirectory()) {
        const arquivosLocais = listarArquivosParaDeleteServidorCejas(itemPath, relativePath);
        apagadosStorage.push(...arquivosLocais);
        fs.rmSync(itemPath, { recursive: true, force: true });
        apagouLocal = true;
      } else if (stat.isFile()) {
        apagadosStorage.push(relativePath.replace(/\\/g, "/"));
        fs.rmSync(itemPath, { force: true });
        apagouLocal = true;
      }
    }

    let storageResult = { ok: true, deleted: 0, paths: [] };

    if (apagadosStorage.length) {
      storageResult = await deletarSupabaseServidor(apagadosStorage);
    } else {
      storageResult = await deletarPrefixoSupabaseServidor(relativePath);
    }

    res.json({
      ok: true,
      apagouLocal,
      apagadosStorage: storageResult.deleted || 0,
      message: `Item apagado definitivamente. Local: ${apagouLocal ? "sim" : "não encontrado"} | Supabase: ${storageResult.deleted || 0} arquivo(s).`
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao apagar definitivamente: " + error.message
    });
  }
});'''

if re.search(pattern, s):
    s = re.sub(pattern, new_route, s, count=1)
else:
    raise SystemExit("❌ Não encontrei a rota DELETE /api/servidor/item no server.js.")

p.write_text(s)
PY

node --check lib/servidor-storage-persistente.js
node --check server.js

echo ""
echo "✅ Botão APAGAR ajustado para exclusão definitiva local + Supabase Storage."
echo ""
echo "Agora rode:"
echo "npm run servidor:check-storage"
echo "npm run dev"
