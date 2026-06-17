const express = require("express");
const { registrarAgendaDiaApi } = require("./lib/agenda-dia-api");
const { registrarAgendaPlusApi } = require("./lib/agenda-plus-api");
const { registrarRotasCejasFase2 } = require("./lib/cejas-fase2");
const { syncRelatorioAtualComSupabase } = require("./lib/sync-relatorio-supabase");
const session = require("express-session");
const bcrypt = require("bcryptjs");
const path = require("path");
const fs = require("fs");
const multer = require("multer");

async function parsePdfBuffer(buffer) {
  const pdfModule = require("pdf-parse");

  // pdf-parse versão nova: usa classe PDFParse
  if (pdfModule.PDFParse) {
    const parser = new pdfModule.PDFParse({ data: buffer });

    try {
      const result = await parser.getText();
      return {
        text: result.text || ""
      };
    } finally {
      if (typeof parser.destroy === "function") {
        await parser.destroy();
      }
    }
  }

  // pdf-parse versão antiga: exporta função direto ou default
  const parserFn = pdfModule.default || pdfModule;

  if (typeof parserFn === "function") {
    return await parserFn(buffer);
  }

  throw new Error("Formato do pacote pdf-parse não reconhecido.");
}




require("dotenv").config();

const app = express();

registrarAgendaDiaApi(app);


// Arquivo JS do Agenda Plus servido diretamente para evitar erro 404/MIME.
app.get("/js/agenda-plus.js", (_req, res) => {
  const arquivo = path.join(__dirname, "public", "js", "agenda-plus.js");

  if (!fs.existsSync(arquivo)) {
    return res.status(404).type("text/plain").send("agenda-plus.js não encontrado");
  }

  res.type("application/javascript");
  res.sendFile(arquivo);
});


app.use("/js", express.static(path.join(__dirname, "public", "js")));
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
app.use("/js", express.static(path.join(__dirname, "public/js")));
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
  try {
    const { email, senha } = req.body;
    const normalizedEmail = String(email || "").trim().toLowerCase();

    const adminEmail = process.env.ADMIN_EMAIL;
    const adminPasswordHash = process.env.ADMIN_PASSWORD_HASH;

    if (
      adminEmail &&
      adminPasswordHash &&
      normalizedEmail === adminEmail.toLowerCase() &&
      await bcrypt.compare(String(senha || ""), adminPasswordHash)
    ) {
      req.session.user = {
        id: "admin-eduardo",
        name: "Eduardo Cabeça",
        nome: "Eduardo Cabeça",
        displayName: "EDUARDO CABEÇA",
        email: adminEmail,
        role: "Super Admin",
        cargo: "Super Admin",
        tipo: "administrador",
        permissoes: ["*"]
      };

      if (typeof touchSession === "function") touchSession(req);

      return res.json({
        ok: true,
        redirect: "/dashboard.html",
        remainingMs: typeof remainingSessionMs === "function" ? remainingSessionMs(req) : null
      });
    }

    const users = readUsers();
    const user = users.find(item => {
      return item.email.toLowerCase() === normalizedEmail && item.status !== "inativo";
    });

    if (!user || !user.senhaHash) {
      return res.status(401).json({
        ok: false,
        message: "Email ou senha inválidos."
      });
    }

    const senhaValida = await bcrypt.compare(String(senha || ""), user.senhaHash);

    if (!senhaValida) {
      return res.status(401).json({
        ok: false,
        message: "Email ou senha inválidos."
      });
    }

    req.session.user = {
      id: user.id,
      name: user.nome,
      nome: user.nome,
      displayName: String(user.nome || "").toUpperCase(),
      email: user.email,
      role: user.cargo,
      cargo: user.cargo,
      tipo: user.tipo,
      permissoes: user.permissoes || []
    };

    if (typeof touchSession === "function") touchSession(req);

    return res.json({
      ok: true,
      redirect: "/dashboard.html",
      remainingMs: typeof remainingSessionMs === "function" ? remainingSessionMs(req) : null
    });
  } catch (error) {
    return res.status(500).json({
      ok: false,
      message: "Erro no login: " + error.message
    });
  }
});

app.get("/api/me", (req, res) => {
  return res.json({
    ok: true,
    user: req.session.user,
    remainingMs: typeof remainingSessionMs === "function" ? remainingSessionMs(req) : null
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


const RELATORIO_FILE = path.join(__dirname, "data", "relatorio-supera.json");
const RELATORIO_UPLOAD_DIR = path.join(__dirname, "uploads", "relatorios");

fs.mkdirSync(path.join(__dirname, "data"), { recursive: true });
fs.mkdirSync(RELATORIO_UPLOAD_DIR, { recursive: true });

const relatorioStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, RELATORIO_UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const safeName = Date.now() + "-" + String(file.originalname || "relatorio.pdf").replace(/[^a-zA-Z0-9._-]/g, "-");
    cb(null, safeName);
  }
});

const relatorioUpload = multer({
  storage: relatorioStorage,
  limits: {
    fileSize: 50 * 1024 * 1024
  }
});

function emptySuperaReport() {
  return {
    atualizadoEm: null,
    arquivo: null,
    resumo: {
      faturamentoPrevisto: 0,
      receitaConfirmada: 0,
      descontosAplicados: 0,
      eventosConfirmados: 0,
      eventosPendentes: 0,
      eventosCancelados: 0,
      totalEventos: 0
    },
    eventos: [],
    salas: [],
    produtos: []
  };
}

function dinheiroBR(valor) {
  if (!valor) return 0;

  const limpo = String(valor)
    .replace(/R\$/g, "")
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".");

  const numero = Number(limpo);
  return Number.isFinite(numero) ? numero : 0;
}

function detectarStatus(texto) {
  const t = String(texto || "").toLowerCase();

  if (t.includes("cancelado") || t.includes("cancelada")) return "cancelado";
  if (t.includes("em espera") || t.includes("espera") || t.includes("pendente")) return "em_espera";
  if (t.includes("confirmado") || t.includes("confirmada")) return "confirmado";

  return "em_espera";
}

function pegar(regex, texto) {
  const match = String(texto || "").match(regex);
  return match ? String(match[1] || "").trim() : "";
}



function valorBRParaNumero(valor) {
  if (!valor) return 0;

  const limpo = String(valor)
    .replace(/R\$/gi, "")
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".");

  const numero = Number(limpo);
  return Number.isFinite(numero) ? numero : 0;
}

function pegarPrimeiro(regex, texto) {
  const match = String(texto || "").match(regex);
  return match ? String(match[1] || "").trim() : "";
}

function dataPorExtensoParaBR(linha) {
  const meses = {
    janeiro: "01",
    fevereiro: "02",
    marco: "03",
    março: "03",
    abril: "04",
    maio: "05",
    junho: "06",
    julho: "07",
    agosto: "08",
    setembro: "09",
    outubro: "10",
    novembro: "11",
    dezembro: "12"
  };

  const texto = String(linha || "").toLowerCase();

  const match = texto.match(/(\d{1,2})\s+de\s+([a-zçãé]+)\s+de\s+(\d{4})/i);

  if (!match) return "";

  const dia = String(match[1]).padStart(2, "0");
  const mes = meses[match[2]] || "";
  const ano = match[3];

  return mes ? `${dia}/${mes}/${ano}` : "";
}

function ehCabecalhoDeData(linha) {
  return /^(segunda-feira|terça-feira|terca-feira|quarta-feira|quinta-feira|sexta-feira|sábado|sabado|domingo),?\s+/i.test(String(linha || ""));
}

function ehCabecalhoDeSala(linha) {
  return /^\d{2}\s*-\s+/.test(String(linha || "").trim());
}

function ehLinhaDeHorario(linha) {
  return /^Hor[aá]rio\s+\d{2}:\d{2}\s+At[eé]\s+\d{2}:\d{2}/i.test(String(linha || "").trim());
}

function limparLinhaRelatorio(linha) {
  return String(linha || "")
    .replace(/\s+/g, " ")
    .replace(/Mostrar todas as agendas/gi, "")
    .replace(/Mostrar agendamentos cancelados/gi, "")
    .replace(/Confirmado\s+Em espera\s+Cancelado/gi, "")
    .replace(/Exibir no Calendário WEB/gi, "")
    .trim();
}

function statusParaSistema(statusOriginal) {
  const status = String(statusOriginal || "").toUpperCase();

  if (status.includes("CANCELADO")) return "cancelado";
  if (status.includes("EM ESPERA")) return "em_espera";

  // No relatório do Supera, RESERVADO equivale ao evento confirmado/ativo.
  if (status.includes("RESERVADO")) return "confirmado";

  return "confirmado";
}

function extrairStatusEvento(bloco) {
  const texto = String(bloco || "");
  const encontrados = [...texto.matchAll(/\b(RESERVADO|EM ESPERA|CANCELADO)\b/gi)].map(m => m[1]);

  if (!encontrados.length) {
    return "confirmado";
  }

  return statusParaSistema(encontrados[encontrados.length - 1]);
}

function extrairValorEvento(bloco) {
  const texto = String(bloco || "");
  const encontrados = [...texto.matchAll(/Valor total di[aá]rio\.*:\s*([\d.]+,\d{2})/gi)].map(m => m[1]);

  if (!encontrados.length) return 0;

  return valorBRParaNumero(encontrados[encontrados.length - 1]);
}

function extrairDescontoEvento(bloco) {
  const texto = String(bloco || "");
  const encontrados = [...texto.matchAll(/DESCONTO\s+(-?[\d.]+,\d{2})/gi)].map(m => m[1]);

  return encontrados.reduce((acc, valor) => {
    return acc + Math.abs(valorBRParaNumero(valor));
  }, 0);
}

function extrairHorarioEvento(bloco) {
  const match = String(bloco || "").match(/Hor[aá]rio\s+(\d{2}:\d{2})\s+At[eé]\s+(\d{2}:\d{2})\s+Dura[cç][aã]o\s+(\d{2}:\d{2})\s+Servi[cç]os\s+Participantes:\s*(\d+)/i);

  return {
    horaInicial: match ? match[1] : "",
    horaFinal: match ? match[2] : "",
    duracao: match ? match[3] : "",
    participantes: match ? Number(match[4] || 0) : 0
  };
}

function extrairEmpresaEvento(linhas) {
  const linhaEmpresa = linhas.find((linha) => {
    return /\b(ASSOCIADA|NÃO ASSOCIADA|NAO ASSOCIADA)\b/i.test(linha);
  });

  if (!linhaEmpresa) return "";

  return linhaEmpresa
    .replace(/Valor total di[aá]rio.*$/i, "")
    .replace(/\s+\d+\s+[A-ZÁÉÍÓÚÃÕÇ .\/()-]+\s+[\d.]+,\d{2}.*$/i, "")
    .trim();
}

function linhaPareceItemFinanceiro(linha) {
  const texto = String(linha || "").trim();

  return (
    /^\d+\s+/.test(texto) ||
    /Valor total di[aá]rio/i.test(texto) ||
    /DESCONTO/i.test(texto) ||
    /Resp\.?:/i.test(texto) ||
    /\b(RESERVADO|CANCELADO|EM ESPERA)\b/i.test(texto) ||
    /\b(ASSOCIADA|NÃO ASSOCIADA|NAO ASSOCIADA)\b/i.test(texto)
  );
}

function extrairTituloEvento(linhas) {
  const candidatos = [];

  for (let i = 1; i < linhas.length; i++) {
    let linha = String(linhas[i] || "").trim();

    if (!linha) continue;

    if (linhaPareceItemFinanceiro(linha)) continue;

    linha = linha
      .replace(/Periodico:.*/i, "")
      .replace(/\s+\d+\s+[A-ZÁÉÍÓÚÃÕÇ .\/()-]+\s+[\d.]+,\d{2}.*$/i, "")
      .trim();

    if (!linha) continue;
    if (linha.length < 3) continue;

    candidatos.push(linha);
  }

  if (!candidatos.length) return "Evento sem descrição detectada";

  // Quando o título quebra em duas linhas, junta. Quando houver muitas observações,
  // pega as primeiras linhas mais prováveis.
  return candidatos.slice(0, 2).join(" ").trim();
}

function extrairProdutosEvento(bloco) {
  const texto = String(bloco || "");
  const produtos = [];

  const conhecidos = [
    "Água",
    "AGUA",
    "Copo",
    "COPOS",
    "Café",
    "CAFE",
    "Microfone",
    "Caixa de som",
    "Toalha",
    "Tampão",
    "LED",
    "Sonorização",
    "Movimentação",
    "Datashow",
    "Projetor",
    "Técnico de som",
    "TECNICO DE SOM"
  ];

  for (const produto of conhecidos) {
    if (new RegExp(produto, "i").test(texto)) {
      const nome = produto
        .replace("AGUA", "Água")
        .replace("CAFE", "Café")
        .replace("COPOS", "Copos")
        .replace("TECNICO DE SOM", "Técnico de som");

      produtos.push(nome);
    }
  }

  return [...new Set(produtos)];
}

function calcularResumoEventos(eventos) {
  return eventos.reduce(
    (acc, evento) => {
      acc.totalEventos += 1;

      if (evento.status === "confirmado") {
        acc.eventosConfirmados += 1;
        acc.receitaConfirmada += Number(evento.valor || 0);
        acc.faturamentoPrevisto += Number(evento.valor || 0);
      }

      if (evento.status === "em_espera") {
        acc.eventosPendentes += 1;
        acc.faturamentoPrevisto += Number(evento.valor || 0);
      }

      if (evento.status === "cancelado") {
        acc.eventosCancelados += 1;
      }

      acc.descontosAplicados += Number(evento.desconto || 0);

      return acc;
    },
    {
      faturamentoPrevisto: 0,
      receitaConfirmada: 0,
      descontosAplicados: 0,
      eventosConfirmados: 0,
      eventosPendentes: 0,
      eventosCancelados: 0,
      totalEventos: 0
    }
  );
}

function analisarTextoSupera(texto, arquivo) {
  const linhas = String(texto || "")
    .replace(/\r/g, "\n")
    .split(/\n+/)
    .map(limparLinhaRelatorio)
    .filter(Boolean);

  const eventos = [];

  let dataAtual = "";
  let salaAtual = "";
  let blocoAtual = null;

  function fecharEvento() {
    if (!blocoAtual) return;

    const linhasEvento = blocoAtual.linhas;
    const blocoTexto = linhasEvento.join("\n");
    const horario = extrairHorarioEvento(blocoTexto);

    const evento = {
      id: `evento-${eventos.length + 1}`,
      data: blocoAtual.data,
      sala: blocoAtual.sala,
      horaInicial: horario.horaInicial,
      horaFinal: horario.horaFinal,
      duracao: horario.duracao,
      participantes: horario.participantes,
      status: extrairStatusEvento(blocoTexto),
      empresa: extrairEmpresaEvento(linhasEvento),
      evento: extrairTituloEvento(linhasEvento),
      valor: extrairValorEvento(blocoTexto),
      desconto: extrairDescontoEvento(blocoTexto),
      produtos: extrairProdutosEvento(blocoTexto),
      blocoOriginal: blocoTexto
    };

    eventos.push(evento);
    blocoAtual = null;
  }

  for (const linha of linhas) {
    const dataCabecalho = ehCabecalhoDeData(linha) ? dataPorExtensoParaBR(linha) : "";

    if (dataCabecalho) {
      fecharEvento();
      dataAtual = dataCabecalho;
      continue;
    }

    if (ehCabecalhoDeSala(linha) && !ehLinhaDeHorario(linha)) {
      fecharEvento();
      salaAtual = linha;
      continue;
    }

    if (ehLinhaDeHorario(linha)) {
      fecharEvento();

      blocoAtual = {
        data: dataAtual,
        sala: salaAtual,
        linhas: [linha]
      };

      continue;
    }

    if (blocoAtual) {
      blocoAtual.linhas.push(linha);
    }
  }

  fecharEvento();

  const eventosLimpos = eventos
    .filter(evento => evento.data && evento.horaInicial)
    .filter((evento, index, lista) => {
      const chave = [
        evento.data,
        evento.sala,
        evento.horaInicial,
        evento.horaFinal,
        evento.evento,
        evento.empresa,
        evento.status
      ].join("|").toLowerCase();

      return lista.findIndex(outro => {
        const chaveOutro = [
          outro.data,
          outro.sala,
          outro.horaInicial,
          outro.horaFinal,
          outro.evento,
          outro.empresa,
          outro.status
        ].join("|").toLowerCase();

        return chaveOutro === chave;
      }) === index;
    })
    .sort((a, b) => {
      const da = a.data.split("/").reverse().join("-");
      const db = b.data.split("/").reverse().join("-");

      return da.localeCompare(db) || String(a.horaInicial).localeCompare(String(b.horaInicial));
    });

  const resumo = calcularResumoEventos(eventosLimpos);

  const salasMap = {};
  const produtosMap = {};

  for (const evento of eventosLimpos) {
    if (evento.sala) {
      salasMap[evento.sala] = salasMap[evento.sala] || {
        nome: evento.sala,
        quantidade: 0,
        valor: 0
      };

      salasMap[evento.sala].quantidade += 1;
      salasMap[evento.sala].valor += Number(evento.valor || 0);
    }

    for (const produto of evento.produtos || []) {
      produtosMap[produto] = produtosMap[produto] || {
        nome: produto,
        quantidade: 0
      };

      produtosMap[produto].quantidade += 1;
    }
  }

  return {
    atualizadoEm: new Date().toISOString(),
    arquivo,
    resumo,
    eventos: eventosLimpos,
    salas: Object.values(salasMap),
    produtos: Object.values(produtosMap),
    textoExtraido: String(texto || "").slice(0, 200000)
  };
}


app.get("/api/relatorio-atual", (_req, res) => {
  try {
    if (!fs.existsSync(RELATORIO_FILE)) {
      fs.writeFileSync(RELATORIO_FILE, JSON.stringify(emptySuperaReport(), null, 2));
    }

    const report = JSON.parse(fs.readFileSync(RELATORIO_FILE, "utf8"));

    res.json({
      ok: true,
      report
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar relatório: " + error.message
    });
  }
});

app.post("/api/importar-relatorio", relatorioUpload.single("relatorio"), async (req, res) => {
  try {
    console.log("📥 Upload recebido:", req.file?.originalname);

    if (!req.file) {
      return res.status(400).json({
        ok: false,
        message: "Nenhum PDF foi recebido pelo servidor."
      });
    }

    const buffer = fs.readFileSync(req.file.path);
    const parsed = await parsePdfBuffer(buffer);
    const texto = parsed.text || "";

    fs.writeFileSync(
      path.join(__dirname, "data", "ultimo-relatorio-texto-extraido.txt"),
      texto,
      "utf8"
    );

    console.log("📄 Caracteres extraídos do PDF:", texto.length);

    if (!texto.trim()) {
      return res.status(400).json({
        ok: false,
        message: "O PDF foi enviado, mas não foi possível extrair texto. Ele pode estar escaneado como imagem."
      });
    }

    const report = analisarTextoSupera(texto, req.file.originalname);

    fs.writeFileSync(RELATORIO_FILE, JSON.stringify(report, null, 2), "utf8");

    console.log("✅ Relatório processado:", report.resumo);
    console.log("📌 Eventos detectados:", report.eventos.length);
    console.log("📌 Eventos detectados:", report.eventos.length);
    console.log("📝 Texto salvo em data/ultimo-relatorio-texto-extraido.txt");

    res.json({
      ok: true,
      message: "Relatório importado com sucesso.",
      report
    });
  } catch (error) {
    console.error("❌ ERRO AO IMPORTAR PDF:", error);

    res.status(500).json({
      ok: false,
      message: "Erro ao importar PDF: " + (error.message || "erro desconhecido")
    });
  }
});



const USERS_FILE = path.join(__dirname, "data", "usuarios.json");

const PERMISSOES_DISPONIVEIS = [
  { id: "painel", nome: "Painel Geral" },
  { id: "agenda", nome: "Agenda Dinâmica" },
  { id: "orcamentos", nome: "Orçamentos" },
  { id: "relatorios", nome: "Importar Relatório PDF" },
  { id: "tarefas", nome: "Tarefas Pendentes" },
  { id: "servidor", nome: "Servidor de Arquivos" },
  { id: "financeiro", nome: "Financeiro" },
  { id: "usuarios", nome: "Acessos / Usuários" },
  { id: "configuracoes", nome: "Configurações" }
];

const PAGE_PERMISSION = {
  "/dashboard.html": "painel",
  "/agenda.html": "agenda",
  "/orcamentos.html": "orcamentos",
  "/importar-relatorio.html": "relatorios",
  "/tarefas.html": "tarefas",
  "/servidor.html": "servidor",
  "/financeiro.html": "financeiro",
  "/usuarios.html": "usuarios",
  "/configuracoes.html": "configuracoes"
};

function ensureUsersFile() {
  fs.mkdirSync(path.join(__dirname, "data"), { recursive: true });

  if (!fs.existsSync(USERS_FILE)) {
    const adminEmail = process.env.ADMIN_EMAIL || "marcel@cejas.com.br";

    const users = [
      {
        id: "admin-eduardo",
        nome: "Eduardo Cabeça",
        email: adminEmail,
        cargo: "Super Admin",
        tipo: "administrador",
        status: "ativo",
        permissoes: ["*"],
        senhaHash: null,
        criadoEm: new Date().toISOString(),
        atualizadoEm: new Date().toISOString()
      }
    ];

    fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2), "utf8");
  }
}

function readUsers() {
  ensureUsersFile();

  try {
    return JSON.parse(fs.readFileSync(USERS_FILE, "utf8"));
  } catch {
    return [];
  }
}

function writeUsers(users) {
  ensureUsersFile();
  fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2), "utf8");
}

function publicUser(user) {
  if (!user) return null;

  const { senhaHash, ...safe } = user;
  return safe;
}

function emailInstitucional(email) {
  return String(email || "").trim().toLowerCase().endsWith("@cejas.com.br");
}

function userHasPermission(user, permission) {
  if (!user) return false;
  if ((user.permissoes || []).includes("*")) return true;
  return (user.permissoes || []).includes(permission);
}

function requirePagePermission(req, res, next) {
  const permission = PAGE_PERMISSION[req.path];

  if (!permission) return next();

  if (!req.session || !req.session.user) {
    return res.redirect("/login.html");
  }

  if (!userHasPermission(req.session.user, permission)) {
    return res.status(403).send(`
      <body style="background:#050505;color:white;font-family:Arial;padding:40px;">
        <h1>Acesso negado</h1>
        <p>Seu usuário não possui permissão para acessar este módulo.</p>
        <a href="/dashboard.html" style="color:#ff61d2;">Voltar ao painel</a>
      </body>
    `);
  }

  next();
}

app.get("/api/permissoes", (_req, res) => {
  res.json({
    ok: true,
    permissoes: PERMISSOES_DISPONIVEIS
  });
});

app.get("/api/usuarios", (req, res) => {
  if (!userHasPermission(req.session.user, "usuarios")) {
    return res.status(403).json({
      ok: false,
      message: "Sem permissão para gerenciar usuários."
    });
  }

  const users = readUsers().map(publicUser);

  res.json({
    ok: true,
    usuarios: users
  });
});

app.post("/api/usuarios", async (req, res) => {
  try {
    if (!userHasPermission(req.session.user, "usuarios")) {
      return res.status(403).json({
        ok: false,
        message: "Sem permissão para criar usuários."
      });
    }

    const { nome, email, cargo, tipo, status, permissoes, senha } = req.body;

    if (!nome || !email) {
      return res.status(400).json({
        ok: false,
        message: "Nome e e-mail são obrigatórios."
      });
    }

    if (!emailInstitucional(email)) {
      return res.status(400).json({
        ok: false,
        message: "Use apenas e-mail institucional @cejas.com.br."
      });
    }

    if (!senha || String(senha).length < 6) {
      return res.status(400).json({
        ok: false,
        message: "Informe uma senha inicial com pelo menos 6 caracteres."
      });
    }

    const users = readUsers();
    const normalizedEmail = String(email).trim().toLowerCase();

    if (users.some(user => user.email.toLowerCase() === normalizedEmail)) {
      return res.status(400).json({
        ok: false,
        message: "Já existe usuário com este e-mail."
      });
    }

    const usuario = {
      id: "user-" + Date.now(),
      nome: String(nome).trim(),
      email: normalizedEmail,
      cargo: String(cargo || "Usuário").trim(),
      tipo: tipo === "administrador" ? "administrador" : "usuario",
      status: status === "inativo" ? "inativo" : "ativo",
      permissoes: tipo === "administrador" ? ["*"] : (Array.isArray(permissoes) ? permissoes : []),
      senhaHash: await bcrypt.hash(String(senha), 12),
      criadoEm: new Date().toISOString(),
      atualizadoEm: new Date().toISOString()
    };

    users.push(usuario);
    writeUsers(users);

    res.json({
      ok: true,
      usuario: publicUser(usuario)
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao criar usuário: " + error.message
    });
  }
});

app.put("/api/usuarios/:id", async (req, res) => {
  try {
    if (!userHasPermission(req.session.user, "usuarios")) {
      return res.status(403).json({
        ok: false,
        message: "Sem permissão para editar usuários."
      });
    }

    const { id } = req.params;
    const { nome, email, cargo, tipo, status, permissoes, senha } = req.body;

    const users = readUsers();
    const index = users.findIndex(user => user.id === id);

    if (index === -1) {
      return res.status(404).json({
        ok: false,
        message: "Usuário não encontrado."
      });
    }

    if (!emailInstitucional(email)) {
      return res.status(400).json({
        ok: false,
        message: "Use apenas e-mail institucional @cejas.com.br."
      });
    }

    const normalizedEmail = String(email).trim().toLowerCase();

    if (users.some(user => user.email.toLowerCase() === normalizedEmail && user.id !== id)) {
      return res.status(400).json({
        ok: false,
        message: "Já existe outro usuário com este e-mail."
      });
    }

    users[index] = {
      ...users[index],
      nome: String(nome || users[index].nome).trim(),
      email: normalizedEmail,
      cargo: String(cargo || users[index].cargo || "Usuário").trim(),
      tipo: tipo === "administrador" ? "administrador" : "usuario",
      status: status === "inativo" ? "inativo" : "ativo",
      permissoes: tipo === "administrador" ? ["*"] : (Array.isArray(permissoes) ? permissoes : []),
      atualizadoEm: new Date().toISOString()
    };

    if (senha && String(senha).length >= 6) {
      users[index].senhaHash = await bcrypt.hash(String(senha), 12);
    }

    writeUsers(users);

    res.json({
      ok: true,
      usuario: publicUser(users[index])
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao atualizar usuário: " + error.message
    });
  }
});

app.delete("/api/usuarios/:id", (req, res) => {
  if (!userHasPermission(req.session.user, "usuarios")) {
    return res.status(403).json({
      ok: false,
      message: "Sem permissão para excluir usuários."
    });
  }

  const { id } = req.params;
  const users = readUsers();

  const filtrados = users.filter(user => user.id !== id);

  if (filtrados.length === users.length) {
    return res.status(404).json({
      ok: false,
      message: "Usuário não encontrado."
    });
  }

  writeUsers(filtrados);

  res.json({
    ok: true
  });
});


app.use(requirePagePermission);


const SERVIDOR_DIR = path.join(__dirname, "uploads", "servidor");
fs.mkdirSync(SERVIDOR_DIR, { recursive: true });

const servidorUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 100 * 1024 * 1024,
    files: 1500
  }
});

function safeServidorPath(relativePath = "") {
  const cleaned = String(relativePath || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => part && part !== "." && part !== "..")
    .join("/");

  const finalPath = path.join(SERVIDOR_DIR, cleaned);

  if (!finalPath.startsWith(SERVIDOR_DIR)) {
    throw new Error("Caminho inválido.");
  }

  return finalPath;
}

function buildServidorTree(dirPath, relative = "") {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });

  return entries
    .filter(entry => !entry.name.startsWith("."))
    .map(entry => {
      const rel = path.join(relative, entry.name).replace(/\\/g, "/");
      const full = path.join(dirPath, entry.name);
      const stats = fs.statSync(full);

      if (entry.isDirectory()) {
        return {
          type: "folder",
          name: entry.name,
          path: rel,
          size: 0,
          updatedAt: stats.mtime,
          children: buildServidorTree(full, rel)
        };
      }

      return {
        type: "file",
        name: entry.name,
        path: rel,
        size: stats.size,
        updatedAt: stats.mtime
      };
    })
    .sort((a, b) => {
      if (a.type !== b.type) return a.type === "folder" ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
}

app.get("/api/servidor/tree", (_req, res) => {
  try {
    fs.mkdirSync(SERVIDOR_DIR, { recursive: true });

    res.json({
      ok: true,
      root: buildServidorTree(SERVIDOR_DIR)
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar servidor: " + error.message
    });
  }
});

app.post("/api/servidor/upload", servidorUpload.array("arquivos"), (req, res) => {
  try {
    const files = req.files || [];
    let paths = req.body.paths || [];

    if (!Array.isArray(paths)) {
      paths = [paths];
    }

    if (!files.length) {
      return res.status(400).json({
        ok: false,
        message: "Nenhum arquivo enviado."
      });
    }

    let saved = 0;

    files.forEach((file, index) => {
      const destino = String(req.body.destino || "").trim();
      const relativeFromClient = paths[index] || file.originalname;
      const finalRelativePath = destino
        ? path.join(destino, relativeFromClient).replace(/\\/g, "/")
        : relativeFromClient;

      const target = safeServidorPath(finalRelativePath);

      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, file.buffer);

      saved += 1;
    });

    res.json({
      ok: true,
      message: `${saved} arquivo(s) salvo(s) no servidor.`,
      saved
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao salvar arquivos: " + error.message
    });
  }
});


app.post("/api/servidor/criar-estrutura", (req, res) => {
  try {
    const { ano } = req.body;

    const year = String(ano || "").trim();

    if (!/^\d{4}$/.test(year)) {
      return res.status(400).json({
        ok: false,
        message: "Informe um ano válido com 4 dígitos."
      });
    }

    const meses = [
      "Janeiro",
      "Fevereiro",
      "Março",
      "Abril",
      "Maio",
      "Junho",
      "Julho",
      "Agosto",
      "Setembro",
      "Outubro",
      "Novembro",
      "Dezembro"
    ];

    const yearDir = safeServidorPath(year);
    fs.mkdirSync(yearDir, { recursive: true });

    meses.forEach((mes) => {
      fs.mkdirSync(path.join(yearDir, mes), { recursive: true });
    });

    res.json({
      ok: true,
      message: `Estrutura ${year}/Janeiro a Dezembro criada com sucesso.`
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao criar estrutura: " + error.message
    });
  }
});



app.post("/api/servidor/mover", (req, res) => {
  try {
    const { origem, destinoPasta } = req.body;

    if (!origem || !destinoPasta) {
      return res.status(400).json({
        ok: false,
        message: "Origem e destino são obrigatórios."
      });
    }

    const origemPath = safeServidorPath(origem);
    const destinoDir = safeServidorPath(destinoPasta);

    if (!fs.existsSync(origemPath)) {
      return res.status(404).json({
        ok: false,
        message: "Item de origem não encontrado."
      });
    }

    if (!fs.existsSync(destinoDir) || !fs.statSync(destinoDir).isDirectory()) {
      return res.status(400).json({
        ok: false,
        message: "Destino precisa ser uma pasta existente."
      });
    }

    if (origemPath === destinoDir || destinoDir.startsWith(origemPath + path.sep)) {
      return res.status(400).json({
        ok: false,
        message: "Não é possível mover uma pasta para dentro dela mesma."
      });
    }

    const baseName = path.basename(origemPath);
    let destinoFinal = path.join(destinoDir, baseName);

    if (fs.existsSync(destinoFinal)) {
      const ext = path.extname(baseName);
      const name = path.basename(baseName, ext);
      let count = 1;

      while (fs.existsSync(destinoFinal)) {
        destinoFinal = path.join(destinoDir, `${name}-${count}${ext}`);
        count++;
      }
    }

    fs.renameSync(origemPath, destinoFinal);

    res.json({
      ok: true,
      message: "Item movido com sucesso."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao mover item: " + error.message
    });
  }
});



const SERVIDOR_TMP_DIR = path.join(__dirname, "uploads", "tmp-servidor");
fs.mkdirSync(SERVIDOR_TMP_DIR, { recursive: true });

const servidorBulkUpload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, SERVIDOR_TMP_DIR),
    filename: (_req, file, cb) => {
      const safe = Date.now() + "-" + Math.random().toString(16).slice(2) + "-" + String(file.originalname || "arquivo").replace(/[^a-zA-Z0-9._-]/g, "-");
      cb(null, safe);
    }
  }),
  limits: {
    fileSize: 500 * 1024 * 1024,
    files: 5000
  }
});

function normalizarTextoServidor(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

const MESES_SERVIDOR = [
  { numero: "01", nome: "JANEIRO", aliases: ["JANEIRO", "JAN"] },
  { numero: "02", nome: "FEVEREIRO", aliases: ["FEVEREIRO", "FEV"] },
  { numero: "03", nome: "MARÇO", aliases: ["MARCO", "MARÇO", "MAR"] },
  { numero: "04", nome: "ABRIL", aliases: ["ABRIL", "ABR"] },
  { numero: "05", nome: "MAIO", aliases: ["MAIO", "MAI"] },
  { numero: "06", nome: "JUNHO", aliases: ["JUNHO", "JUN"] },
  { numero: "07", nome: "JULHO", aliases: ["JULHO", "JUL"] },
  { numero: "08", nome: "AGOSTO", aliases: ["AGOSTO", "AGO"] },
  { numero: "09", nome: "SETEMBRO", aliases: ["SETEMBRO", "SET"] },
  { numero: "10", nome: "OUTUBRO", aliases: ["OUTUBRO", "OUT"] },
  { numero: "11", nome: "NOVEMBRO", aliases: ["NOVEMBRO", "NOV"] },
  { numero: "12", nome: "DEZEMBRO", aliases: ["DEZEMBRO", "DEZ"] }
];

function pastaMesServidor(numeroMes) {
  const mes = MESES_SERVIDOR.find(item => item.numero === String(numeroMes).padStart(2, "0"));
  return mes ? `${mes.numero} ${mes.nome}` : "_MES_NAO_IDENTIFICADO";
}

function detectarAnoServidor(texto, anoPadrao) {
  const match = String(texto || "").match(/\b(20\d{2})\b/);
  return match ? match[1] : String(anoPadrao || new Date().getFullYear());
}

function detectarMesServidor(texto) {
  const original = String(texto || "");
  const normalizado = normalizarTextoServidor(original);

  for (const mes of MESES_SERVIDOR) {
    if (normalizado.includes(`${mes.numero} ${normalizarTextoServidor(mes.nome)}`)) return mes.numero;
    if (normalizado.includes(`${mes.numero}-${normalizarTextoServidor(mes.nome)}`)) return mes.numero;
    if (normalizado.includes(`${mes.numero}_${normalizarTextoServidor(mes.nome)}`)) return mes.numero;

    for (const alias of mes.aliases) {
      if (normalizado.includes(normalizarTextoServidor(alias))) return mes.numero;
    }
  }

  const dataCompleta = original.match(/\b(\d{1,2})[.\-_/](\d{1,2})[.\-_/](20\d{2}|\d{2})\b/);
  if (dataCompleta) return String(dataCompleta[2]).padStart(2, "0");

  const diaMes = original.match(/\b(\d{1,2})[.\-_/](\d{1,2})\b/);
  if (diaMes) return String(diaMes[2]).padStart(2, "0");

  const mesInicio = normalizado.match(/(?:^|\/|\s)(0?[1-9]|1[0-2])(?:\s|_|-|$)/);
  if (mesInicio) return String(mesInicio[1]).padStart(2, "0");

  return "";
}

function limparNomeEventoServidor(nome) {
  let base = String(nome || "")
    .replace(/\.[a-zA-Z0-9]{2,8}$/g, "")
    .replace(/\\/g, "/")
    .split("/")
    .pop();

  base = base
    .replace(/\b(20\d{2})\b/g, "")
    .replace(/\b\d{1,2}[.\-_/]\d{1,2}([.\-_/](20\d{2}|\d{2}))?\b/g, "")
    .replace(/\b(ORCAMENTO|ORÇAMENTO|BOLETO|DEMONSTRATIVO|RECIBO|COMPROVANTE|NF|NFS|NOTA|FISCAL|CONTRATO|PDF|DOC|DOCUMENTO)\b/gi, "")
    .replace(/[_\-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (!base || base.length < 3) return "_A_ORGANIZAR";

  return base.toUpperCase();
}

function segmentoEhAnoOuMesServidor(segmento) {
  const n = normalizarTextoServidor(segmento);

  if (/^20\d{2}$/.test(n)) return true;
  if (detectarMesServidor(segmento)) return true;
  if (["CEJAS", "AREA DE TRABALHO", "DESKTOP"].includes(n)) return true;

  return false;
}

function detectarNomeEventoServidor(relativePath, fileName) {
  const partes = String(relativePath || "")
    .replace(/\\/g, "/")
    .split("/")
    .filter(Boolean);

  const filePart = partes[partes.length - 1] || fileName;

  let indiceMes = -1;

  for (let i = 0; i < partes.length; i++) {
    if (detectarMesServidor(partes[i])) {
      indiceMes = i;
      break;
    }
  }

  if (indiceMes >= 0 && partes[indiceMes + 1] && partes[indiceMes + 1] !== filePart) {
    return limparNomeEventoServidor(partes[indiceMes + 1]);
  }

  const paisPossiveis = partes.slice(0, -1).filter(p => !segmentoEhAnoOuMesServidor(p));

  if (paisPossiveis.length) {
    return limparNomeEventoServidor(paisPossiveis[paisPossiveis.length - 1]);
  }

  return limparNomeEventoServidor(fileName || filePart);
}

function destinoInteligenteServidor(originalPath, fileName, anoPadrao) {
  const texto = `${originalPath || ""} ${fileName || ""}`;

  const ano = detectarAnoServidor(texto, anoPadrao);
  const mesNumero = detectarMesServidor(texto);
  const mes = mesNumero ? pastaMesServidor(mesNumero) : "_A_ORGANIZAR";
  const evento = mesNumero ? detectarNomeEventoServidor(originalPath, fileName) : "_A_ORGANIZAR";
  const nomeArquivo = String(fileName || path.basename(originalPath || "arquivo"))
    .replace(/[\\/:*?"<>|]/g, "-")
    .trim();

  return `${ano}/${mes}/${evento}/${nomeArquivo}`;
}

function caminhoUnicoServidor(target) {
  if (!fs.existsSync(target)) return target;

  const dir = path.dirname(target);
  const ext = path.extname(target);
  const name = path.basename(target, ext);

  let count = 1;
  let candidate = path.join(dir, `${name}-${count}${ext}`);

  while (fs.existsSync(candidate)) {
    count++;
    candidate = path.join(dir, `${name}-${count}${ext}`);
  }

  return candidate;
}

app.post("/api/servidor/upload-inteligente", servidorBulkUpload.array("arquivos"), (req, res) => {
  try {
    const files = req.files || [];
    let paths = req.body.paths || [];
    const anoPadrao = req.body.anoPadrao || "2026";

    if (!Array.isArray(paths)) paths = [paths];

    if (!files.length) {
      return res.status(400).json({
        ok: false,
        message: "Nenhum arquivo enviado."
      });
    }

    const salvos = [];
    const organizar = [];

    files.forEach((file, index) => {
      const originalRelative = paths[index] || file.originalname;
      const destinoRelativo = destinoInteligenteServidor(originalRelative, file.originalname, anoPadrao);
      const target = caminhoUnicoServidor(safeServidorPath(destinoRelativo));

      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.renameSync(file.path, target);

      salvos.push(destinoRelativo);

      if (destinoRelativo.includes("_A_ORGANIZAR")) {
        organizar.push(destinoRelativo);
      }
    });

    res.json({
      ok: true,
      saved: salvos.length,
      organizar: organizar.length,
      message: `${salvos.length} arquivo(s) organizados. ${organizar.length} foram para _A_ORGANIZAR.`
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro no upload inteligente: " + error.message
    });
  }
});


app.get("/api/servidor/arquivo", (req, res) => {
  try {
    const relativePath = req.query.path || "";
    const filePath = safeServidorPath(relativePath);

    if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
      return res.status(404).send("Arquivo não encontrado.");
    }

    res.sendFile(filePath);
  } catch (error) {
    res.status(500).send("Erro ao abrir arquivo.");
  }
});

app.delete("/api/servidor/item", (req, res) => {
  try {
    const relativePath = req.query.path || "";
    const itemPath = safeServidorPath(relativePath);

    if (!fs.existsSync(itemPath)) {
      return res.status(404).json({
        ok: false,
        message: "Item não encontrado."
      });
    }

    const stats = fs.statSync(itemPath);

    if (stats.isDirectory()) {
      fs.rmSync(itemPath, { recursive: true, force: true });
    } else {
      fs.unlinkSync(itemPath);
    }

    res.json({
      ok: true,
      message: "Item excluído com sucesso."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao excluir item: " + error.message
    });
  }
});


app.use(express.static(path.join(__dirname), { dotfiles: "deny" }));


// Sincronização automática do último relatório do Supera com o Supabase.
// Sempre que data/relatorio-supera.json for atualizado, o sistema envia o resumo e os eventos para o banco.
const RELATORIO_SUPERA_AUTO_SYNC_FILE = path.join(__dirname, "data", "relatorio-supera.json");
let relatorioAutoSyncTimer = null;
let relatorioAutoSyncUltimoMtime = 0;

function iniciarAutoSyncRelatorioSupabase() {
  try {
    fs.mkdirSync(path.join(__dirname, "data"), { recursive: true });

    fs.watchFile(RELATORIO_SUPERA_AUTO_SYNC_FILE, { interval: 1500 }, (curr) => {
      if (!curr || !curr.mtimeMs) return;
      if (curr.mtimeMs === relatorioAutoSyncUltimoMtime) return;

      relatorioAutoSyncUltimoMtime = curr.mtimeMs;

      clearTimeout(relatorioAutoSyncTimer);

      relatorioAutoSyncTimer = setTimeout(async () => {
        try {
          console.log("🔄 Novo relatório detectado. Sincronizando com Supabase...");

          const result = await syncRelatorioAtualComSupabase();

          if (result.ok) {
            console.log(`✅ Supabase atualizado: ${result.eventosInseridos} evento(s) enviados.`);
          } else {
            console.log("⚠️ Supabase não sincronizado:", result.message);
          }
        } catch (error) {
          console.error("❌ Erro na sincronização automática com Supabase:", error.message);
        }
      }, 1200);
    });

    console.log("✅ Auto Sync Supabase ativo para relatórios do Supera.");
  } catch (error) {
    console.log("⚠️ Auto Sync Supabase não iniciado:", error.message);
  }
}

iniciarAutoSyncRelatorioSupabase();



registrarRotasCejasFase2(app);





registrarAgendaPlusApi(app);




app.listen(PORT, () => {
  console.log(`✅ Sistema de Gestão CEJAS rodando em http://localhost:${PORT}`);
});
