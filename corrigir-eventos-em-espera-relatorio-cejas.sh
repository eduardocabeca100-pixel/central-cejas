#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "lib/relatorio-oficial-supabase-cejas.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/fix-eventos-em-espera-$STAMP"
mkdir -p "$BACKUP_DIR"

cp lib/relatorio-oficial-supabase-cejas.js "$BACKUP_DIR/relatorio-oficial-supabase-cejas.js"

python3 <<'PY'
from pathlib import Path

p = Path("lib/relatorio-oficial-supabase-cejas.js")
s = p.read_text()

old = '''  const jsonStore = await obterRelatorioCompletoDoJsonStore();

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
'''

new = '''  const jsonStore = await obterRelatorioCompletoDoJsonStore();

  if (jsonStore.relatorio && contarEventos(jsonStore.relatorio) > 0) {
    const resumosDisponiveis = analisados
      .filter(item => item.temResumo)
      .sort((a, b) => b.timestamp - a.timestamp);

    const resumoBase = resumosDisponiveis[0]?.relatorio || {};

    const escolherNumero = (...valores) => {
      for (const valor of valores) {
        const n = numero(valor);
        if (n > 0) return n;
      }
      return 0;
    };

    const totalEventos = escolherNumero(
      jsonStore.relatorio.totalEventos,
      jsonStore.relatorio.total_eventos,
      jsonStore.relatorio.resumo?.totalEventos,
      jsonStore.relatorio.resumo?.total_eventos,
      resumoBase.totalEventos,
      resumoBase.total_eventos,
      resumoBase.resumo?.totalEventos,
      resumoBase.resumo?.total_eventos,
      contarEventos(jsonStore.relatorio)
    );

    const eventosConfirmados = escolherNumero(
      jsonStore.relatorio.eventosConfirmados,
      jsonStore.relatorio.eventos_confirmados,
      jsonStore.relatorio.resumo?.eventosConfirmados,
      jsonStore.relatorio.resumo?.eventos_confirmados,
      resumoBase.eventosConfirmados,
      resumoBase.eventos_confirmados,
      resumoBase.resumo?.eventosConfirmados,
      resumoBase.resumo?.eventos_confirmados
    );

    const eventosEmEspera = escolherNumero(
      jsonStore.relatorio.eventosEmEspera,
      jsonStore.relatorio.eventos_em_espera,
      jsonStore.relatorio.resumo?.eventosEmEspera,
      jsonStore.relatorio.resumo?.eventos_em_espera,
      resumoBase.eventosEmEspera,
      resumoBase.eventos_em_espera,
      resumoBase.resumo?.eventosEmEspera,
      resumoBase.resumo?.eventos_em_espera
    );

    const relatorioMesclado = {
      ...jsonStore.relatorio,
      totalEventos,
      total_eventos: totalEventos,
      eventosConfirmados,
      eventos_confirmados: eventosConfirmados,
      eventosEmEspera,
      eventos_em_espera: eventosEmEspera,
      resumo: {
        ...(jsonStore.relatorio.resumo || {}),
        totalEventos,
        total_eventos: totalEventos,
        eventosConfirmados,
        eventos_confirmados: eventosConfirmados,
        eventosEmEspera,
        eventos_em_espera: eventosEmEspera,
        eventosNaLista: contarEventos(jsonStore.relatorio),
        eventos_na_lista: contarEventos(jsonStore.relatorio)
      }
    };

    return {
      row: jsonStore.row,
      relatorio: relatorioMesclado,
      totalLinhas: rows.length,
      origemEscolhida: "cejas_json_store_relatorio_completo",
      eventosNaLista: contarEventos(relatorioMesclado),
      linhasComEventos: 0,
      totalJsonStore: jsonStore.totalLinhas
    };
  }

  const comResumo = analisados
'''

if old not in s:
    raise SystemExit("❌ Não encontrei o bloco esperado para substituir.")

s = s.replace(old, new, 1)
p.write_text(s)
PY

node --check lib/relatorio-oficial-supabase-cejas.js
node --check scripts/relatorio-oficial-restore-cejas.js
node --check scripts/start-seguro-cejas.js
node --check server.js

echo ""
echo "✅ Corrigido para manter eventos em espera do resumo."
echo ""
echo "Agora rode:"
echo "npm run relatorio:restore"
echo "npm start"
