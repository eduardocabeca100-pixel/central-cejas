#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "lib/relatorio-oficial-supabase-cejas.js" ]; then
  echo "❌ Não encontrei lib/relatorio-oficial-supabase-cejas.js"
  echo "Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/prioridade-relatorio-completo-$STAMP"
mkdir -p "$BACKUP_DIR"

cp lib/relatorio-oficial-supabase-cejas.js "$BACKUP_DIR/relatorio-oficial-supabase-cejas.js"

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path

p = Path("lib/relatorio-oficial-supabase-cejas.js")
s = p.read_text()

def replace_async_function(source, name, replacement):
    marker = f"async function {name}("
    start = source.find(marker)
    if start == -1:
        raise SystemExit(f"❌ Não encontrei {marker}")

    brace = source.find("{", start)
    if brace == -1:
        raise SystemExit(f"❌ Não encontrei abertura de {name}")

    depth = 0
    i = brace

    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[:start] + replacement + source[i + 1:]

        i += 1

    raise SystemExit(f"❌ Não encontrei fechamento de {name}")

nova = r'''async function obterUltimoRelatorioOficial() {
  const rows = await listarRelatoriosSupabase();

  const analisados = rows
    .filter(Boolean)
    .map((row) => {
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

  // Prioridade 1:
  // Sempre preferir relatório com lista completa de eventos.
  // Mesmo que exista outro registro mais recente somente com resumo.
  const comEventos = analisados
    .filter(item => item.eventosNaLista > 0)
    .sort((a, b) => b.timestamp - a.timestamp);

  if (comEventos.length) {
    return {
      row: comEventos[0].row,
      relatorio: comEventos[0].relatorio,
      totalLinhas: rows.length,
      origemEscolhida: "relatorio-completo-com-eventos",
      eventosNaLista: comEventos[0].eventosNaLista,
      linhasComEventos: comEventos.length
    };
  }

  // Prioridade 2:
  // Só usar resumo quando não existir nenhum relatório completo.
  const comResumo = analisados
    .filter(item => item.temResumo)
    .sort((a, b) => b.timestamp - a.timestamp);

  if (comResumo.length) {
    return {
      row: comResumo[0].row,
      relatorio: comResumo[0].relatorio,
      totalLinhas: rows.length,
      origemEscolhida: "somente-resumo-sem-eventos",
      eventosNaLista: 0,
      linhasComEventos: 0
    };
  }

  return {
    row: null,
    relatorio: null,
    totalLinhas: rows.length,
    origemEscolhida: "nenhum-relatorio-valido",
    eventosNaLista: 0,
    linhasComEventos: 0
  };
}'''

s = replace_async_function(s, "obterUltimoRelatorioOficial", nova)

p.write_text(s)
PY

echo ""
echo "🔎 Verificando sintaxe..."
node --check lib/relatorio-oficial-supabase-cejas.js
node --check scripts/relatorio-oficial-restore-cejas.js
node --check scripts/start-seguro-cejas.js
node --check server.js

echo ""
echo "✅ Prioridade corrigida: agora o sistema escolhe o relatório com eventos completos."
echo ""
echo "Agora rode:"
echo "npm run relatorio:restore"
echo "npm start"
