#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "lib/servidor-supabase-definitivo.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/servidor-stack-upload-lotes-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js lib/servidor-supabase-definitivo.js servidor.html package.json "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("lib/servidor-supabase-definitivo.js")
s = p.read_text()

# 1) Remove cache antigo bugado, se existir.
s = re.sub(
    r'\n// CEJAS_CACHE_TREE_SERVIDOR_START[\s\S]*?// CEJAS_CACHE_TREE_SERVIDOR_END\n',
    '\n',
    s
)

# 2) Garante cache seguro, que NÃO chama ele mesmo dentro da recursão.
insert_after = 'const uploadServidorSupabase = multer({'
cache_block = r'''
// CEJAS_CACHE_TREE_SERVIDOR_SEGURO_START
let CEJAS_TREE_CACHE = {
  at: 0,
  root: null
};

function limparCacheServidorCejas() {
  CEJAS_TREE_CACHE = {
    at: 0,
    root: null
  };
}

async function listarStorageComCacheCejas() {
  const agora = Date.now();

  if (CEJAS_TREE_CACHE.root && agora - CEJAS_TREE_CACHE.at < 15000) {
    return CEJAS_TREE_CACHE.root;
  }

  const root = await listarStorage("");

  CEJAS_TREE_CACHE = {
    at: agora,
    root
  };

  return root;
}
// CEJAS_CACHE_TREE_SERVIDOR_SEGURO_END

'''

if "CEJAS_CACHE_TREE_SERVIDOR_SEGURO_START" not in s:
    if insert_after not in s:
        raise SystemExit("❌ Não encontrei ponto para inserir cache seguro.")
    s = s.replace(insert_after, cache_block + insert_after, 1)

# 3) Reescreve a função listarStorage para evitar recursão infinita.
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

new_listar = r'''async function listarStorage(prefix = "") {
  await garantirBucket();

  const env = getRuntimeEnv();
  const folder = limparPath(prefix);
  const result = [];
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
        sortBy: { column: "name", order: "asc" }
      })
    });

    const items = Array.isArray(batch) ? batch : [];

    for (const item of items) {
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
          children: await listarStorage(rel)
        });
      }
    }

    if (items.length < limit) break;
    offset += limit;
  }

  return result.sort((a, b) => {
    if (a.type !== b.type) return a.type === "folder" ? -1 : 1;
    return a.name.localeCompare(b.name, "pt-BR");
  });
}'''

s, ok = replace_async_function(s, "listarStorage", new_listar)

if not ok:
    raise SystemExit("❌ Não consegui substituir listarStorage.")

# 4) Garante que somente as rotas principais usam cache, e a função interna usa listarStorage normal.
s = s.replace("const root = await listarStorageComCacheCejas();", "const root = await listarStorage();")

s = s.replace(
'''  app.get("/api/servidor/tree", async (_req, res) => {
    try {
      const root = await listarStorage();
      res.json({ ok: true, origem: "supabase-storage-rest", bucket: getRuntimeEnv().bucket, root });''',
'''  app.get("/api/servidor/tree", async (_req, res) => {
    try {
      const root = await listarStorageComCacheCejas();
      res.json({ ok: true, origem: "supabase-storage-rest", bucket: getRuntimeEnv().bucket, root });'''
)

s = s.replace(
'''  app.get("/api/servidor/pastas", async (_req, res) => {
    try {
      const root = await listarStorage();
      res.json({ ok: true, pastas: listarPastas(root).filter(p => !p.startsWith("VERIFICAR/")) });''',
'''  app.get("/api/servidor/pastas", async (_req, res) => {
    try {
      const root = await listarStorageComCacheCejas();
      res.json({ ok: true, pastas: listarPastas(root).filter(p => !p.startsWith("VERIFICAR/")) });'''
)

s = s.replace(
'''  app.get("/api/servidor/verificar", async (_req, res) => {
    try {
      const root = await listarStorage();
      res.json({ ok: true, itens: listarVerificar(root) });''',
'''  app.get("/api/servidor/verificar", async (_req, res) => {
    try {
      const root = await listarStorageComCacheCejas();
      res.json({ ok: true, itens: listarVerificar(root) });'''
)

# 5) Limpa cache depois de salvar, mover e apagar.
s = s.replace(
'''      res.json({
        ok: true,
        saved: salvos.length,''',
'''      limparCacheServidorCejas();

      res.json({
        ok: true,
        saved: salvos.length,''',
1
)

s = s.replace(
'''      res.json({ ok: true, saved: salvos.length, exemplos: salvos.slice(0, 12), message: `${salvos.length} arquivo(s) salvos no Supabase Storage.` });''',
'''      limparCacheServidorCejas();
      res.json({ ok: true, saved: salvos.length, exemplos: salvos.slice(0, 12), message: `${salvos.length} arquivo(s) salvos no Supabase Storage.` });'''
)

s = s.replace(
'''      res.json({ ok: true, ...result, message: "Item movido no Supabase Storage." });''',
'''      limparCacheServidorCejas();
      res.json({ ok: true, ...result, message: "Item movido no Supabase Storage." });'''
)

s = s.replace(
'''      res.json({ ok: true, ...result, message: `Item apagado definitivamente do Supabase Storage. Arquivos removidos: ${result.deleted}.` });''',
'''      limparCacheServidorCejas();
      res.json({ ok: true, ...result, message: `Item apagado definitivamente do Supabase Storage. Arquivos removidos: ${result.deleted}.` });'''
)

p.write_text(s)
PY

# 6) Ajuste no front: enviar muitos arquivos em lotes menores.
if [ -f "servidor.html" ]; then
python3 <<'PY'
from pathlib import Path
import re

p = Path("servidor.html")
s = p.read_text()

# Remove patch antigo, se existir.
s = re.sub(
    r'\s*<script>\s*// CEJAS_UPLOAD_LOTES_SERVIDOR_START[\s\S]*?// CEJAS_UPLOAD_LOTES_SERVIDOR_END\s*</script>',
    '',
    s
)

js = r'''
<script>
// CEJAS_UPLOAD_LOTES_SERVIDOR_START
(function () {
  if (window.__CEJAS_UPLOAD_LOTES_SERVIDOR__) return;
  window.__CEJAS_UPLOAD_LOTES_SERVIDOR__ = true;

  const TAMANHO_LOTE = 20;

  function obterArquivosSelecionados() {
    const inputs = [...document.querySelectorAll('input[type="file"]')];
    const arquivos = [];

    for (const input of inputs) {
      for (const file of Array.from(input.files || [])) {
        arquivos.push(file);
      }
    }

    return arquivos;
  }

  function obterAnoPadrao() {
    const el = document.querySelector("#anoPadrao, [name='anoPadrao'], select[name='anoPadrao']");
    return el && el.value ? el.value : "2026";
  }

  function atualizarStatusUpload(texto) {
    const candidatos = [...document.querySelectorAll("div,p,span,strong")];

    const status = candidatos.find((el) => {
      const t = String(el.textContent || "").toLowerCase();
      return t.includes("enviando") || t.includes("organizando") || t.includes("arquivo");
    });

    if (status) {
      status.textContent = texto;
    }
  }

  async function enviarLoteServidor(files, inicio, total) {
    const form = new FormData();

    files.forEach((file) => {
      form.append("arquivos", file, file.webkitRelativePath || file.name);
      form.append("paths", file.webkitRelativePath || file.name);
    });

    form.append("anoPadrao", obterAnoPadrao());

    const response = await fetch("/api/servidor/upload-inteligente", {
      method: "POST",
      body: form
    });

    const data = await response.json().catch(() => null);

    if (!response.ok || !data) {
      throw new Error(`Erro HTTP ${response.status}`);
    }

    return data;
  }

  async function uploadEmLotesCejas(event) {
    const botao = event.target.closest("button, a");
    if (!botao) return;

    const texto = String(botao.textContent || "").toLowerCase();
    const ehEnviar = texto.includes("enviar para o servidor") || texto.includes("subir") || texto.includes("upload");

    if (!ehEnviar) return;

    const arquivos = obterArquivosSelecionados();

    if (arquivos.length <= TAMANHO_LOTE) return;

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    let salvos = 0;
    let falhas = [];

    botao.disabled = true;

    try {
      for (let i = 0; i < arquivos.length; i += TAMANHO_LOTE) {
        const lote = arquivos.slice(i, i + TAMANHO_LOTE);
        atualizarStatusUpload(`Enviando lote ${Math.floor(i / TAMANHO_LOTE) + 1} de ${Math.ceil(arquivos.length / TAMANHO_LOTE)}...`);

        const result = await enviarLoteServidor(lote, i, arquivos.length);

        salvos += Number(result.saved || 0);

        if (Array.isArray(result.falhas)) {
          falhas.push(...result.falhas);
        }
      }

      atualizarStatusUpload(`Upload finalizado: ${salvos} arquivo(s) enviados. ${falhas.length} falha(s).`);

      if (falhas.length) {
        console.warn("Falhas no upload CEJAS:", falhas);
        alert(`${salvos} arquivo(s) enviados. ${falhas.length} falha(s). Veja o console para detalhes.`);
      } else {
        alert(`${salvos} arquivo(s) enviados com sucesso.`);
      }

      if (typeof window.carregarServidor === "function") {
        window.carregarServidor();
      } else {
        location.reload();
      }
    } catch (error) {
      alert("Erro no upload em lotes: " + error.message);
    } finally {
      botao.disabled = false;
    }
  }

  document.addEventListener("click", uploadEmLotesCejas, true);
})();
// CEJAS_UPLOAD_LOTES_SERVIDOR_END
</script>
'''

if "</body>" in s:
    s = s.replace("</body>", js + "\n</body>", 1)
else:
    s += js

p.write_text(s)
PY
fi

echo ""
echo "🔎 Verificando sintaxe..."

node --check lib/servidor-supabase-definitivo.js
node --check server.js

if [ -f "servidor.html" ]; then
  node <<'NODE'
const fs = require("fs");
const html = fs.readFileSync("servidor.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-servidor-upload-lotes", { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-servidor-upload-lotes/script-${i + 1}.js`, code);
});
NODE

  for f in .cejas-local-backups/check-servidor-upload-lotes/*.js; do
    [ -f "$f" ] && node --check "$f"
  done

  rm -rf .cejas-local-backups/check-servidor-upload-lotes
fi

echo ""
echo "✅ Corrigido:"
echo "- Remove loop/Maximum call stack size exceeded."
echo "- Listagem do servidor usa cache seguro."
echo "- Upload grande é enviado em lotes de 20 arquivos."
echo "- Se alguns arquivos falharem, os outros continuam subindo."
echo ""
echo "Agora rode:"
echo "npm run dev"
