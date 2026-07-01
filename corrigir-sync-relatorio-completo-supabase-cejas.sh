#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/sync-relatorio-completo-$STAMP"
mkdir -p "$BACKUP_DIR" lib scripts

cp server.js package.json "$BACKUP_DIR/" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

cat > lib/relatorio-oficial-sync-cejas.js <<'EOF'
require("dotenv").config();

const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(process.cwd(), "data");
const RELATORIO_SUPERA_FILE = path.join(DATA_DIR, "relatorio-supera.json");
const RELATORIO_ATUAL_FILE = path.join(DATA_DIR, "relatorio-atual.json");

function cleanEnv(value) {
  return String(value || "").trim().replace(/^["']|["']$/g, "");
}

function getEnv() {
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

  return { url, serviceRole };
}

function assertEnv() {
  const env = getEnv();

  if (!env.url || !env.serviceRole) {
    throw new Error("Supabase não configurado.");
  }

  return env;
}

function headers(extra = {}) {
  const env = assertEnv();

  return {
    apikey: env.serviceRole,
    Authorization: `Bearer ${env.serviceRole}`,
    "Content-Type": "application/json",
    ...extra
  };
}

async function restRequest(route, options = {}) {
  const env = assertEnv();
  const url = `${env.url.replace(/\/$/, "")}/rest/v1/${route}`;

  const response = await fetch(url, {
    ...options,
    headers: headers(options.headers || {})
  });

  const text = await response.text();

  if (!response.ok) {
    throw new Error(text || `HTTP ${response.status}`);
  }

  if (!text) return null;

  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function lerJson(file) {
  if (!fs.existsSync(file)) return null;
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function buscarRelatorioLocal() {
  let relatorio = null;

  try {
    relatorio = lerJson(RELATORIO_SUPERA_FILE);
  } catch {}

  if (!relatorio) {
    try {
      relatorio = lerJson(RELATORIO_ATUAL_FILE);
    } catch {}
  }

  if (!relatorio || typeof relatorio !== "object") {
    throw new Error("Nenhum relatório local encontrado em data/relatorio-supera.json ou data/relatorio-atual.json.");
  }

  return relatorio;
}

function numero(valor) {
  if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

  const n = Number(
    String(valor || "")
      .replace(/R\$/gi, "")
      .replace(/\s/g, "")
      .replace(/\./g, "")
      .replace(",", ".")
  );

  return Number.isFinite(n) ? n : 0;
}

function pareceEvento(item) {
  if (!item || typeof item !== "object" || Array.isArray(item)) return false;

  return Boolean(
    item.evento ||
    item.nomeEvento ||
    item.titulo ||
    item.title ||
    item.sala ||
    item.local ||
    item.data ||
    item.dataEvento ||
    item.valorTotal ||
    item.receitaConfirmada ||
    item.status
  );
}

function extrairEventos(obj, lista = [], visitados = new Set()) {
  if (!obj || typeof obj !== "object") return lista;
  if (visitados.has(obj)) return lista;

  visitados.add(obj);

  if (Array.isArray(obj)) {
    const eventosDaLista = obj.filter(pareceEvento);

    if (eventosDaLista.length >= 10) {
      lista.push(...eventosDaLista);
      return lista;
    }

    obj.forEach(item => extrairEventos(item, lista, visitados));
    return lista;
  }

  if (pareceEvento(obj)) lista.push(obj);

  Object.values(obj).forEach(value => {
    if (value && typeof value === "object") {
      extrairEventos(value, lista, visitados);
    }
  });

  return lista;
}

function statusConfirmado(item) {
  const status = String(
    item.status ||
    item.situacao ||
    item.estado ||
    item.confirmacao ||
    ""
  ).toUpperCase();

  return status.includes("CONFIRM") ||
    status.includes("REALIZAD") ||
    status.includes("LIBERAD") ||
    status.includes("APROVAD");
}

function statusEspera(item) {
  const status = String(
    item.status ||
    item.situacao ||
    item.estado ||
    item.confirmacao ||
    ""
  ).toUpperCase();

  return status.includes("ESPERA") ||
    status.includes("PENDENTE") ||
    status.includes("AGUARD");
}

function resumoDoRelatorio(relatorio, eventos) {
  const resumo = relatorio.resumo && typeof relatorio.resumo === "object"
    ? relatorio.resumo
    : {};

  const totalEventos =
    numero(relatorio.total_eventos) ||
    numero(relatorio.totalEventos) ||
    numero(resumo.total_eventos) ||
    numero(resumo.totalEventos) ||
    eventos.length;

  const eventosConfirmados =
    numero(relatorio.eventos_confirmados) ||
    numero(relatorio.eventosConfirmados) ||
    numero(resumo.eventos_confirmados) ||
    numero(resumo.eventosConfirmados) ||
    eventos.filter(statusConfirmado).length;

  const eventosEmEspera =
    numero(relatorio.eventos_em_espera) ||
    numero(relatorio.eventosEmEspera) ||
    numero(resumo.eventos_em_espera) ||
    numero(resumo.eventosEmEspera) ||
    eventos.filter(statusEspera).length;

  const nomeArquivo =
    relatorio.nome_arquivo ||
    relatorio.nomeArquivo ||
    relatorio.arquivo ||
    relatorio.filename ||
    "relatorio-supera.pdf";

  return {
    nomeArquivo,
    totalEventos,
    eventosConfirmados,
    eventosEmEspera,
    eventosNaLista: eventos.length
  };
}

async function syncRelatorioCompletoParaSupabase() {
  const relatorio = buscarRelatorioLocal();
  const eventos = extrairEventos(relatorio);
  const resumo = resumoDoRelatorio(relatorio, eventos);

  if (!resumo.totalEventos && !eventos.length) {
    throw new Error("Relatório local não tem eventos nem resumo válido.");
  }

  const relatorioCompleto = {
    ...relatorio,
    eventos: Array.isArray(relatorio.eventos) && relatorio.eventos.length
      ? relatorio.eventos
      : eventos,
    resumo: {
      ...(relatorio.resumo || {}),
      total_eventos: resumo.totalEventos,
      totalEventos: resumo.totalEventos,
      eventos_confirmados: resumo.eventosConfirmados,
      eventosConfirmados: resumo.eventosConfirmados,
      eventos_em_espera: resumo.eventosEmEspera,
      eventosEmEspera: resumo.eventosEmEspera,
      eventos_na_lista: resumo.eventosNaLista,
      eventosNaLista: resumo.eventosNaLista
    },
    sincronizadoCompletoEm: new Date().toISOString()
  };

  const body = {
    nome_arquivo: resumo.nomeArquivo,
    total_eventos: resumo.totalEventos,
    eventos_confirmados: resumo.eventosConfirmados,
    eventos_em_espera: resumo.eventosEmEspera,
    dados: relatorioCompleto,
    resumo: relatorioCompleto.resumo
  };

  const inserted = await restRequest("cejas_relatorios", {
    method: "POST",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify(body)
  });

  return {
    ok: true,
    enviado: true,
    nomeArquivo: resumo.nomeArquivo,
    totalEventos: resumo.totalEventos,
    eventosConfirmados: resumo.eventosConfirmados,
    eventosEmEspera: resumo.eventosEmEspera,
    eventosNaLista: resumo.eventosNaLista,
    id: Array.isArray(inserted) && inserted[0] ? inserted[0].id || inserted[0]["eu ia"] : null
  };
}

function registrarRotasSyncRelatorioCompleto(app) {
  if (!app || app.__CEJAS_SYNC_RELATORIO_COMPLETO__) return;

  app.__CEJAS_SYNC_RELATORIO_COMPLETO__ = true;

  app.post("/api/sistema/relatorio-sync-completo", async (_req, res) => {
    try {
      const result = await syncRelatorioCompletoParaSupabase();
      res.json(result);
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.use((req, res, next) => {
    const muda = ["POST", "PUT", "PATCH", "DELETE"].includes(req.method);

    const rotaRelatorio =
      req.path.startsWith("/api/importar-relatorio") ||
      req.path.startsWith("/api/relatorio") ||
      req.path.startsWith("/api/supera");

    if (muda && rotaRelatorio) {
      res.on("finish", () => {
        if (res.statusCode < 400) {
          setTimeout(() => {
            syncRelatorioCompletoParaSupabase().catch(error => {
              console.warn("⚠️ Sync relatório completo falhou:", error.message);
            });
          }, 2500);
        }
      });
    }

    next();
  });
}

module.exports = {
  syncRelatorioCompletoParaSupabase,
  registrarRotasSyncRelatorioCompleto
};
EOF

cat > scripts/relatorio-oficial-sync-completo-cejas.js <<'EOF'
const {
  syncRelatorioCompletoParaSupabase
} = require("../lib/relatorio-oficial-sync-cejas");

(async () => {
  const result = await syncRelatorioCompletoParaSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro ao sincronizar relatório completo:", error.message);
  process.exit(1);
});
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())
scripts = pkg.setdefault("scripts", {})

scripts["relatorio:sync-oficial"] = "node scripts/relatorio-oficial-sync-completo-cejas.js"

p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const { registrarRotasSyncRelatorioCompleto } = require("./lib/relatorio-oficial-sync-cejas");'

if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace('const path = require("path");', 'const path = require("path");\n' + require_line, 1)
    elif 'const express = require("express");' in s:
        s = s.replace('const express = require("express");', 'const express = require("express");\n' + require_line, 1)
    else:
        s = require_line + "\n" + s

call_line = 'registrarRotasSyncRelatorioCompleto(app);'

if call_line not in s:
    marker = "const app = express();"
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express();")
    s = s.replace(marker, marker + "\n" + call_line, 1)

p.write_text(s)
PY

echo ""
echo "🔎 Verificando sintaxe..."

node --check lib/relatorio-oficial-sync-cejas.js
node --check scripts/relatorio-oficial-sync-completo-cejas.js
node --check server.js

echo ""
echo "✅ Sync de relatório completo configurado."
echo ""
echo "Agora rode:"
echo "npm run relatorio:sync-oficial"
echo "npm run relatorio:restore"
echo "npm start"
