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
- Render (deploy recomendado)

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

## 🌐 Deploy recomendado

### Por que o Vercel não é adequado
Este projeto é um backend Node.js/Express que usa `app.listen`, sessões, uploads de arquivos e lógica de servidor persistente. O Vercel funciona melhor com funções serverless, e não com um servidor Express completo.

### Opção 1: Hospedar o backend em Render / Railway / Fly.io
1. Crie um novo serviço Node.js.
2. Configure o repositório `central-cejas`.
3. Defina as variáveis de ambiente do backend: `SESSION_SECRET`, `ADMIN_EMAIL`, `ADMIN_PASSWORD_HASH`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` e `SUPABASE_STORAGE_BUCKET`.
4. Use o comando de build padrão e `npm start`.

Para a Agenda e o Painel do Dia carregarem dados do banco no Render, a variável essencial é `SUPABASE_SERVICE_ROLE_KEY`. Use a chave `service_role` do projeto Supabase, não a chave anon/publishable.

### Opção 2: Hospedar frontend estático + proxy Cloudflare Worker
- O backend continua rodando no Render/Railway.
- O Cloudflare Worker proxy envia `/api/*` para o backend.

#### Deploy do Worker proxy
```bash
npm install -g wrangler
wrangler login
wrangler secret put BACKEND_URL
wrangler deploy
```

- `BACKEND_URL` deve apontar para o URL público do backend, por exemplo `https://central-cejas-backend.onrender.com`.
- O Worker proxy roteia `/api/*` para esse backend.

### Deploy local
```bash
npm install
cp .env.example .env
# edite .env com as credenciais certas
npm start
```

Acesse: **http://localhost:5500**

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
- Verifique `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` no `.env` ou nas Environment Variables do Render.
- Se aparecer "Supabase não configurado" no Render, adicione a `SUPABASE_SERVICE_ROLE_KEY` e faça um novo deploy.
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
