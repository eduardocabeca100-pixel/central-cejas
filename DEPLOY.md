# 🚀 Guia de Deploy - Central CEJAS

## ⚠️ Por que Vercel não funciona?

O Vercel é ideal para:
- Aplicações serverless (Next.js, static exports)
- Funções isoladas sem estado

**Este projeto NÃO é adequado para Vercel porque:**
- Usa `app.listen()` (servidor persistente)
- Mantém sessões em memória (`express-session`)
- Gerencia upload de arquivos
- Executa operações de longa duração (PDF parsing)

**Solução:** Backend persistente + Cloudflare Worker proxy

---

## 📋 Arquitetura Recomendada

```
┌─────────────────────────────────────────────────┐
│  Cliente (Frontend HTML/CSS/JS estático)       │
│  Serve: Dashboard, Agenda, Chat, etc           │
└────────────┬────────────────────────────────────┘
             │
             └─────────────────────────────────┐
                                               │
                    ┌──────────────────────────┴──────────────┐
                    │                                         │
         ┌──────────▼──────────┐          ┌─────────────────▼─────────┐
         │ Cloudflare Worker   │          │ Backend Node.js (Render)  │
         │ (Proxy /api/*)      │          │ Express + Sessions        │
         │ ┌─────────────────┐ │          │ ┌──────────────────────┐  │
         │ │ BACKEND_URL env │─┼──────────┼─│ localhost:5500       │  │
         │ └─────────────────┘ │          │ │ - Login/Auth         │  │
         └─────────────────────┘          │ - Agenda/Chat        │  │
                                          │ - PDF & Uploads      │  │
                                          │ - Supabase            │  │
                                          └──────────────────────┘  │
                                                                   │
         ┌────────────────────────────────────────────────────────┘
         │
    ┌────▼──────────────────┐
    │ Supabase (Database)   │
    │ Real-time Sync        │
    └───────────────────────┘
```

---

## 🔧 Passo 1: Host Backend em Render

### 1.1 Criar Serviço Node.js no Render

1. Acesse [render.com](https://render.com)
2. **New +** → **Web Service**
3. Conecte seu GitHub: `eduardocabeca100-pixel/central-cejas`
4. Configurar:
   - **Name:** `central-cejas-backend`
   - **Runtime:** Node
   - **Build Command:** `npm install`
   - **Start Command:** `npm start`
   - **Instance Type:** Free (ou Starter Pro)

### 1.2 Adicionar Variáveis de Ambiente

No Render dashboard:
```
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_SERVICE_ROLE_KEY=sua_chave_service_role
SUPABASE_ANON_KEY=sua_chave_anon_ou_publishable
SUPABASE_STORAGE_BUCKET=servidor-cejas
SESSION_SECRET=uma_chave_muito_segura_e_longa_aqui
CEJAS_PERSISTENT_DATA_DIR=/opt/render/project/src/uploads/.data
NODE_ENV=production
ADMIN_EMAIL=seu@email.com
ADMIN_PASSWORD_HASH=bcrypt_hash_da_senha_admin
```

No Render, nao defina `PORT` manualmente; a plataforma injeta essa variavel automaticamente. Use `PORT=5500` apenas no `.env` local.
O `CEJAS_PERSISTENT_DATA_DIR` usa o disco persistente montado em `uploads/` para manter os JSONs dinamicos entre redeploys.

### 1.3 Deploy

- Clique **Create Web Service**
- Render faz deploy automático em ~2 minutos
- Anote a URL pública: `https://central-cejas-backend.onrender.com`

---

## 🛡️ Passo 2: Configurar Cloudflare Worker Proxy

### 2.1 Instalar Wrangler

```bash
npm install -g wrangler
wrangler login
```

### 2.2 Adicionar Variável de Ambiente

```bash
wrangler secret put BACKEND_URL
# Cole a URL pública do Render, ex:
# https://central-cejas-backend.onrender.com
```

### 2.3 Deploy do Worker

```bash
wrangler deploy
```

- O arquivo `workers/proxy/index.js` já está configurado
- Worker agora roteia todas as requisições `/api/*` para o backend

---

## 🌐 Passo 3: Deploy Frontend Estático

### Opção A: Cloudflare Pages (Recomendado)

1. Acesse [dash.cloudflare.com](https://dash.cloudflare.com)
2. **Pages** → **Create project** → **Connect to Git**
3. Selecione: `eduardocabeca100-pixel/central-cejas`
4. **Build settings:**
   - Build command: `echo "Frontend estático"` (opcional)
   - Build output directory: `/` (raiz, pois os HTMLs já estão lá)
5. **Deploy**

### Opção B: GitHub Pages

1. Settings → Pages
2. Source: Deploy from a branch
3. Branch: `main`, folder: `/`
4. Salve

---

## ✅ Verificação de Deploy

### Local (teste antes de publicar)

```bash
cd ~/Desktop/central-cejas
npm install
cp .env.example .env
# edite .env com credenciais reais
npm start
# Acesse: http://localhost:5500
```

### URLs Públicas (após deploy)

- **Frontend:** `https://seu-domain.cloudflare.com` ou GitHub Pages
- **Backend:** `https://central-cejas-backend.onrender.com`
- **API:** Proxy Worker roteia automaticamente

---

## 🔐 Segurança

### Checklist

- [ ] `.env` nunca é commitado (verificado em `.gitignore`)
- [ ] `SESSION_SECRET` é uma string aleatória de 32+ caracteres
- [ ] Senha admin é armazenada como hash bcrypt em `ADMIN_PASSWORD_HASH`
- [ ] `SUPABASE_SERVICE_ROLE_KEY` é a chave **service_role** do Supabase
- [ ] `SUPABASE_ANON_KEY` é a chave **anon/publishable**
- [ ] CORS está configurado no Express (padrão aceita qualquer origem)

### Exemplo `.env` Real

```
SUPABASE_URL=https://xyzabc123.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...ServiceRoleSecret...
SUPABASE_ANON_KEY=eyJhbGc...AnonPublishable...
SUPABASE_STORAGE_BUCKET=servidor-cejas
SESSION_SECRET=j8x#$%kL9@!mNp2qR3sT4uV5wX6yZ7aB8cD9eF0gH1iJ2
NODE_ENV=production
ADMIN_EMAIL=admin@cejas.com.br
ADMIN_PASSWORD_HASH=$2b$10$... (bcrypt hash da senha)
```

---

## 🐛 Troubleshooting

### Erro 502 / 503 no Backend

```bash
# Verificar logs no Render
# Dashboard → Logs

# Testar localmente
npm start

# Verificar PORT está correto
echo $PORT  # deve ser 5500
```

### Worker proxy não encaminha `/api/*`

```bash
# Verificar BACKEND_URL
wrangler secret list

# Re-deploy
wrangler deploy
```

### Sessão não persiste

- Certifique-se que `SESSION_SECRET` é a mesma em todas as instâncias
- No Render, verifique variável de ambiente está definida
- Teste com: `curl http://localhost:5500/api/ping`

### CORS bloqueado

- Frontend está enviando requisição para `/api/...` (relativo)
- Worker proxy roteia para `BACKEND_URL/api/...`
- Erro CORS pode vir se BACKEND_URL não estiver correto

---

## 📦 Estrutura Final

```
central-cejas/
├── server.js                 ← Backend principal
├── package.json              ← Scripts: npm start
├── .env                      ← Credenciais (não commitado)
├── .env.example              ← Template
├── wrangler.toml             ← Config Cloudflare
├── workers/
│   └── proxy/index.js        ← Proxy /api/* → backend
├── README.md                 ← Instruções básicas
├── DEPLOY.md                 ← Este arquivo
├── lib/                      ← Módulos API
├── js/                       ← Frontend JavaScript
├── assets/                   ← Imagens
├── *.html                    ← Páginas (Dashboard, Agenda, etc)
└── uploads/                  ← Uploads de usuários (local)
```

---

## 🚀 Resumo dos Passos

1. **Backend:** Deploy no Render (auto-redeploy ao fazer push)
2. **Worker:** `wrangler secret put BACKEND_URL` + `wrangler deploy`
3. **Frontend:** Deploy no Cloudflare Pages (auto ao fazer push)
4. **Teste:** Acesse a URL pública, faça login, teste uma API

---

## 📞 URLs de Referência

- [Render Deployment](https://render.com/docs/deploy-node-express)
- [Cloudflare Workers](https://developers.cloudflare.com/workers/)
- [Cloudflare Pages](https://pages.cloudflare.com/)
- [Express Session](https://github.com/expressjs/session)

---

**Desenvolvido com ❤️ para CEJAS**
