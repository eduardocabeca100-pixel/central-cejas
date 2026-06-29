#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e package.json."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/protecao-dados-$STAMP"
mkdir -p "$BACKUP_DIR"
cp server.js package.json .gitignore "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup do código criado em: $BACKUP_DIR"

mkdir -p scripts backups-cejas

cat > scripts/backup-dados-cejas.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="backups-cejas/dados-cejas-$STAMP.tar.gz"

mkdir -p backups-cejas

echo "📦 Criando backup de segurança..."

tar \
  --exclude='uploads/tmp-servidor' \
  --exclude='uploads/servidor/tmp-servidor' \
  --exclude='.cejas-local-backups' \
  --exclude='node_modules' \
  -czf "$DEST" \
  uploads data 2>/dev/null || true

echo "✅ Backup criado:"
echo "$DEST"
EOF

chmod +x scripts/backup-dados-cejas.sh

cat > scripts/auditoria-dados-cejas.js <<'EOF'
const fs = require("fs");
const path = require("path");

const root = process.cwd();

function walk(dir, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);

    if (entry.name === "tmp-servidor") continue;

    if (entry.isDirectory()) {
      walk(full, result);
    } else if (entry.isFile()) {
      const stat = fs.statSync(full);
      result.push({
        path: path.relative(root, full).replace(/\\/g, "/"),
        size: stat.size,
        updatedAt: stat.mtime.toISOString()
      });
    }
  }

  return result;
}

const arquivosServidor = walk(path.join(root, "uploads", "servidor"));
const arquivosData = walk(path.join(root, "data"));
const lixeira = arquivosServidor.filter(item => item.path.includes("_LIXEIRA"));

console.log("");
console.log("📊 Auditoria de dados CEJAS");
console.log("");
console.log(`Arquivos no servidor: ${arquivosServidor.length}`);
console.log(`Arquivos em data/: ${arquivosData.length}`);
console.log(`Arquivos na lixeira: ${lixeira.length}`);

const totalServidor = arquivosServidor.reduce((acc, item) => acc + item.size, 0);
console.log(`Tamanho servidor: ${(totalServidor / 1024 / 1024).toFixed(2)} MB`);

console.log("");
console.log("Últimos arquivos do servidor:");
arquivosServidor
  .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
  .slice(0, 20)
  .forEach(item => {
    console.log(`- ${item.path}`);
  });
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())

scripts = pkg.setdefault("scripts", {})
scripts["backup:dados"] = "bash scripts/backup-dados-cejas.sh"
scripts["audit:dados"] = "node scripts/auditoria-dados-cejas.js"

p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("server.js")
s = p.read_text()

if "CEJAS_PROTECAO_DADOS_START" not in s:
    insert_after = 'fs.mkdirSync(SERVIDOR_DIR, { recursive: true });'

    bloco = r'''
// CEJAS_PROTECAO_DADOS_START
function cejasTimestampSeguro() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function copiarDiretorioSeguroCejas(origem, destino) {
  if (!fs.existsSync(origem)) return false;

  fs.mkdirSync(destino, { recursive: true });

  for (const entry of fs.readdirSync(origem, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;

    const origemItem = path.join(origem, entry.name);
    const destinoItem = path.join(destino, entry.name);

    if (entry.isDirectory()) {
      copiarDiretorioSeguroCejas(origemItem, destinoItem);
    } else if (entry.isFile()) {
      fs.mkdirSync(path.dirname(destinoItem), { recursive: true });
      fs.copyFileSync(origemItem, destinoItem);
    }
  }

  return true;
}

function criarBackupServidorAntesMudancaCejas(motivo = "mudanca") {
  try {
    const backupBase = path.join(__dirname, ".cejas-local-backups");
    const destino = path.join(backupBase, `servidor-${motivo}-${cejasTimestampSeguro()}`);

    fs.mkdirSync(backupBase, { recursive: true });

    if (fs.existsSync(SERVIDOR_DIR)) {
      copiarDiretorioSeguroCejas(SERVIDOR_DIR, destino);
    }

    return destino;
  } catch (error) {
    console.warn("⚠️ Não foi possível criar backup do servidor:", error.message);
    return "";
  }
}

function moverParaLixeiraServidorCejas(itemPath, relativePath = "") {
  const lixeiraDir = path.join(SERVIDOR_DIR, "_LIXEIRA", cejasTimestampSeguro().slice(0, 10));
  const destinoBase = path.join(lixeiraDir, relativePath || path.basename(itemPath));
  let destino = destinoBase;

  fs.mkdirSync(path.dirname(destino), { recursive: true });

  if (fs.existsSync(destino)) {
    const ext = path.extname(destinoBase);
    const name = path.basename(destinoBase, ext);
    const dir = path.dirname(destinoBase);
    let count = 1;

    while (fs.existsSync(destino)) {
      destino = path.join(dir, `${name}-${count}${ext}`);
      count++;
    }
  }

  fs.renameSync(itemPath, destino);

  return path.relative(SERVIDOR_DIR, destino).replace(/\\/g, "/");
}

app.post("/api/servidor/backup-seguranca", (_req, res) => {
  try {
    const destino = criarBackupServidorAntesMudancaCejas("manual");

    res.json({
      ok: true,
      destino,
      message: "Backup de segurança criado."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao criar backup: " + error.message
    });
  }
});
// CEJAS_PROTECAO_DADOS_END

'''

    if insert_after in s:
      s = s.replace(insert_after, insert_after + "\n" + bloco, 1)
    else:
      raise SystemExit("❌ Não encontrei SERVIDOR_DIR no server.js.")

# Troca exclusão definitiva do servidor por lixeira.
pattern = r'app\.delete\("/api/servidor/item",\s*\(req,\s*res\)\s*=>\s*\{[\s\S]*?\n\}\);'

novo_delete = r'''app.delete("/api/servidor/item", (req, res) => {
  try {
    const relativePath = String(req.query.path || "").trim();
    const itemPath = safeServidorPath(relativePath);

    if (!fs.existsSync(itemPath)) {
      return res.status(404).json({
        ok: false,
        message: "Item não encontrado."
      });
    }

    if (relativePath.startsWith("_LIXEIRA/")) {
      return res.status(400).json({
        ok: false,
        message: "Este item já está na lixeira. Exclusão definitiva bloqueada para proteger os documentos."
      });
    }

    const destinoLixeira = moverParaLixeiraServidorCejas(itemPath, relativePath);

    res.json({
      ok: true,
      destino: destinoLixeira,
      message: "Item movido para a lixeira de segurança. Nada foi apagado definitivamente."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao mover item para lixeira: " + error.message
    });
  }
});'''

if re.search(pattern, s):
    s = re.sub(pattern, novo_delete, s, count=1)

# Antes de reorganizar arquivos, cria snapshot automático.
if 'criarBackupServidorAntesMudancaCejas("reorganizar-eventos")' not in s:
    s = s.replace(
        'app.post("/api/servidor/reorganizar-eventos", express.json({ limit: "2mb" }), (req, res) => {\n  try {',
        'app.post("/api/servidor/reorganizar-eventos", express.json({ limit: "2mb" }), (req, res) => {\n  try {\n    criarBackupServidorAntesMudancaCejas("reorganizar-eventos");',
        1
    )

# Histórico de relatório antes de sobrescrever.
if "CEJAS_BACKUP_RELATORIO_START" not in s:
    marker = 'function emptySuperaReport() {'

    helper = r'''
// CEJAS_BACKUP_RELATORIO_START
function criarHistoricoRelatorioAtualCejas() {
  try {
    if (!fs.existsSync(RELATORIO_FILE)) return "";

    const historicoDir = path.join(__dirname, "data", "historico-relatorios");
    fs.mkdirSync(historicoDir, { recursive: true });

    const destino = path.join(historicoDir, `relatorio-atual-${cejasTimestampSeguro()}.json`);
    fs.copyFileSync(RELATORIO_FILE, destino);

    return destino;
  } catch (error) {
    console.warn("⚠️ Não foi possível salvar histórico do relatório:", error.message);
    return "";
  }
}
// CEJAS_BACKUP_RELATORIO_END

'''

    if marker in s:
        s = s.replace(marker, helper + marker, 1)

if "criarHistoricoRelatorioAtualCejas();" not in s:
    s = s.replace(
        'fs.writeFileSync(RELATORIO_FILE, JSON.stringify(report, null, 2), "utf8");',
        'criarHistoricoRelatorioAtualCejas();\n    fs.writeFileSync(RELATORIO_FILE, JSON.stringify(report, null, 2), "utf8");',
        1
    )

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path("servidor.html")

if p.exists():
    s = p.read_text()

    if "criarBackupSegurancaServidorCejas" not in s:
        js = r'''
<script>
// CEJAS_BACKUP_BUTTON_START
async function criarBackupSegurancaServidorCejas() {
  if (!confirm("Criar backup de segurança dos arquivos do servidor agora?")) return;

  const response = await fetch("/api/servidor/backup-seguranca", {
    method: "POST"
  });

  const data = await response.json();

  if (!data.ok) {
    alert(data.message || "Erro ao criar backup.");
    return;
  }

  alert("Backup criado com sucesso. Local: " + data.destino);
}
// CEJAS_BACKUP_BUTTON_END
</script>
'''
        s = s.replace("</body>", js + "\n</body>", 1)

    if "Backup de segurança" not in s:
        s = s.replace(
            '<button class="btn" style="width:100%;justify-content:center;margin-top:10px;" onclick="reorganizarServidorEventos()">',
            '<button class="btn" style="width:100%;justify-content:center;margin-top:10px;" onclick="criarBackupSegurancaServidorCejas()">\n            Backup de segurança\n          </button>\n\n          <button class="btn" style="width:100%;justify-content:center;margin-top:10px;" onclick="reorganizarServidorEventos()">',
            1
        )

    p.write_text(s)
PY

node --check server.js
[ -f js/cejas-mobile-menu.js ] && node --check js/cejas-mobile-menu.js || true

node <<'NODE'
const fs = require("fs");

if (fs.existsSync("servidor.html")) {
  const html = fs.readFileSync("servidor.html", "utf8");
  const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

  fs.mkdirSync(".cejas-local-backups/check-protecao-dados", { recursive: true });

  scripts.forEach((code, i) => {
    fs.writeFileSync(`.cejas-local-backups/check-protecao-dados/script-${i + 1}.js`, code);
  });
}
NODE

for f in .cejas-local-backups/check-protecao-dados/script-*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-protecao-dados

echo ""
echo "✅ Proteção aplicada."
echo ""
echo "Agora rode um backup manual imediatamente:"
echo "npm run backup:dados"
echo ""
echo "Depois audite:"
echo "npm run audit:dados"
echo ""
echo "Depois inicie:"
echo "npm run dev"
