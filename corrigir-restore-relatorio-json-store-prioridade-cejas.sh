#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "lib/relatorio-oficial-supabase-cejas.js" ]; then
  echo "❌ Não encontrei lib/relatorio-oficial-supabase-cejas.js"
  echo "Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/restore-relatorio-json-store-$STAMP"
mkdir -p "$BACKUP_DIR"

cp lib/relatorio-oficial-supabase-cejas.js "$BACKUP_DIR/relatorio-oficial-supabase-cejas.js"

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
    tabelaJsonStore: "cejas_json_store",
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
    item.status ||
    item.empresa ||
    item.solicitante
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

function contarEventos(relatorio) {
  if (!relatorio || typeof relatorio !== "object") return 0;

  const candidatos = [
    relatorio.eventos,
    relatorio.dados?.eventos,
    relatorio.resumo?.eventos,
    relatorio.lista,
    relatorio.items,
    relatorio.itens,
    relatorio.data?.eventos,
    relatorio.payload?.eventos
  ];

  for (const c of candidatos) {
    if (Array.isArray(c) && c.length) return c.length;
  }

  const extraidos = extrairEventos(relatorio);
  return extraidos.length;
}

function garantirEventos(relatorio) {
  if (!relatorio || typeof relatorio !== "object") return relatorio;

  if (Array.isArray(relatorio.eventos) && relatorio.eventos.length) {
    return relatorio;
  }

  const extraidos = extrairEventos(relatorio);

  if (extraidos.length) {
    return {
      ...relatorio,
      eventos: extraidos
    };
  }

  return relatorio;
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
    row?.dados,
    row?.relatorio,
    row?.report,
    row?.payload,
    row?.json,
    row?.conteudo,
    row?.data
  ];

  for (const c of candidatos) {
    if (c && typeof c === "object" && !Array.isArray(c)) {
      return JSON.parse(JSON.stringify(c));
    }
  }

  return {};
}

function normalizarRelatorio(row) {
  const base = garantirEventos(extrairObjetoRelatorio(row));

  const resumoExistente =
    base.resumo && typeof base.resumo === "object"
      ? base.resumo
      : {};

  const eventos =
    Array.isArray(base.eventos) ? base.eventos :
    Array.isArray(base.dados?.eventos) ? base.dados.eventos :
    Array.isArray(row?.eventos) ? row.eventos :
    extrairEventos(base);

  const totalEventos =
    numero(row?.total_eventos) ||
    numero(row?.totalEventos) ||
    numero(base.total_eventos) ||
    numero(base.totalEventos) ||
    numero(resumoExistente.total_eventos) ||
    numero(resumoExistente.totalEventos) ||
    eventos.length;

  const eventosConfirmados =
    numero(row?.eventos_confirmados) ||
    numero(row?.eventosConfirmados) ||
    numero(base.eventos_confirmados) ||
    numero(base.eventosConfirmados) ||
    numero(resumoExistente.eventos_confirmados) ||
    numero(resumoExistente.eventosConfirmados);

  const eventosEmEspera =
    numero(row?.eventos_em_espera) ||
    numero(row?.eventosEmEspera) ||
    numero(base.eventos_em_espera) ||
    numero(base.eventosEmEspera) ||
    numero(resumoExistente.eventos_em_espera) ||
    numero(resumoExistente.eventosEmEspera);

  const nomeArquivo =
    row?.nome_arquivo ||
    row?.nomeArquivo ||
    base.nome_arquivo ||
    base.nomeArquivo ||
    "relatorio-supera.pdf";

  return {
    ...base,
    idSupabase: row?.id || row?.uuid || row?.eu_ia || row?.["eu ia"] || null,
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
      eventosEmEspera,
      eventos_na_lista: eventos.length,
      eventosNaLista: eventos.length
    },
    restauradoDoSupabase: true,
    restauradoEm: new Date().toISOString()
  };
}

function dataLinha(row) {
  const campos = [
    row?.atualizado_em,
    row?.updated_at,
    row?.criado_em,
    row?.created_at,
    row?.importado_em,
    row?.data_importacao
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

async function listarJsonStoreSupabase() {
  const rows = await restRequest("cejas_json_store?select=chave,dados,atualizado_em", {
    method: "GET"
  });

  return Array.isArray(rows) ? rows : [];
}

async function obterRelatorioCompletoDoJsonStore() {
  const rows = await listarJsonStoreSupabase();

  const candidatos = rows
    .filter(row => [
      "relatorio-supera.json",
      "relatorio-atual.json"
    ].includes(row.chave))
    .map(row => ({
      row,
      relatorio: garantirEventos(row.dados),
      eventosNaLista: contarEventos(row.dados),
      timestamp: Date.parse(row.atualizado_em || "") || 0
    }))
    .filter(item => item.eventosNaLista > 0)
    .sort((a, b) => b.timestamp - a.timestamp);

  if (!candidatos.length) {
    return {
      row: null,
      relatorio: null,
      totalLinhas: rows.length,
      eventosNaLista: 0
    };
  }

  const escolhido = candidatos[0];

  return {
    row: escolhido.row,
    relatorio: normalizarRelatorio({
      dados: escolhido.relatorio,
      nome_arquivo: escolhido.relatorio?.nomeArquivo || escolhido.relatorio?.nome_arquivo || escolhido.row.chave,
      atualizado_em: escolhido.row.atualizado_em
    }),
    totalLinhas: rows.length,
    eventosNaLista: escolhido.eventosNaLista
  };
}

async function obterUltimoRelatorioOficial() {
  const rows = await listarRelatoriosSupabase();

  const analisados = rows
    .filter(Boolean)
    .map(row => {
      const relatorio = normalizarRelatorio(row);
      const eventosNaLista = contarEventos(relatorio);
      const temResumo = temConteudoReal(relatorio);
      const timestamp = dataLinha(row);

      return {
        row,
        relatorio,
        eventosNaLista,
        temResumo,
        timestamp
      };
    });

  const comEventos = analisados
    .filter(item => item.eventosNaLista > 0)
    .sort((a, b) => b.timestamp - a.timestamp);

  if (comEventos.length) {
    return {
      row: comEventos[0].row,
      relatorio: comEventos[0].relatorio,
      totalLinhas: rows.length,
      origemEscolhida: "cejas_relatorios_com_eventos",
      eventosNaLista: comEventos[0].eventosNaLista,
      linhasComEventos: comEventos.length
    };
  }

  const jsonStore = await obterRelatorioCompletoDoJsonStore();

  if (jsonStore.relatorio && contarEventos(jsonStore.relatorio) > 0) {
    return {
      row: jsonStore.row,
      relatorio: jsonStore.relatorio,
      totalLinhas: rows.length,
      origemEscolhida: "cejas_json_store_relatorio_completo",
      eventosNaLista: contarEventos(jsonStore.relatorio),
      linhasComEventos: 0,
      totalJsonStore: jsonStore.totalLinhas
    };
  }

  const comResumo = analisados
    .filter(item => item.temResumo)
    .sort((a, b) => b.timestamp - a.timestamp);

  if (comResumo.length) {
    return {
      row: comResumo[0].row,
      relatorio: comResumo[0].relatorio,
      totalLinhas: rows.length,
      origemEscolhida: "cejas_relatorios_somente_resumo",
      eventosNaLista: 0,
      linhasComEventos: 0
    };
  }

  return {
    row: null,
    relatorio: null,
    totalLinhas: rows.length,
    origemEscolhida: "nenhum_relatorio_valido",
    eventosNaLista: 0,
    linhasComEventos: 0
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

  const localAtual = garantirEventos(lerJsonLocal(RELATORIO_SUPERA_FILE));
  const eventosLocal = contarEventos(localAtual);

  if (!result.relatorio) {
    if (eventosLocal > 0) {
      const jsonLocal = JSON.stringify(localAtual, null, 2);
      fs.writeFileSync(RELATORIO_SUPERA_FILE, jsonLocal, "utf8");
      fs.writeFileSync(RELATORIO_ATUAL_FILE, jsonLocal, "utf8");

      return {
        ok: true,
        restaurado: true,
        origemEscolhida: "local_com_eventos",
        motivo: "Nenhum relatório válido no Supabase. Mantive local com eventos.",
        eventosNaLista: eventosLocal,
        totalLinhas: result.totalLinhas
      };
    }

    return {
      ok: false,
      restaurado: false,
      motivo: "Nenhum relatório válido encontrado no Supabase ou local.",
      totalLinhas: result.totalLinhas
    };
  }

  const relatorioComEventos = garantirEventos(result.relatorio);
  const eventosSupabase = contarEventos(relatorioComEventos);

  if (eventosSupabase === 0 && eventosLocal > 0) {
    const jsonLocal = JSON.stringify(localAtual, null, 2);
    fs.writeFileSync(RELATORIO_SUPERA_FILE, jsonLocal, "utf8");
    fs.writeFileSync(RELATORIO_ATUAL_FILE, jsonLocal, "utf8");

    return {
      ok: true,
      restaurado: true,
      origemEscolhida: "local_com_eventos_protegido",
      motivo: "Supabase tinha apenas resumo. Mantive relatório local com eventos.",
      eventosSupabase,
      eventosLocal,
      eventosNaLista: eventosLocal,
      totalLinhas: result.totalLinhas
    };
  }

  const json = JSON.stringify(relatorioComEventos, null, 2);

  fs.writeFileSync(RELATORIO_SUPERA_FILE, json, "utf8");
  fs.writeFileSync(RELATORIO_ATUAL_FILE, json, "utf8");

  return {
    ok: true,
    restaurado: true,
    origemEscolhida: result.origemEscolhida,
    nomeArquivo: relatorioComEventos.nomeArquivo || relatorioComEventos.nome_arquivo,
    totalEventos: relatorioComEventos.totalEventos || relatorioComEventos.total_eventos || eventosSupabase,
    eventosConfirmados: relatorioComEventos.eventosConfirmados || relatorioComEventos.eventos_confirmados || 0,
    eventosEmEspera: relatorioComEventos.eventosEmEspera || relatorioComEventos.eventos_em_espera || 0,
    eventosNaLista: eventosSupabase,
    totalLinhas: result.totalLinhas,
    totalJsonStore: result.totalJsonStore
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
          origemEscolhida: ultimo.origemEscolhida,
          message: "Nenhum relatório válido encontrado."
        });
      }

      const relatorio = garantirEventos(ultimo.relatorio);

      res.json({
        ok: true,
        status: statusRelatorioOficialSupabase(),
        totalLinhas: ultimo.totalLinhas,
        origemEscolhida: ultimo.origemEscolhida,
        nomeArquivo: relatorio.nomeArquivo || relatorio.nome_arquivo,
        totalEventos: relatorio.totalEventos || relatorio.total_eventos || 0,
        eventosConfirmados: relatorio.eventosConfirmados || relatorio.eventos_confirmados || 0,
        eventosEmEspera: relatorio.eventosEmEspera || relatorio.eventos_em_espera || 0,
        eventosNaLista: contarEventos(relatorio),
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

echo ""
echo "🔎 Verificando sintaxe..."
node --check lib/relatorio-oficial-supabase-cejas.js
node --check scripts/relatorio-oficial-restore-cejas.js
node --check scripts/start-seguro-cejas.js
node --check server.js

echo ""
echo "✅ Restore reforçado aplicado."
echo ""
echo "Agora rode:"
echo "npm run relatorio:restore"
echo "npm start"
