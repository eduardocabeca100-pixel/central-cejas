#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Preparando projeto CEJAS para subir no GitHub..."

if [ ! -f "package.json" ] || [ ! -f "server.js" ]; then
  echo "❌ Você precisa rodar este comando dentro da pasta raiz do projeto, onde ficam package.json e server.js."
  exit 1
fi

echo ""
echo "🧹 Garantindo que arquivos sensíveis não vão para o GitHub..."

cat > .gitignore <<'EOF'
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*

.env
.env.*
!.env.example
*.local

.DS_Store
Thumbs.db
.vscode/*
!.vscode/settings.json
*.swp
*.swo
*~

uploads/
.cejas-local-backups/
*.backup-*.html
*.backup-*.js
*.backup-*.json
.env.backup-*
diagnostico-*.zip

data/usuarios.json
data/redefinicoes-senha-local.json
data/chat-mensagens-local.json
data/relatorio-supera.json
data/relatorio-atual.json
data/ultimo-relatorio-texto-extraido.txt
data/agenda-manual-local.json
data/gratuidades-manuais.json
EOF

echo "✅ .gitignore atualizado."

echo ""
echo "🔎 Rodando verificação básica..."

if npm run check >/dev/null 2>&1; then
  npm run check
else
  echo "⚠️ npm run check não existe ou falhou. Continuando..."
fi

echo ""
echo "🧱 Inicializando Git, se necessário..."

if [ ! -d ".git" ]; then
  git init
fi

git branch -M main

echo ""
echo "🛡️ Removendo arquivos sensíveis do controle do Git, caso tenham entrado antes..."

git rm -r --cached .env .env.* uploads .cejas-local-backups data/usuarios.json data/redefinicoes-senha-local.json data/chat-mensagens-local.json data/relatorio-supera.json data/relatorio-atual.json data/ultimo-relatorio-texto-extraido.txt data/agenda-manual-local.json data/gratuidades-manuais.json 2>/dev/null || true

echo ""
echo "📦 Adicionando arquivos do projeto..."

git add .

echo ""
echo "📝 Criando commit..."

if git diff --cached --quiet; then
  echo "⚠️ Nenhuma alteração nova para commit."
else
  git commit -m "feat: atualiza sistema CEJAS com servidor inteligente, gratuidades e layout de orçamento"
fi

echo ""
echo "🌐 Configurando repositório remoto..."

DEFAULT_REMOTE="https://github.com/eduardocabeca100/central-cejas.git"

if git remote get-url origin >/dev/null 2>&1; then
  echo "✅ Remote origin já existe:"
  git remote get-url origin
else
  echo ""
  echo "Digite a URL do repositório GitHub."
  echo "Exemplo: https://github.com/eduardocabeca100/central-cejas.git"
  echo ""
  read -r -p "URL do GitHub [ENTER para usar $DEFAULT_REMOTE]: " GITHUB_URL

  if [ -z "$GITHUB_URL" ]; then
    GITHUB_URL="$DEFAULT_REMOTE"
  fi

  git remote add origin "$GITHUB_URL"
fi

echo ""
echo "⬆️ Subindo para o GitHub..."

git push -u origin main

echo ""
echo "✅ Projeto enviado para o GitHub com sucesso!"
echo ""
echo "Repositório:"
git remote get-url origin
