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
