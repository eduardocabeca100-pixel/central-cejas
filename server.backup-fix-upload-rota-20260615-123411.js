const express = require("express");
const session = require("express-session");
const bcrypt = require("bcryptjs");
const path = require("path");
const fs = require("fs");
require("dotenv").config();

const app = express();
const PORT = process.env.PORT || 5500;

const IDLE_SESSION_MS = 5 * 60 * 1000;

const DATA_DIR = path.join(__dirname, "data");
const ITEMS_FILE = path.join(DATA_DIR, "orcamento-itens.json");

function ensureDataFiles() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }

  if (!fs.existsSync(ITEMS_FILE)) {
    fs.writeFileSync(ITEMS_FILE, "[]", "utf8");
  }
}

function readJson(filePath) {
  ensureDataFiles();

  try {
    const raw = fs.readFileSync(filePath, "utf8");
    return JSON.parse(raw || "[]");
  } catch {
    return [];
  }
}

function writeJson(filePath, data) {
  ensureDataFiles();
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), "utf8");
}

function slugify(text) {
  return String(text || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

function normalizarAplicaRegras(valor) {
  return valor === true || valor === "true" || valor === "sim" || valor === "1";
}

function touchSession(req) {
  req.session.expiresAt = Date.now() + IDLE_SESSION_MS;
  req.session.cookie.maxAge = IDLE_SESSION_MS;
}

function remainingSessionMs(req) {
  if (!req.session || !req.session.expiresAt) return 0;
  return Math.max(0, req.session.expiresAt - Date.now());
}

function isPublicPath(req) {
  return (
    req.path === "/" ||
    req.path === "/login.html" ||
    req.path === "/api/login" ||
    req.path.startsWith("/assets/")
  );
}

function isAuthenticated(req, res, next) {
  if (isPublicPath(req)) return next();

  if (!req.session || !req.session.user) {
    if (req.path.startsWith("/api/")) {
      return res.status(401).json({ ok: false, message: "Sessão expirada." });
    }

    return res.redirect("/login.html");
  }

  if (remainingSessionMs(req) <= 0) {
    return req.session.destroy(() => {
      if (req.path.startsWith("/api/")) {
        return res.status(401).json({ ok: false, message: "Sessão expirada." });
      }

      return res.redirect("/login.html");
    });
  }

  next();
}

app.use(express.urlencoded({ extended: true }));
app.use(express.json());

app.use(
  session({
    secret: process.env.SESSION_SECRET || "troque-este-segredo",
    resave: false,
    saveUninitialized: false,
    rolling: false,
    cookie: {
      httpOnly: true,
      sameSite: "lax",
      secure: false,
      maxAge: IDLE_SESSION_MS
    }
  })
);

app.use(isAuthenticated);

app.get("/", (req, res) => {
  if (req.session.user) return res.redirect("/dashboard.html");
  return res.redirect("/login.html");
});

app.post("/api/login", async (req, res) => {
  const { email, senha } = req.body;

  const adminEmail = process.env.ADMIN_EMAIL;
  const adminPasswordHash = process.env.ADMIN_PASSWORD_HASH;

  if (!adminEmail || !adminPasswordHash) {
    return res.status(500).json({
      ok: false,
      message: "Login ADM ainda não foi configurado no servidor."
    });
  }

  const emailValido =
    String(email || "").trim().toLowerCase() === adminEmail.toLowerCase();

  const senhaValida = await bcrypt.compare(
    String(senha || ""),
    adminPasswordHash
  );

  if (!emailValido || !senhaValida) {
    return res.status(401).json({
      ok: false,
      message: "Email ou senha inválidos."
    });
  }

  req.session.user = {
    name: "Eduardo Cabeça",
    displayName: "EDUARDO CABEÇA",
    email: adminEmail,
    role: "Super Admin"
  };

  touchSession(req);

  return res.json({
    ok: true,
    redirect: "/dashboard.html",
    remainingMs: remainingSessionMs(req)
  });
});

app.get("/api/me", (req, res) => {
  return res.json({
    ok: true,
    user: req.session.user,
    remainingMs: remainingSessionMs(req)
  });
});

app.post("/api/touch", (req, res) => {
  touchSession(req);

  return res.json({
    ok: true,
    remainingMs: remainingSessionMs(req)
  });
});

app.get("/api/ping", (_req, res) => {
  res.json({ ok: true, message: "Servidor CEJAS ativo." });
});

app.get("/api/session-status", (req, res) => {
  return res.json({
    ok: true,
    remainingMs: remainingSessionMs(req)
  });
});

app.get("/api/orcamento-itens", (req, res) => {
  const itens = readJson(ITEMS_FILE);

  return res.json({
    ok: true,
    itens
  });
});

app.post("/api/orcamento-itens", (req, res) => {
  const { nome, categoria, detalhes, valor, unidade, status, aplicaRegras } = req.body;

  if (!nome || !categoria) {
    return res.status(400).json({
      ok: false,
      message: "Nome e categoria são obrigatórios."
    });
  }

  const itens = readJson(ITEMS_FILE);
  const baseId = slugify(nome);
  let id = baseId;
  let count = 1;

  while (itens.some((item) => item.id === id)) {
    id = `${baseId}-${count}`;
    count += 1;
  }

  const novoItem = {
    id,
    nome: String(nome).trim(),
    categoria: String(categoria).trim(),
    detalhes: String(detalhes || "").trim(),
    valor: Number(valor || 0),
    unidade: String(unidade || "unidade").trim(),
    status: status === "inativo" ? "inativo" : "ativo",
    aplicaRegras: normalizarAplicaRegras(aplicaRegras),
    criado_em: new Date().toISOString(),
    atualizado_em: new Date().toISOString()
  };

  itens.push(novoItem);
  writeJson(ITEMS_FILE, itens);

  return res.json({
    ok: true,
    item: novoItem
  });
});

app.put("/api/orcamento-itens/:id", (req, res) => {
  const { id } = req.params;
  const { nome, categoria, detalhes, valor, unidade, status, aplicaRegras } = req.body;

  const itens = readJson(ITEMS_FILE);
  const index = itens.findIndex((item) => item.id === id);

  if (index === -1) {
    return res.status(404).json({
      ok: false,
      message: "Item não encontrado."
    });
  }

  itens[index] = {
    ...itens[index],
    nome: String(nome || itens[index].nome).trim(),
    categoria: String(categoria || itens[index].categoria).trim(),
    detalhes: String(detalhes || "").trim(),
    valor: Number(valor || 0),
    unidade: String(unidade || "unidade").trim(),
    status: status === "inativo" ? "inativo" : "ativo",
    aplicaRegras: normalizarAplicaRegras(aplicaRegras),
    atualizado_em: new Date().toISOString()
  };

  writeJson(ITEMS_FILE, itens);

  return res.json({
    ok: true,
    item: itens[index]
  });
});

app.delete("/api/orcamento-itens/:id", (req, res) => {
  const { id } = req.params;

  const itens = readJson(ITEMS_FILE);
  const filtrados = itens.filter((item) => item.id !== id);

  if (filtrados.length === itens.length) {
    return res.status(404).json({
      ok: false,
      message: "Item não encontrado."
    });
  }

  writeJson(ITEMS_FILE, filtrados);

  return res.json({
    ok: true
  });
});

app.post("/api/logout", (req, res) => {
  req.session.destroy(() => {
    res.json({ ok: true, redirect: "/login.html" });
  });
});

app.use((error, _req, res, _next) => {
  console.error("Erro interno tratado pelo servidor:", error);

  return res.status(500).json({
    ok: false,
    message: error.message || "Erro interno ao processar arquivo."
  });
});

app.use(express.static(path.join(__dirname), { dotfiles: "deny" }));

app.listen(PORT, () => {
  console.log(`✅ Sistema de Gestão CEJAS rodando em http://localhost:${PORT}`);
});
