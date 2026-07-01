#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "package.json" ]; then
  echo "❌ Rode este comando dentro da pasta raiz do projeto, onde fica package.json."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
DESTINO="$HOME/Desktop/CEJAS-para-analise-TI-$STAMP"

echo "📁 Criando pasta para análise em:"
echo "$DESTINO"
echo ""

mkdir -p "$DESTINO"

echo "📦 Copiando arquivos do sistema..."

rsync -av \
  --exclude "node_modules" \
  --exclude ".git" \
  --exclude ".env" \
  --exclude ".env.*" \
  --exclude ".cejas-local-backups" \
  --exclude "backups-cejas" \
  --exclude "uploads/tmp-servidor-supabase" \
  --exclude "uploads/tmp" \
  --exclude "*.log" \
  --exclude ".DS_Store" \
  ./ "$DESTINO/"

echo ""
echo "🧾 Criando arquivo .env.EXEMPLO sem senhas..."

cat > "$DESTINO/.env.EXEMPLO" <<'EOF'
# Copiar este arquivo para .env apenas em ambiente local.
# NÃO colocar chaves reais em grupos de WhatsApp ou mensagens públicas.

PORT=5500

SESSION_SECRET=coloque-um-segredo-aqui

NEXT_PUBLIC_SUPABASE_URL=https://SEU-PROJETO.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sua-chave-publica-ou-anon

SUPABASE_SERVICE_ROLE_KEY=sua-service-role-key-privada
SUPABASE_STORAGE_BUCKET=servidor-cejas

ADMIN_EMAIL=seu-email-admin
ADMIN_PASSWORD_HASH=hash-da-senha-admin
EOF

echo ""
echo "🧪 Gerando diagnóstico técnico..."

{
  echo "DIAGNÓSTICO CEJAS"
  echo "Gerado em: $(date)"
  echo ""
  echo "Node:"
  node -v 2>/dev/null || true
  echo ""
  echo "NPM:"
  npm -v 2>/dev/null || true
  echo ""
  echo "Package scripts:"
  node -e 'const p=require("./package.json"); console.log(JSON.stringify(p.scripts||{}, null, 2))' 2>/dev/null || true
  echo ""
  echo "Arquivos principais:"
  find . -maxdepth 2 -type f \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./.cejas-local-backups/*" \
    ! -name ".env" \
    ! -name ".env.*" \
    | sort
} > "$DESTINO/DIAGNOSTICO-TECNICO.txt"

echo ""
echo "🔎 Verificando sintaxe dos arquivos principais..."

{
  echo "CHECK DE SINTAXE"
  echo "Gerado em: $(date)"
  echo ""

  for f in server.js lib/*.js scripts/*.js; do
    if [ -f "$f" ]; then
      echo "---- $f ----"
      node --check "$f" 2>&1 || true
      echo ""
    fi
  done
} > "$DESTINO/CHECK-SINTAXE.txt"

echo ""
echo "🗜️ Criando ZIP na Área de Trabalho..."

cd "$HOME/Desktop"
zip -qr "CEJAS-para-analise-TI-$STAMP.zip" "CEJAS-para-analise-TI-$STAMP"

echo ""
echo "✅ Pronto!"
echo ""
echo "Pasta criada:"
echo "$DESTINO"
echo ""
echo "ZIP criado:"
echo "$HOME/Desktop/CEJAS-para-analise-TI-$STAMP.zip"
echo ""
echo "⚠️ Importante:"
echo "- O .env real NÃO foi incluído."
echo "- node_modules NÃO foi incluído."
echo "- Seu amigo deve rodar npm install antes de testar."
echo "- Para testar, ele deve criar um .env local baseado no .env.EXEMPLO."
