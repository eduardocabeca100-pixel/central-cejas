#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/restore-relatorio-oficial-$STAMP"
mkdir -p "$BACKUP_DIR" lib scripts

cp server.js package.json "$BACKUP_DIR/" 2>/dev/null || true
[ -f scripts/start-seguro-cejas.js ] && cp scripts/start-seguro-cejas.js "$BACKUP_DIR/start-seguro-cejas.js" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

cat > lib/relatorio-oficial-supabase-cejas.js <<'EOF'
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

function statusRelatorioOficialSupabase() {
  const env = getEnv();

  return {
    ok: Boolean(env.url && env.serviceRole),
    tabela: "cejas_relatorios",
    hasUrl: Boolean(env.url),
    hasServiceRole: Boolean(env.serviceRole),
    destinoSupera: RELATORIO_SUPERA_FILE,
    destinoAtual: RELATORIO_ATUAL_FILE
  };
}

function assertEnv() {
  const env = getEnv();

  if (!env.url || !env.serviceRole) {
    throw new Error("Supabase não configurado para restaurar relatório oficial.");
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

function numero(valor) {
  const n = Number(valor || 0);
  return Number.isFinite(n) ? n : 0;
}

function contarEventos(relatorio) {
  const candidatos = [
    relatorio?.eventos,
    relatorio?.dados?.eventos,
    relatorio?.resumo?.eventos,
    relatorio?.lista,
    relatorio?.items,
    relatorio?.itens
  ];

  for (const c of candidatos) {
    if (Array.isArray(c)) return c.length;
  }

  return 0;
}

function temConteudoReal(relatorio) {
  if (!relatorio || typeof relatorio !== "object") return false;

  if (contarEventos(relatorio) > 0) return true;

  const total =
    numero(relatorio.total_eventos) ||
    numero(relatorio.totalEventos) ||
    numero(relatorio.resumo?.total_eventos) ||
    numero(relatorio.resumo?.totalEventos);

  return total > 0;
}

function extrairObjetoRelatorio(row) {
  const candidatos = [
    row.dados,
    row.relatorio,
    row.report,
    row.payload,
    row.json,
    row.conteudo,
    row.data
  ];

  for (const c of candidatos) {
    if (c && typeof c === "object" && !Array.isArray(c)) {
      return JSON.parse(JSON.stringify(c));
    }
  }

  return {};
}

function normalizarRelatorio(row) {
  const base = extrairObjetoRelatorio(row);

  const resumoExistente =
    base.resumo && typeof base.resumo === "object"
      ? base.resumo
      : {};

  const eventos =
    Array.isArray(base.eventos) ? base.eventos :
    Array.isArray(base.dados?.eventos) ? base.dados.eventos :
    Array.isArray(row.eventos) ? row.eventos :
    [];

  const totalEventos =
    numero(row.total_eventos) ||
    numero(row.totalEventos) ||
    numero(base.total_eventos) ||
    numero(base.totalEventos) ||
    numero(resumoExistente.total_eventos) ||
    numero(resumoExistente.totalEventos) ||
    eventos.length;

  const eventosConfirmados =
    numero(row.eventos_confirmados) ||
    numero(row.eventosConfirmados) ||
    numero(base.eventos_confirmados) ||
    numero(base.eventosConfirmados) ||
    numero(resumoExistente.eventos_confirmados) ||
    numero(resumoExistente.eventosConfirmados);

  const eventosEmEspera =
    numero(row.eventos_em_espera) ||
    numero(row.eventosEmEspera) ||
    numero(base.eventos_em_espera) ||
    numero(base.eventosEmEspera) ||
    numero(resumoExistente.eventos_em_espera) ||
    numero(resumoExistente.eventosEmEspera);

  const nomeArquivo =
    row.nome_arquivo ||
    row.nomeArquivo ||
    base.nome_arquivo ||
    base.nomeArquivo ||
    "relatorio-supera.pdf";

  const relatorio = {
    ...base,
    idSupabase: row.id || row.uuid || row.eu_ia || row["eu ia"] || null,
    nome_arquivo: nomeArquivo,
    nomeArquivo,
    total_eventos: totalEventos,
    totalEventos,
    eventos_confirmados: eventosConfirmados,
    eventosConfirmados,
    eventos_em_espera: eventosEmEspera,
    eventosEmEspera,
    eventos,
    resumo: {
      ...resumoExistente,
      total_eventos: totalEventos,
      totalEventos,
      eventos_confirmados: eventosConfirmados,
      eventosConfirmados,
      eventos_em_espera: eventosEmEspera,
      eventosEmEspera
    },
    restauradoDoSupabase: true,
    restauradoEm: new Date().toISOString()
  };

  return relatorio;
}

function dataLinha(row) {
  const campos = [
    row.atualizado_em,
    row.updated_at,
    row.criado_em,
    row.created_at,
    row.importado_em,
    row.data_importacao
  ];

  for (const c of campos) {
    const t = Date.parse(c || "");
    if (Number.isFinite(t)) return t;
  }

  return 0;
}

async function listarRelatoriosSupabase() {
  const rows = await restRequest("cejas_relatorios?select=*&limit=1000", {
    method: "GET"
  });

  return Array.isArray(rows) ? rows : [];
}

async function obterUltimoRelatorioOficial() {
  const rows = await listarRelatoriosSupabase();

  const ordenados = rows
    .filter(Boolean)
    .sort((a, b) => dataLinha(b) - dataLinha(a));

  for (const row of ordenados) {
    const relatorio = normalizarRelatorio(row);

    if (temConteudoReal(relatorio)) {
      return {
        row,
        relatorio,
        totalLinhas: rows.length
      };
    }
  }

  return {
    row: null,
    relatorio: null,
    totalLinhas: rows.length
  };
}

function lerJsonLocal(file) {
  try {
    if (!fs.existsSync(file)) return null;
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

async function restaurarRelatorioOficialDoSupabase() {
  fs.mkdirSync(DATA_DIR, { recursive: true });

  const result = await obterUltimoRelatorioOficial();

  if (!result.relatorio) {
    return {
      ok: false,
      restaurado: false,
      motivo: "Nenhum relatório válido encontrado em cejas_relatorios.",
      totalLinhas: result.totalLinhas
    };
  }

  const eventosSupabase = contarEventos(result.relatorio);
  const localAtual = lerJsonLocal(RELATORIO_SUPERA_FILE);
  const eventosLocal = contarEventos(localAtual);

  // Proteção: não sobrescreve um relatório local cheio por um registro do Supabase sem lista de eventos.
  if (eventosSupabase === 0 && eventosLocal > 0) {
    return {
      ok: true,
      restaurado: false,
      motivo: "Supabase tem resumo, mas não tem lista de eventos. Mantive relatório local com eventos.",
      eventosSupabase,
      eventosLocal,
      totalLinhas: result.totalLinhas
    };
  }

  const json = JSON.stringify(result.relatorio, null, 2);

  fs.writeFileSync(RELATORIO_SUPERA_FILE, json, "utf8");
  fs.writeFileSync(RELATORIO_ATUAL_FILE, json, "utf8");

  return {
    ok: true,
    restaurado: true,
    nomeArquivo: result.relatorio.nomeArquivo || result.relatorio.nome_arquivo,
    totalEventos: result.relatorio.totalEventos || result.relatorio.total_eventos || 0,
    eventosConfirmados: result.relatorio.eventosConfirmados || result.relatorio.eventos_confirmados || 0,
    eventosEmEspera: result.relatorio.eventosEmEspera || result.relatorio.eventos_em_espera || 0,
    eventosNaLista: contarEventos(result.relatorio),
    totalLinhas: result.totalLinhas
  };
}

function registrarRotasRelatorioOficialSupabase(app) {
  if (!app || app.__CEJAS_RELATORIO_OFICIAL_SUPABASE__) return;

  app.__CEJAS_RELATORIO_OFICIAL_SUPABASE__ = true;

  app.get("/api/sistema/relatorio-oficial-status", async (_req, res) => {
    try {
      const ultimo = await obterUltimoRelatorioOficial();

      res.set("Cache-Control", "no-store");

      if (!ultimo.relatorio) {
        return res.json({
          ok: false,
          status: statusRelatorioOficialSupabase(),
          totalLinhas: ultimo.totalLinhas,
          message: "Nenhum relatório válido encontrado."
        });
      }

      res.json({
        ok: true,
        status: statusRelatorioOficialSupabase(),
        totalLinhas: ultimo.totalLinhas,
        nomeArquivo: ultimo.relatorio.nomeArquivo || ultimo.relatorio.nome_arquivo,
        totalEventos: ultimo.relatorio.totalEventos || ultimo.relatorio.total_eventos || 0,
        eventosConfirmados: ultimo.relatorio.eventosConfirmados || ultimo.relatorio.eventos_confirmados || 0,
        eventosEmEspera: ultimo.relatorio.eventosEmEspera || ultimo.relatorio.eventos_em_espera || 0,
        eventosNaLista: contarEventos(ultimo.relatorio),
        dataLinha: dataLinha(ultimo.row)
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message,
        status: statusRelatorioOficialSupabase()
      });
    }
  });

  app.post("/api/sistema/relatorio-oficial-restore", async (_req, res) => {
    try {
      const result = await restaurarRelatorioOficialDoSupabase();
      res.json(result);
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });
}

module.exports = {
  statusRelatorioOficialSupabase,
  listarRelatoriosSupabase,
  obterUltimoRelatorioOficial,
  restaurarRelatorioOficialDoSupabase,
  registrarRotasRelatorioOficialSupabase
};
EOF

cat > scripts/relatorio-oficial-restore-cejas.js <<'EOF'
const {
  statusRelatorioOficialSupabase,
  restaurarRelatorioOficialDoSupabase
} = require("../lib/relatorio-oficial-supabase-cejas");

(async () => {
  console.log("📊 Status relatório oficial:", statusRelatorioOficialSupabase());
  const result = await restaurarRelatorioOficialDoSupabase();
  console.log(JSON.stringify(result, null, 2));
})().catch(error => {
  console.error("❌ Erro ao restaurar relatório oficial:", error.message);
  process.exit(1);
});
EOF

python3 <<'PY'
from pathlib import Path
import json

p = Path("package.json")
pkg = json.loads(p.read_text())
scripts = pkg.setdefault("scripts", {})

scripts["relatorio:restore"] = "node scripts/relatorio-oficial-restore-cejas.js"

p.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + "\n")
PY

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const { registrarRotasRelatorioOficialSupabase } = require("./lib/relatorio-oficial-supabase-cejas");'

if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace('const path = require("path");', 'const path = require("path");\n' + require_line, 1)
    elif 'const express = require("express");' in s:
        s = s.replace('const express = require("express");', 'const express = require("express");\n' + require_line, 1)
    else:
        s = require_line + "\n" + s

call_line = 'registrarRotasRelatorioOficialSupabase(app);'

if call_line not in s:
    marker = "const app = express();"
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express();")
    s = s.replace(marker, marker + "\n" + call_line, 1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path("scripts/start-seguro-cejas.js")

if not p.exists():
    p.write_text('require("dotenv").config();\n\n(async () => {\n  console.log("🚀 Abrindo servidor...");\n  require("../server.js");\n})();\n')

s = p.read_text()

bloco = r'''
  // CEJAS_RESTORE_RELATORIO_OFICIAL_SUPABASE_START
  try {
    const {
      statusRelatorioOficialSupabase,
      restaurarRelatorioOficialDoSupabase
    } = require("../lib/relatorio-oficial-supabase-cejas");

    console.log("📊 Status relatório oficial Supabase:", statusRelatorioOficialSupabase());

    const restoreRelatorioOficial = await restaurarRelatorioOficialDoSupabase();
    console.log("✅ Relatório oficial restaurado do Supabase:", restoreRelatorioOficial);
  } catch (error) {
    console.warn("⚠️ Restore relatório oficial ignorado:", error.message);
  }
  // CEJAS_RESTORE_RELATORIO_OFICIAL_SUPABASE_END

'''

if "CEJAS_RESTORE_RELATORIO_OFICIAL_SUPABASE_START" not in s:
    marker = 'console.log("🚀 Abrindo servidor...");'
    if marker in s:
        s = s.replace(marker, bloco + "  " + marker, 1)
    else:
        s = s.replace('require("../server.js");', bloco + '  require("../server.js");', 1)

p.write_text(s)
PY

echo ""
echo "🔎 Verificando sintaxe..."

node --check lib/relatorio-oficial-supabase-cejas.js
node --check scripts/relatorio-oficial-restore-cejas.js
node --check scripts/start-seguro-cejas.js
node --check server.js

echo ""
echo "✅ Restore do relatório oficial configurado."
echo ""
echo "Agora rode:"
echo "npm run relatorio:restore"
echo "npm start"
