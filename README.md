# Central CEJAS - Sistema de Gestão Interno

Sistema completo de gestão empresarial com dashboard, agenda dinâmica, chat interno, orçamentos e controle financeiro.

## 🚀 Funcionalidades

- ✓ **Dashboard**: Painel geral com métricas
- ✓ **Agenda Dinâmica**: Calendário com visualização por dia/semana/mês
- ✓ **Chat Interno**: Comunicação entre usuários
- ✓ **Orçamentos**: Criação e gestão com geração de PDF
- ✓ **Financeiro**: Controle de boletos e demonstrativos
- ✓ **Tarefas**: Lista de tarefas pendentes
- ✓ **Servidor**: Gerenciamento de uploads
- ✓ **Contratos**: Gestão de documentos
- ✓ **Configurações**: Painel admin com permissões

## 📋 Requisitos

- Node.js 18+
- npm
- Supabase (banco de dados)
- Cloudflare (para deploy)

## 🔧 Instalação Local

```bash
# Clone e instale
git clone https://github.com/eduardocabeca100-pixel/central-cejas.git
cd central-cejas
npm install

# Configure variáveis
cp .env.example .env
nano .env  # Edite com suas credenciais

# Execute
npm run dev
```

Acesse: **http://localhost:5500**

## 🌐 Deploy no Cloudflare Pages

### Passo 1: Instale o Wrangler
```bash
npm install -g wrangler
```

### Passo 2: Faça Login
```bash
wrangler login
```

### Passo 3: Adicione Variáveis de Ambiente
```bash
wrangler secret put SUPABASE_URL
wrangler secret put SUPABASE_KEY
wrangler secret put SESSION_SECRET
```

### Passo 4: Deploy
```bash
wrangler deploy
```

### OU: Conexão GitHub Automática

1. Acesse: https://dash.cloudflare.com
2. Pages → Create a project → Connect to Git
3. Selecione: `eduardocabeca100-pixel/central-cejas`
4. Build command: `npm install`
5. Adicione as variáveis de ambiente
6. Deploy automático ao fazer push!

## 📁 Estrutura

```
central-cejas/
├── server.js                      # Servidor Express
├── package.json                   # Dependências
├── wrangler.toml                  # Config Cloudflare
├── lib/                           # Módulos backend
│   ├── financeiro-cejas.js        # Financeiro
│   ├── chat-cejas-api.js          # Chat
│   ├── agenda-dia-api.js          # Agenda
│   └── *.js                       # Outras APIs
├── js/                            # Frontend JavaScript
├── assets/                        # Imagens
├── *.html                         # Páginas principais
└── data/                          # Dados locais
```

## 🔐 Segurança

- Senhas com bcryptjs
- Sessões seguras
- Autenticação Supabase
- Controle de permissões por perfil

## 🐛 Troubleshooting

**Erro de Supabase?**
- Verifique SUPABASE_URL e SUPABASE_KEY no .env
- Teste: `curl -H "Authorization: Bearer $KEY" $URL/rest/v1/`

**Upload não funciona?**
- Verifique permissões em `uploads/`
- Limpe pasta temporária

**Performance no Cloudflare?**
- Ative cache para estáticos
- Comprima imagens
- Use CDN

## 📞 Suporte

Issues: https://github.com/eduardocabeca100-pixel/central-cejas/issues

---

**Desenvolvido com ❤️ para CEJAS**
