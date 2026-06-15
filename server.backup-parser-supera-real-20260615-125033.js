const express = require("express");
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

  const match = String(linha || "")
    .toLowerCase()
    .match(/(\d{1,2})\s+de\s+([a-zçãé]+)\s+de\s+(\d{4})/i);

  if (!match) return "";

  const dia = String(match[1]).padStart(2, "0");
  const mes = meses[match[2]] || "";
  const ano = match[3];

  return mes ? `${dia}/${mes}/${ano}` : "";
}

function limparCabecalhosSupera(texto) {
  return String(texto || "")
    .replace(/Mostrar agendamentos cancelados/gi, "")
    .replace(/Confirmado\s+Em espera\s+Cancelado/gi, "")
    .replace(/Exibir no Calendário WEB/gi, "")
    .replace(/Valor de referência/gi, "")
    .replace(/Lançar para fatura/gi, "")
    .replace(/Lançar receita/gi, "")
    .replace(/Uso Interno/gi, "");
}

function statusDoEvento(bloco) {
  const t = limparCabecalhosSupera(bloco).toLowerCase();

  if (/\bsitua[cç][aã]o\s*[:\-]?\s*cancelad[oa]\b/.test(t) || /\bcancelad[oa]\b/.test(t)) {
    return "cancelado";
  }

  if (/\bem\s+espera\b/.test(t) || /\bpendente\b/.test(t) || /\bn[ãa]o\s+confirmad[oa]\b/.test(t)) {
    return "em_espera";
  }

  if (/\bsitua[cç][aã]o\s*[:\-]?\s*confirmad[oa]\b/.test(t) || /\bconfirmad[oa]\b/.test(t)) {
    return "confirmado";
  }

  return "em_espera";
}

function extrairSalaEvento(bloco) {
  const texto = String(bloco || "").replace(/\s+/g, " ").trim();

  const salaEvento = texto.match(/\b(\d{2}\s*-\s*[^-]+?)\s+-\s+([^]+?)(?:\s+Empresa:|\s+Respons[aá]vel:|\s+Obs\.?:|\s+Confirmado|\s+Em espera|\s+Cancelado|$)/i);

  if (salaEvento) {
    return {
      sala: salaEvento[1].trim(),
      evento: salaEvento[2].trim()
    };
  }

  const sala = 
    pegar(/(?:Sala|Agenda)\s*[:\-]\s*([^\n]+)/i, bloco) ||
    pegar(/\b(\d{2}\s*-\s*[^\n]+)/i, bloco) ||
    pegar(/(Auditório[^\n]+)/i, bloco) ||
    pegar(/(Salão[^\n]+)/i, bloco) ||
    pegar(/(Sala[^\n]+)/i, bloco);

  const evento =
    pegar(/Descrição do agendamento\s*[:\-]\s*([^\n]+)/i, bloco) ||
    pegar(/Descrição\s*[:\-]\s*([^\n]+)/i, bloco) ||
    pegar(/\b\d{2}\s*-\s*[^-]+?\s+-\s*([^\n]+)/i, bloco);

  return { sala, evento };
}

function blocoPareceEvento(bloco) {
  const t = String(bloco || "");

  const temSala = /\b\d{2}\s*-\s*/.test(t) || /\b(Sala|Auditório|Salão)\b/i.test(t);
  const temHora = /\b\d{2}:\d{2}\b/.test(t);
  const temEmpresa = /\bEmpresa\b/i.test(t);
  const temStatus = /\b(Confirmado|Em espera|Cancelado|Pendente)\b/i.test(t);

  return temSala || (temHora && (temEmpresa || temStatus));
}

function quebrarDiaEmEventos(dataAtual, linhasDoDia) {
  const blocos = [];
  let atual = [];

  function fecha() {
    if (!atual.length) return;

    const texto = atual.join("\n").trim();

    if (blocoPareceEvento(texto)) {
      blocos.push({
        data: dataAtual,
        texto
      });
    }

    atual = [];
  }

  for (const linha of linhasDoDia) {
    const l = linha.trim();

    const iniciaEvento =
      /\b\d{2}\s*-\s*/.test(l) ||
      /^\d{2}:\d{2}\b/.test(l) ||
      /\b\d{2}:\d{2}\b.*\b\d{2}\s*-\s*/.test(l);

    if (iniciaEvento && atual.length) {
      fecha();
    }

    atual.push(l);
  }

  fecha();

  return blocos;
}

function analisarTextoSupera(texto, arquivo) {
  const textoLimpo = limparCabecalhosSupera(texto);

  const linhas = String(textoLimpo || "")
    .replace(/\r/g, "\n")
    .split(/\n+/)
    .map(l => l.trim())
    .filter(Boolean);

  const blocos = [];

  // Estratégia 1: linhas/tabelas que já possuem data dd/mm/aaaa.
  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];
    const data = pegar(/(\d{2}\/\d{2}\/\d{4})/, linha);

    if (data && blocoPareceEvento(linha)) {
      const complemento = [
        linha,
        linhas[i + 1] || "",
        linhas[i + 2] || "",
        linhas[i + 3] || ""
      ].join("\n");

      blocos.push({
        data,
        texto: complemento
      });
    }
  }

  // Estratégia 2: páginas/agenda por dia com data por extenso.
  let dataAtual = "";
  let linhasDoDia = [];

  function fechaDia() {
    if (!dataAtual || !linhasDoDia.length) return;
    blocos.push(...quebrarDiaEmEventos(dataAtual, linhasDoDia));
    linhasDoDia = [];
  }

  for (const linha of linhas) {
    const dataExtenso = dataPorExtensoParaBR(linha);
    const dataNormal = pegar(/(\d{2}\/\d{2}\/\d{4})/, linha);

    const novaData = dataExtenso || dataNormal;

    if (novaData) {
      fechaDia();
      dataAtual = novaData;
      linhasDoDia = [linha];
    } else if (dataAtual) {
      linhasDoDia.push(linha);
    }
  }

  fechaDia();

  // Remove duplicados.
  const vistos = new Set();
  const eventos = [];

  for (const bloco of blocos) {
    const textoBloco = bloco.texto;
    const data = bloco.data || pegar(/(\d{2}\/\d{2}\/\d{4})/, textoBloco);

    if (!data) continue;

    const horas = textoBloco.match(/\b\d{2}:\d{2}\b/g) || [];
    const valores = textoBloco.match(/R\$\s?[\d.]+,\d{2}/g) || [];
    const valor = valores.length ? dinheiroBR(valores[valores.length - 1]) : 0;

    const { sala, evento } = extrairSalaEvento(textoBloco);

    const empresa =
      pegar(/Empresa\s*[:\-]\s*([^\n]+)/i, textoBloco) ||
      pegar(/Empresa\/Pessoa\s*[:\-]\s*([^\n]+)/i, textoBloco);

    const produtos = [];
    ["Água", "Copo", "Café", "Projetor", "Microfone", "LED", "Toalha", "Tampão", "Movimentação", "Sonorização", "Caixa de som", "Aquários"].forEach(p => {
      if (new RegExp(p, "i").test(textoBloco)) produtos.push(p);
    });

    const chave = [
      data,
      horas[0] || "",
      horas[1] || "",
      sala || "",
      evento || "",
      empresa || ""
    ].join("|").toLowerCase();

    if (vistos.has(chave)) continue;
    vistos.add(chave);

    eventos.push({
      id: "evento-" + eventos.length,
      data,
      horaInicial: horas[0] || "",
      horaFinal: horas[1] || "",
      status: statusDoEvento(textoBloco),
      empresa,
      evento: evento || "Evento sem descrição detectada",
      sala,
      valor,
      desconto: 0,
      produtos,
      blocoOriginal: textoBloco
    });
  }

  eventos.sort((a, b) => {
    const da = a.data.split("/").reverse().join("-");
    const db = b.data.split("/").reverse().join("-");
    return da.localeCompare(db) || String(a.horaInicial).localeCompare(String(b.horaInicial));
  });

  const resumo = {
    faturamentoPrevisto: 0,
    receitaConfirmada: 0,
    descontosAplicados: 0,
    eventosConfirmados: 0,
    eventosPendentes: 0,
    eventosCancelados: 0,
    totalEventos: eventos.length
  };

  eventos.forEach(e => {
    if (e.status === "confirmado") {
      resumo.eventosConfirmados++;
      resumo.receitaConfirmada += e.valor;
      resumo.faturamentoPrevisto += e.valor;
    }

    if (e.status === "em_espera") {
      resumo.eventosPendentes++;
      resumo.faturamentoPrevisto += e.valor;
    }

    if (e.status === "cancelado") {
      resumo.eventosCancelados++;
    }

    resumo.descontosAplicados += e.desconto || 0;
  });

  const salasMap = {};
  const produtosMap = {};

  eventos.forEach(e => {
    if (e.sala) {
      salasMap[e.sala] = salasMap[e.sala] || { nome: e.sala, quantidade: 0 };
      salasMap[e.sala].quantidade++;
    }

    (e.produtos || []).forEach(p => {
      produtosMap[p] = produtosMap[p] || { nome: p, quantidade: 0 };
      produtosMap[p].quantidade++;
    });
  });

  return {
    atualizadoEm: new Date().toISOString(),
    arquivo,
    resumo,
    eventos,
    salas: Object.values(salasMap),
    produtos: Object.values(produtosMap)
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


app.use(express.static(path.join(__dirname), { dotfiles: "deny" }));

app.listen(PORT, () => {
  console.log(`✅ Sistema de Gestão CEJAS rodando em http://localhost:${PORT}`);
});
