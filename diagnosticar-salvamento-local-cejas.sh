#!/usr/bin/env bash
set -euo pipefail

OUT="DIAGNOSTICO-SALVAMENTO-LOCAL-CEJAS.txt"

echo "DIAGNÓSTICO DE SALVAMENTO LOCAL CEJAS" > "$OUT"
echo "Gerado em: $(date)" >> "$OUT"
echo "" >> "$OUT"

echo "=== localStorage ===" >> "$OUT"
grep -R "localStorage" -n . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=.cejas-local-backups \
  --exclude="$OUT" >> "$OUT" 2>/dev/null || true

echo "" >> "$OUT"
echo "=== sessionStorage ===" >> "$OUT"
grep -R "sessionStorage" -n . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=.cejas-local-backups \
  --exclude="$OUT" >> "$OUT" 2>/dev/null || true

echo "" >> "$OUT"
echo "=== fs.writeFile / writeFileSync ===" >> "$OUT"
grep -R "writeFile" -n . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=.cejas-local-backups \
  --exclude="$OUT" >> "$OUT" 2>/dev/null || true

echo "" >> "$OUT"
echo "=== data/ ===" >> "$OUT"
grep -R "data/" -n . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=.cejas-local-backups \
  --exclude="$OUT" >> "$OUT" 2>/dev/null || true

echo "" >> "$OUT"
echo "=== uploads/ ===" >> "$OUT"
grep -R "uploads" -n . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=.cejas-local-backups \
  --exclude="$OUT" >> "$OUT" 2>/dev/null || true

echo "" >> "$OUT"
echo "✅ Diagnóstico gerado em: $OUT"
cat "$OUT"
