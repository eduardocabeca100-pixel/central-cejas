const express = require("express");
const { registrarFinanceiroCejas } = require("./lib/financeiro-cejas");
const { registrarMenuPermissoesCejas } = require("./lib/menu-permissoes-cejas");
const { registrarChatCejasApi } = require("./lib/chat-cejas-api");
const { registrarConfiguracoesCejas } = require("./lib/configuracoes-cejas");
const { registrarOrcamentoPdfServidor } = require("./lib/orcamento-pdf-servidor");
const { registrarServidorPdfViewer } = require("./lib/servidor-pdf-viewer");
const { registrarDashboardPermissoesOrcamento } = require("./lib/dashboard-permissoes-orcamento");
const { registrarAgendaDiaLivre } = require("./lib/agenda-dia-livre");
const { registrarAgendaDiaApi } = require("./lib/agenda-dia-api");
const { registrarRotasCejasFase2 } = require("./lib/cejas-fase2");
const { syncRelatorioAtualComSupabase } = require("./lib/sync-relatorio-supabase");
const { iniciarProtecaoServidorSupabase, uploadBufferSupabaseServidor, uploadLocalFileSupabaseServidor, downloadBufferSupabaseServidor, moverSupabaseServidor, deletarSupabaseServidor, deletarPrefixoSupabaseServidor, listarStorageServidor } = require("./lib/servidor-storage-persistente");
const session = require("express-session");
const bcrypt = require("bcryptjs");
const path = require("path");
const { registrarDashboardRelatorioOficialCejas } = require("./lib/dashboard-relatorio-oficial-cejas");
const { registrarRotasSyncRelatorioCompleto } = require("./lib/relatorio-oficial-sync-cejas");
const { registrarRotasRelatorioOficialSupabase } = require("./lib/relatorio-oficial-supabase-cejas");
const { registrarRotasRelatoriosSuperaStorage } = require("./lib/relatorios-supera-storage-cejas");
const { registrarUploadLotePathsServidorCejas } = require("./lib/servidor-upload-lote-paths-cejas");
const { registrarUploadZipServidorCejas } = require("./lib/servidor-upload-zip-cejas");
const { syncDataParaSupabase } = require("./lib/dados-supabase-cejas");
const { registrarRotasServidorSupabaseDefinitivo } = require("./lib/servidor-supabase-definitivo");
const { getSupabaseEnvStatus } = require("./lib/supabase");

const persistenciaTotalCejas = require("./lib/persistencia-total-supabase");
const fs = require("fs");
const { aplicarPatchWriteFileJsonStore, syncJsonsParaSupabase } = require("./lib/json-store-supabase-cejas");
const multer = require("multer");
const { prepararDadosPersistentes } = require("./lib/render-persistent-data");

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
prepararDadosPersistentes(__dirname);

aplicarPatchWriteFileJsonStore();
const app = express();
registrarDashboardRelatorioOficialCejas(app);
registrarRotasSyncRelatorioCompleto(app);
registrarRotasRelatorioOficialSupabase(app);
registrarRotasRelatoriosSuperaStorage(app);
registrarUploadLotePathsServidorCejas(app);
registrarUploadZipServidorCejas(app);

// CEJAS_JSON_STORE_API_START
app.post("/api/sistema/json-sync", async (_req, res) => {
  try {
    const result = await syncJsonsParaSupabase();
    res.json({ ok: true, ...result });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});
// CEJAS_JSON_STORE_API_END



// CEJAS_RECEITA_MENSAL_API_START
app.get("/api/cejas/receita-mensal", async (_req, res) => {
  try {
    const fs = require("fs");
    const path = require("path");

    const DATA_DIR = path.join(__dirname, "data");

    function numeroBR(valor) {
      if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

      const texto = String(valor || "")
        .replace(/R\$/gi, "")
        .replace(/\s/g, "")
        .replace(/\./g, "")
        .replace(",", ".");

      const numero = Number(texto);
      return Number.isFinite(numero) ? numero : 0;
    }

    function dataISO(valor) {
      const texto = String(valor || "").trim();

      if (/^\d{4}-\d{2}-\d{2}/.test(texto)) return texto.slice(0, 10);

      let m = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/);
      if (m) return `${m[3]}-${String(m[2]).padStart(2, "0")}-${String(m[1]).padStart(2, "0")}`;

      m = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2})\b/);
      if (m) return `20${m[3]}-${String(m[2]).padStart(2, "0")}-${String(m[1]).padStart(2, "0")}`;

      return "";
    }

    function statusConfirmado(item) {
      const status = String(
        item.status ||
        item.situacao ||
        item.estado ||
        item.confirmacao ||
        item.statusEvento ||
        ""
      ).toUpperCase();

      if (!status) return false;

      return status.includes("CONFIRM") ||
        status.includes("LIBERAD") ||
        status.includes("REALIZAD") ||
        status.includes("APROVAD");
    }

    function valorEvento(item) {
      const campos = [
        item.receitaConfirmada,
        item.valorConfirmado,
        item.valorPago,
        item.valorFinal,
        item.valorTotal,
        item.total,
        item.valor,
        item.preco
      ];

      for (const campo of campos) {
        const n = numeroBR(campo);
        if (n > 0) return n;
      }

      return 0;
    }

    function dataEvento(item) {
      return dataISO(
        item.dataISO ||
        item.data ||
        item.dataEvento ||
        item.inicio ||
        item.start ||
        item.date ||
        ""
      );
    }

    function pareceEvento(item) {
      if (!item || typeof item !== "object" || Array.isArray(item)) return false;

      return Boolean(
        item.evento ||
        item.nomeEvento ||
        item.titulo ||
        item.title ||
        item.sala ||
        item.local ||
        item.data ||
        item.dataEvento ||
        item.valorTotal ||
        item.receitaConfirmada ||
        item.valorConfirmado
      );
    }

    function extrairEventos(obj, lista = []) {
      if (!obj) return lista;

      if (Array.isArray(obj)) {
        obj.forEach(item => extrairEventos(item, lista));
        return lista;
      }

      if (typeof obj !== "object") return lista;

      if (pareceEvento(obj)) lista.push(obj);

      Object.values(obj).forEach(value => {
        if (value && typeof value === "object") extrairEventos(value, lista);
      });

      return lista;
    }

    function listarJson(dir, result = []) {
      if (!fs.existsSync(dir)) return result;

      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);

        if (entry.isDirectory()) listarJson(full, result);
        else if (entry.isFile() && entry.name.endsWith(".json")) result.push(full);
      }

      return result;
    }

    const arquivos = listarJson(DATA_DIR);
    const eventos = [];

    for (const file of arquivos) {
      try {
        const json = JSON.parse(fs.readFileSync(file, "utf8"));
        extrairEventos(json, eventos);
      } catch {}
    }

    const porMes = {};
    let totalConfirmado = 0;
    let qtdConfirmados = 0;

    for (const ev of eventos) {
      if (!statusConfirmado(ev)) continue;

      const iso = dataEvento(ev);
      const valor = valorEvento(ev);

      if (!iso || !valor) continue;

      const key = iso.slice(0, 7);

      porMes[key] = porMes[key] || {
        key,
        valor: 0,
        quantidade: 0
      };

      porMes[key].valor += valor;
      porMes[key].quantidade += 1;

      totalConfirmado += valor;
      qtdConfirmados += 1;
    }

    const nomes = [
      "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
      "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    ];

    let meses = Object.values(porMes)
      .sort((a, b) => a.key.localeCompare(b.key))
      .map(item => {
        const [ano, mes] = item.key.split("-");
        return {
          ...item,
          mes: nomes[Number(mes) - 1] || item.key,
          mesCurto: (nomes[Number(mes) - 1] || item.key).slice(0, 3),
          ano
        };
      });

    res.set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");

    res.json({
      ok: true,
      meses,
      totalConfirmado,
      qtdConfirmados,
      arquivosLidos: arquivos.length,
      eventosEncontrados: eventos.length,
      atualizadoEm: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_RECEITA_MENSAL_API_END


// CEJAS_SYNC_DATA_SUPABASE_START
app.use((req, res, next) => {
  const mudaDados = ["POST", "PUT", "PATCH", "DELETE"].includes(req.method);
  const rotasData = [
    "/api/importar-relatorio",
    "/api/relatorio",
    "/api/dashboard",
    "/api/gratuidades",
    "/api/agenda",
    "/api/tarefas",
    "/api/configuracoes"
  ];

  if (mudaDados && rotasData.some(prefix => req.path.startsWith(prefix))) {
    res.on("finish", () => {
      if (res.statusCode < 400) {
        setTimeout(() => {
          syncDataParaSupabase().catch(error => {
            console.warn("⚠️ Sync data/ pós alteração falhou:", error.message);
          });
        }, 1200);
      }
    });
  }

  next();
});

app.post("/api/sistema/sync-data", async (_req, res) => {
  try {
    const result = await syncDataParaSupabase();
    res.json({ ok: true, ...result });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});
// CEJAS_SYNC_DATA_SUPABASE_END


registrarRotasServidorSupabaseDefinitivo(app);

// CEJAS_SERVIDOR_API_PING_START
app.get("/api/servidor/ping", (_req, res) => {
  res.set("Cache-Control", "no-store");
  res.json({
    ok: true,
    message: "API do servidor ativa",
    at: new Date().toISOString()
  });
});
// CEJAS_SERVIDOR_API_PING_END


// CEJAS_DEBUG_STORAGE_RUNTIME_START
app.get("/api/debug/storage-runtime", (_req, res) => {
  try {
    const { getSupabaseRuntimeStatus } = require("./lib/servidor-supabase-definitivo");

    res.json({
      ok: true,
      storage: getSupabaseRuntimeStatus()
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_DEBUG_STORAGE_RUNTIME_END
// CEJAS_PERSISTENCIA_TOTAL_DEPLOY_START
const CEJAS_ROTAS_QUE_SALVAM_DADOS = [
  "/api/servidor",
  "/api/gratuidades",
  "/api/importar-relatorio",
  "/api/relatorio",
  "/api/agenda",
  "/api/tarefas",
  "/api/usuarios",
  "/api/configuracoes",
  "/api/chat",
  "/api/orcamentos",
  "/api/financeiro"
];

app.use((req, res, next) => {
  const metodoMudaDados = ["POST", "PUT", "PATCH", "DELETE"].includes(req.method);
  const rotaMudaDados = CEJAS_ROTAS_QUE_SALVAM_DADOS.some(prefix => req.path.startsWith(prefix));

  if (metodoMudaDados && rotaMudaDados) {
    res.on("finish", () => {
      if (res.statusCode < 400) {
        setTimeout(() => {
          persistenciaTotalCejas.syncTudoCejas("auto").catch((error) => {
            console.warn("⚠️ Sync automático pós-alteração falhou:", error.message);
          });
        }, 1200);
      }
    });
  }

  next();
});

app.get("/api/persistencia/status", async (_req, res) => {
  try {
    const status = await persistenciaTotalCejas.statusPersistenciaCejas();
    res.json(status);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});

app.post("/api/persistencia/sync", async (_req, res) => {
  try {
    const result = await persistenciaTotalCejas.syncTudoCejas("api");
    res.json(result);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});

app.post("/api/persistencia/restore", async (_req, res) => {
  try {
    const result = await persistenciaTotalCejas.restoreTudoCejas("api");
    res.json(result);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
});
// CEJAS_PERSISTENCIA_TOTAL_DEPLOY_END




// CEJAS_STATIC_JS_ROOT
app.use("/js", express.static(require("path").join(__dirname, "js")));
app.use("/assets", express.static(require("path").join(__dirname, "assets")));
app.use("/uploads", express.static(require("path").join(__dirname, "uploads")));













app.use("/assets", express.static(require("path").join(__dirname, "assets")));









app.use("/js", express.static(require("path").join(__dirname, "js")));
app.use("/uploads", express.static(require("path").join(__dirname, "uploads")));




// CEJAS_FIX_RELATORIO_DELETE_START
// Não responder vazio aqui: deixa a rota principal tentar carregar local ou Supabase.
app.get("/api/relatorio-atual", (_req, _res, next) => next());

app.delete("/api/relatorio-atual", async (_req, res) => {
  const fs = require("fs");
  const path = require("path");

  const removidos = [];
  const erros = [];

  function removerArquivo(caminho) {
    try {
      if (fs.existsSync(caminho)) {
        fs.rmSync(caminho, { recursive: true, force: true });
        removidos.push(path.relative(__dirname, caminho));
      }
    } catch (error) {
      erros.push({ caminho: path.relative(__dirname, caminho), erro: error.message });
    }
  }

  [
    path.join(__dirname, "data", "relatorio-supera.json"),
    path.join(__dirname, "data", "ultimo-relatorio-texto-extraido.txt"),
    path.join(__dirname, "data", "relatorio-atual.json")
  ].forEach(removerArquivo);

  [
    path.join(__dirname, "uploads", "relatorios"),
    path.join(__dirname, "uploads", "supera"),
    path.join(__dirname, "uploads", "importar-relatorio")
  ].forEach(removerArquivo);

  try {
    const { supabaseAdmin, isSupabaseConfigured } = require("./lib/supabase");

    if (isSupabaseConfigured && isSupabaseConfigured() && supabaseAdmin) {
      // Primeiro tenta apagar eventos vinculados a relatórios.
      try {
        const rels = await supabaseAdmin
          .from("cejas_relatorios")
          .select("id");

        const ids = (rels.data || []).map((r) => r.id).filter(Boolean);

        if (ids.length) {
          await supabaseAdmin
            .from("cejas_eventos")
            .delete()
            .in("relatorio_id", ids);
        }
      } catch (error) {
        erros.push({ supabase: "cejas_eventos por relatorio_id", erro: error.message });
      }

      // Depois tenta apagar eventos do Supera pela origem.
      try {
        await supabaseAdmin
          .from("cejas_eventos")
          .delete()
          .eq("origem", "supera");
      } catch (error) {
        erros.push({ supabase: "cejas_eventos origem supera", erro: error.message });
      }

      // Remove os relatórios salvos para não sobrecarregar.
      try {
        await supabaseAdmin
          .from("cejas_relatorios")
          .delete()
          .neq("id", "00000000-0000-0000-0000-000000000000");
      } catch (error) {
        erros.push({ supabase: "cejas_relatorios", erro: error.message });
      }
    }
  } catch (error) {
    erros.push({ supabase: "conexao", erro: error.message });
  }

  // CEJAS_RECRIAR_PASTA_RELATORIOS_APOS_DELETE
  try {
    fs.mkdirSync(path.join(__dirname, "uploads", "relatorios"), { recursive: true });
  } catch {}

  return res.json({
    ok: true,
    message: "Relatório atual apagado com sucesso.",
    removidos,
    erros,
    resumo: {
      faturamentoPrevisto: 0,
      receitaConfirmada: 0,
      descontos: 0,
      totalEventos: 0,
      confirmados: 0,
      emEspera: 0,
      cancelados: 0
    },
    eventos: []
  });
});
// CEJAS_FIX_RELATORIO_DELETE_END







// Força a tela Configurações 2.0, evitando cache/rota antiga.
app.get("/configuracoes.html", (_req, res) => {
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
  res.sendFile(require("path").join(__dirname, "configuracoes.html"));
});




// Proteção CEJAS: somente Superadmin pode excluir arquivos/pastas do Servidor.
// Essa proteção envolve todas as rotas DELETE /api/servidor...
function cejasUsuarioSessaoParaExclusao(req) {
  const sessao = req.session || {};
  const usuario = sessao.usuario || sessao.user || sessao.admin || {};

  return {
    email:
      usuario.email ||
      sessao.email ||
      sessao.userEmail ||
      sessao.adminEmail ||
      null,
    tipo:
      usuario.tipo ||
      usuario.tipo_usuario ||
      usuario.role ||
      sessao.tipo ||
      null,
    permissoes:
      usuario.permissoes ||
      usuario.permissions ||
      sessao.permissoes ||
      []
  };
}

function cejasEhSuperadmin(req) {
  const usuario = cejasUsuarioSessaoParaExclusao(req);

  if (process.env.ADMIN_EMAIL && usuario.email === process.env.ADMIN_EMAIL) return true;
  if (usuario.tipo === "superadmin" || usuario.tipo === "admin_master") return true;
  if (Array.isArray(usuario.permissoes) && usuario.permissoes.includes("*")) return true;

  return false;
}

const cejasOriginalDelete = app.delete.bind(app);

app.delete = function(route, ...handlers) {
  if (String(route).startsWith("/api/servidor")) {
    return cejasOriginalDelete(route, (req, res, next) => {
      if (!cejasEhSuperadmin(req)) {
        return res.status(403).json({
          ok: false,
          message: "Somente o Superadmin pode excluir arquivos ou pastas do servidor."
        });
      }

      next();
    }, ...handlers);
  }

  return cejasOriginalDelete(route, ...handlers);
};

// Bloqueia o fluxo antigo que salvava orçamento em JSON.
app.post("/api/orcamentos/auto-salvar-servidor", (_req, res) => {
  return res.status(410).json({
    ok: false,
    message: "Fluxo antigo desativado. Orçamentos agora devem ser salvos somente em PDF."
  });
});



registrarAgendaDiaLivre(app, express);





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

const IDLE_SESSION_MS = 8 * 60 * 60 * 1000;

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
  const p = String(req.path || req.url || "").split("?")[0];

  return (
    p === "/" ||
    p === "/login.html" ||
    p === "/api/login" ||
    p === "/favicon.ico" ||
    p.startsWith("/assets/") ||
    p.startsWith("/js/") ||
    p.startsWith("/css/") ||
    p.startsWith("/public/")
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

app.use(express.urlencoded({ extended: true, limit: "60mb" }));
app.use("/js", express.static(path.join(__dirname, "public/js")));
app.use(express.json({ limit: "60mb" }));

// Login público precisa vir antes das proteções




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

// Financeiro / Faturamento CEJAS
registrarFinanceiroCejas(app);

// Financeiro / Faturamento CEJAS


// Menu/permissões precisa vir depois da sessão para reconhecer Superadmin
registrarMenuPermissoesCejas(app);

app.get("/", (req, res) => {
  if (req.session.user) return res.redirect("/dashboard.html");
  return res.redirect("/login.html");
});

app.post("/api/login", async (req, res) => {
  try {
    const { email, senha, lembrar } = req.body;
    const normalizedEmail = String(email || "").trim().toLowerCase();

    if (!normalizedEmail.endsWith("@cejas.com.br")) {
      return res.status(403).json({
        ok: false,
        message: "Use apenas e-mail institucional @cejas.com.br."
      });
    }

    const adminEmail = String(process.env.ADMIN_EMAIL || "").trim().toLowerCase();
    const adminPasswordHash = process.env.ADMIN_PASSWORD_HASH;
    const maxAge = lembrar ? 1000 * 60 * 60 * 24 * 30 : IDLE_SESSION_MS;

    if (
      adminEmail &&
      adminPasswordHash &&
      normalizedEmail === adminEmail &&
      await bcrypt.compare(String(senha || ""), adminPasswordHash)
    ) {
      req.session.user = {
        id: "admin-eduardo",
        name: "Eduardo",
        nome: "Eduardo",
        displayName: "EDUARDO",
        email: adminEmail,
        role: "Superadmin",
        cargo: "Superadmin",
        tipo: "superadmin",
        permissoes: ["*"],
        permissions: ["*"],
        superadmin: true,
        admin: true,
        isSuperAdmin: true,
        isAdmin: true,
        tipo: "superadmin"
      };

      req.session.usuario = req.session.user;
      req.session.currentUser = req.session.user;
      req.session.authUser = req.session.user;
      req.session.usuarioAtual = req.session.user;
      req.session.usuarioLogado = req.session.user;

      req.session.email = req.session.user.email;
      req.session.nome = req.session.user.nome;
      req.session.name = req.session.user.nome;
      req.session.cargo = req.session.user.cargo;
      req.session.role = req.session.user.cargo;
      req.session.tipo = "superadmin";

      req.session.permissoes = ["*"];
      req.session.permissions = ["*"];

      req.session.superadmin = true;
      req.session.admin = true;
      req.session.isSuperAdmin = true;
      req.session.isAdmin = true;
      req.session.logado = true;
      req.session.loggedIn = true;
      req.session.isLoggedIn = true;
      req.session.autenticado = true;
      req.session.authenticated = true;
      req.session.isAuthenticated = true;
      req.session.expiresAt = Date.now() + maxAge;
      req.session.cookie.maxAge = maxAge;

      return req.session.save((error) => {
        if (error) {
          return res.status(500).json({ ok: false, message: "Erro ao salvar sessão." });
        }

        return res.json({
          ok: true,
          redirect: "/dashboard.html",
          remainingMs: remainingSessionMs(req)
        });
      });
    }

    const users = readUsers();
    const user = users.find(item => {
      return String(item.email || "").toLowerCase() === normalizedEmail && item.status !== "inativo";
    });

    if (!user || !user.senhaHash) {
      return res.status(401).json({
        ok: false,
        message: "E-mail ou senha inválidos."
      });
    }

    const senhaValida = await bcrypt.compare(String(senha || ""), user.senhaHash);

    if (!senhaValida) {
      return res.status(401).json({
        ok: false,
        message: "E-mail ou senha inválidos."
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
      permissoes: user.permissoes || [],
      permissions: user.permissoes || [],
      superadmin: Boolean((user.permissoes || []).includes("*")),
      admin: Boolean((user.permissoes || []).includes("*"))
    };

    req.session.usuario = req.session.user;
    req.session.email = req.session.user.email;
    req.session.nome = req.session.user.nome;
    req.session.cargo = req.session.user.cargo;
    req.session.permissoes = req.session.user.permissoes;
    req.session.expiresAt = Date.now() + maxAge;
    req.session.cookie.maxAge = maxAge;

    return req.session.save((error) => {
      if (error) {
        return res.status(500).json({ ok: false, message: "Erro ao salvar sessão." });
      }

      return res.json({
        ok: true,
        redirect: "/dashboard.html",
        remainingMs: remainingSessionMs(req)
      });
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
  destination: (_req, _file, cb) => {
    fs.mkdirSync(RELATORIO_UPLOAD_DIR, { recursive: true });
    cb(null, RELATORIO_UPLOAD_DIR);
  },
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


function isoParaDataBRServidor(iso) {
  if (!iso || !String(iso).includes("-")) return "";
  const [ano, mes, dia] = String(iso).slice(0, 10).split("-");
  if (!ano || !mes || !dia) return "";
  return `${dia}/${mes}/${ano}`;
}

function relatorioCejasVazioServidor(report) {
  const eventos = Array.isArray(report?.eventos) ? report.eventos : [];
  const resumo = report?.resumo || {};

  return !eventos.length &&
    !Number(resumo.totalEventos || 0) &&
    !Number(resumo.faturamentoPrevisto || 0) &&
    !Number(resumo.receitaConfirmada || 0);
}

async function carregarRelatorioAtualDoSupabaseServidor() {
  try {
    const { supabaseAdmin, isSupabaseConfigured } = require("./lib/supabase");

    if (!isSupabaseConfigured || !isSupabaseConfigured() || !supabaseAdmin) return null;

    const relatorios = await supabaseAdmin
      .from("cejas_relatorios")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(1);

    if (relatorios.error || !relatorios.data || !relatorios.data.length) return null;

    const relatorio = relatorios.data[0];

    const eventosQuery = await supabaseAdmin
      .from("cejas_eventos")
      .select("*")
      .eq("relatorio_id", relatorio.id)
      .order("data_evento", { ascending: true });

    if (eventosQuery.error) return null;

    const eventos = (eventosQuery.data || []).map((evento) => ({
      data: isoParaDataBRServidor(evento.data_evento),
      horaInicial: evento.hora_inicial || "",
      horaFinal: evento.hora_final || "",
      sala: evento.sala || "",
      empresa: evento.empresa || "",
      evento: evento.evento || "",
      status: evento.status || "em_espera",
      participantes: Number(evento.participantes || 0),
      valor: Number(evento.valor || 0),
      desconto: Number(evento.desconto || 0),
      produtos: evento.produtos || [],
      blocoOriginal: evento.bloco_original || ""
    }));

    const report = {
      atualizadoEm: relatorio.created_at || new Date().toISOString(),
      arquivo: relatorio.nome_arquivo || "relatorio-supabase.pdf",
      origem: "supabase",
      resumo: {
        faturamentoPrevisto: Number(relatorio.faturamento_previsto || 0),
        receitaConfirmada: Number(relatorio.receita_confirmada || 0),
        descontosAplicados: Number(relatorio.descontos_aplicados || 0),
        eventosConfirmados: Number(relatorio.eventos_confirmados || 0),
        eventosPendentes: Number(relatorio.eventos_em_espera || 0),
        eventosCancelados: Number(relatorio.eventos_cancelados || 0),
        totalEventos: Number(relatorio.total_eventos || eventos.length)
      },
      eventos,
      salas: [],
      produtos: []
    };

    return report;
  } catch (error) {
    console.warn("⚠️ Não foi possível carregar relatório do Supabase:", error.message);
    return null;
  }
}


// CEJAS_BACKUP_RELATORIO_START
function criarHistoricoRelatorioAtualCejas() {
  try {
    if (!fs.existsSync(RELATORIO_FILE)) return "";

    const historicoDir = path.join(__dirname, "data", "historico-relatorios");
    fs.mkdirSync(historicoDir, { recursive: true });

    const destino = path.join(historicoDir, `relatorio-atual-${cejasTimestampSeguro()}.json`);
    fs.copyFileSync(RELATORIO_FILE, destino);

    return destino;
  } catch (error) {
    console.warn("⚠️ Não foi possível salvar histórico do relatório:", error.message);
    return "";
  }
}
// CEJAS_BACKUP_RELATORIO_END

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


app.get("/api/relatorio-atual", async (_req, res) => {
  try {
    let report = null;

    if (fs.existsSync(RELATORIO_FILE)) {
      try {
        report = JSON.parse(fs.readFileSync(RELATORIO_FILE, "utf8"));
      } catch {
        report = null;
      }
    }

    if (!report || relatorioCejasVazioServidor(report)) {
      const supabaseReport = await carregarRelatorioAtualDoSupabaseServidor();

      if (supabaseReport && !relatorioCejasVazioServidor(supabaseReport)) {
        fs.writeFileSync(RELATORIO_FILE, JSON.stringify(supabaseReport, null, 2), "utf8");
        report = supabaseReport;
      }
    }

    if (!report) {
      report = emptySuperaReport();
      criarHistoricoRelatorioAtualCejas();
    fs.writeFileSync(RELATORIO_FILE, JSON.stringify(report, null, 2), "utf8");
    }

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

app.post("/api/importar-relatorio", (req, res, next) => {
  fs.mkdirSync(RELATORIO_UPLOAD_DIR, { recursive: true });
  next();
}, relatorioUpload.single("relatorio"), async (req, res) => {
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

    let syncSupabase = null;
    try {
      syncSupabase = await syncRelatorioAtualComSupabase({ reportPath: RELATORIO_FILE });
      console.log("✅ Relatório sincronizado com Supabase:", syncSupabase);
    } catch (syncError) {
      syncSupabase = { ok: false, message: syncError.message };
      console.warn("⚠️ Relatório salvo localmente, mas não sincronizou com Supabase:", syncError.message);
    }

    console.log("✅ Relatório processado:", report.resumo);
    console.log("📌 Eventos detectados:", report.eventos.length);
    console.log("📌 Eventos detectados:", report.eventos.length);
    console.log("📝 Texto salvo em data/ultimo-relatorio-texto-extraido.txt");

    res.json({
      ok: true,
      message: syncSupabase && syncSupabase.ok
        ? "Relatório importado e sincronizado para todos os dispositivos."
        : "Relatório importado localmente. Verifique a configuração do Supabase para aparecer em celular/tablet.",
      report,
      syncSupabase
    });
  } catch (error) {
    console.error("❌ ERRO AO IMPORTAR PDF:", error);

    res.status(500).json({
      ok: false,
      message: "Erro ao importar PDF: " + (error.message || "erro desconhecido")
    });
  }
});







// CEJAS_GRATUIDADES_API_START
const cryptoCejasGratManual = require("crypto");

const GRATUIDADES_FILE = path.join(__dirname, "data", "gratuidades-manuais.json");

function garantirArquivoGratuidadesManualCejas() {
  fs.mkdirSync(path.join(__dirname, "data"), { recursive: true });

  if (!fs.existsSync(GRATUIDADES_FILE)) {
    fs.writeFileSync(GRATUIDADES_FILE, "[]", "utf8");
  }
}

function carregarGratuidadesManualCejas() {
  garantirArquivoGratuidadesManualCejas();

  try {
    const data = JSON.parse(fs.readFileSync(GRATUIDADES_FILE, "utf8"));
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
}

function salvarGratuidadesManualCejas(lista) {
  garantirArquivoGratuidadesManualCejas();
  fs.writeFileSync(GRATUIDADES_FILE, JSON.stringify(lista || [], null, 2), "utf8");
}

function numeroGratManualCejas(valor) {
  if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

  const texto = String(valor || "")
    .replace(/R\$/gi, "")
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".");

  const numero = Number(texto);
  return Number.isFinite(numero) ? numero : 0;
}

function perdaNegativaManualCejas(valor) {
  const numero = numeroGratManualCejas(valor);
  if (!numero) return 0;
  return numero > 0 ? -Math.abs(numero) : numero;
}

function calcularPerdaManualCejas(valorTotal, valorPago, valorPerdaInformado) {
  const informado = numeroGratManualCejas(valorPerdaInformado);

  if (informado !== 0) {
    return perdaNegativaManualCejas(informado);
  }

  const total = numeroGratManualCejas(valorTotal);
  const pago = numeroGratManualCejas(valorPago);
  const perda = Math.min(pago - total, 0);

  return perdaNegativaManualCejas(perda);
}

function dataParaISOManualCejas(data) {
  const texto = String(data || "").trim();

  if (!texto) return "";

  if (/^\d{4}-\d{2}-\d{2}/.test(texto)) {
    return texto.slice(0, 10);
  }

  let match = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/);
  if (match) {
    return `${match[3]}-${String(match[2]).padStart(2, "0")}-${String(match[1]).padStart(2, "0")}`;
  }

  match = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2})\b/);
  if (match) {
    return `20${match[3]}-${String(match[2]).padStart(2, "0")}-${String(match[1]).padStart(2, "0")}`;
  }

  return "";
}

function isoParaDataBRManualCejas(iso) {
  if (!iso || !String(iso).includes("-")) return "";
  const [ano, mes, dia] = String(iso).slice(0, 10).split("-");
  if (!ano || !mes || !dia) return "";
  return `${dia}/${mes}/${ano}`;
}

function nomeMesManualCejas(key) {
  const nomes = [
    "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
    "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
  ];

  const [ano, mes] = String(key || "").split("-");
  const idx = Number(mes) - 1;

  if (!ano || idx < 0 || idx > 11) return key || "Sem mês";
  return `${nomes[idx]} de ${ano}`;
}

function normalizarBuscaManualCejas(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function normalizarGratuidadeManualCejas(item) {
  const dataISO = dataParaISOManualCejas(item?.dataISO || item?.data || "");

  const valorTotal = numeroGratManualCejas(
    item?.valorTotal ??
    item?.valorEvento ??
    item?.total ??
    0
  );

  const valorPago = numeroGratManualCejas(
    item?.valorPago ??
    item?.pago ??
    0
  );

  const valorPerda = calcularPerdaManualCejas(
    valorTotal,
    valorPago,
    item?.valorPerda ??
    item?.perda ??
    item?.valorGratuidade ??
    0
  );

  return {
    id: item?.id || `manual-${Date.now()}-${cryptoCejasGratManual.randomBytes(4).toString("hex")}`,
    origem: "manual",
    tipo: "manual",
    editavel: true,
    data: isoParaDataBRManualCejas(dataISO),
    dataISO,
    evento: String(item?.evento || "Gratuidade sem evento").trim(),
    valorTotal,
    valorPago,
    valorPerda,
    orgaoAssociado: String(
      item?.orgaoAssociado ||
      item?.orgao ||
      item?.associado ||
      item?.referencia ||
      "NÃO INFORMADO"
    ).trim(),
    referencia: String(item?.referencia || "").trim(),
    observacao: String(item?.observacao || "").trim(),
    criadoEm: item?.criadoEm || new Date().toISOString(),
    atualizadoEm: new Date().toISOString()
  };
}

function filtrarGratuidadesManualCejas(lista, query = {}) {
  const de = String(query.de || "").slice(0, 10);
  const ate = String(query.ate || "").slice(0, 10);
  const busca = normalizarBuscaManualCejas(query.busca || "");

  let itens = lista.map(normalizarGratuidadeManualCejas);

  if (de || ate) {
    itens = itens.filter(item => {
      if (!item.dataISO) return false;
      if (de && item.dataISO < de) return false;
      if (ate && item.dataISO > ate) return false;
      return true;
    });
  }

  if (busca) {
    itens = itens.filter(item => {
      const texto = normalizarBuscaManualCejas(`${item.evento} ${item.orgaoAssociado} ${item.referencia} ${item.observacao}`);
      return texto.includes(busca);
    });
  }

  itens.sort((a, b) => String(b.dataISO || "").localeCompare(String(a.dataISO || "")) || String(a.evento).localeCompare(String(b.evento)));

  return itens;
}

function resumirGratuidadesManualCejas(itens) {
  return itens.reduce((acc, item) => {
    acc.quantidade += 1;
    acc.valorTotal += numeroGratManualCejas(item.valorTotal);
    acc.valorPago += numeroGratManualCejas(item.valorPago);
    acc.valorPerda += perdaNegativaManualCejas(item.valorPerda);
    acc.manual += 1;
    return acc;
  }, {
    quantidade: 0,
    valorTotal: 0,
    valorPago: 0,
    valorPerda: 0,
    manual: 0,
    automatica: 0
  });
}

function graficosGratuidadesManualCejas(itens) {
  const porMes = {};
  const porOrgao = {};
  const porOrigem = {
    manual: {
      key: "manual",
      label: "Manual",
      quantidade: 0,
      valorPerda: 0
    }
  };

  for (const item of itens) {
    const mesKey = item.dataISO ? item.dataISO.slice(0, 7) : "SEM DATA";
    const orgao = item.orgaoAssociado || "NÃO INFORMADO";
    const perda = perdaNegativaManualCejas(item.valorPerda);

    porMes[mesKey] = porMes[mesKey] || {
      key: mesKey,
      label: nomeMesManualCejas(mesKey),
      quantidade: 0,
      valorPerda: 0
    };

    porOrgao[orgao] = porOrgao[orgao] || {
      key: orgao,
      label: orgao,
      quantidade: 0,
      valorPerda: 0
    };

    porMes[mesKey].quantidade += 1;
    porMes[mesKey].valorPerda += perda;

    porOrgao[orgao].quantidade += 1;
    porOrgao[orgao].valorPerda += perda;

    porOrigem.manual.quantidade += 1;
    porOrigem.manual.valorPerda += perda;
  }

  return {
    porMes: Object.values(porMes).sort((a, b) => String(a.key).localeCompare(String(b.key))),
    porOrigem: Object.values(porOrigem),
    porOrgao: Object.values(porOrgao).sort((a, b) => Math.abs(b.valorPerda) - Math.abs(a.valorPerda)).slice(0, 12)
  };
}

async function montarGratuidadesCejas(query = {}) {
  const lista = carregarGratuidadesManualCejas();
  const itens = filtrarGratuidadesManualCejas(lista, query);

  return {
    itens,
    resumo: resumirGratuidadesManualCejas(itens),
    graficos: graficosGratuidadesManualCejas(itens),
    atualizadoEm: new Date().toISOString()
  };
}

async function montarDashboardFinanceiroCejas() {
  const gratuidades = await montarGratuidadesCejas({});

  return {
    ok: true,
    receitaMensal: [],
    resumo: {
      totalReceitaConfirmada: 0,
      totalEventosConfirmados: 0,
      mesesComReceita: 0,
      gratuidades: gratuidades.resumo
    },
    graficosGratuidades: gratuidades.graficos,
    atualizadoEm: new Date().toISOString()
  };
}

app.get("/api/gratuidades", async (req, res) => {
  try {
    const dados = await montarGratuidadesCejas(req.query || {});
    res.json({ ok: true, ...dados });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar gratuidades: " + error.message
    });
  }
});

app.post("/api/gratuidades", express.json({ limit: "2mb" }), (req, res) => {
  try {
    const lista = carregarGratuidadesManualCejas();
    const novo = normalizarGratuidadeManualCejas(req.body || {});

    if (!novo.dataISO) {
      return res.status(400).json({ ok: false, message: "Informe a data da gratuidade." });
    }

    if (!novo.evento || novo.evento === "Gratuidade sem evento") {
      return res.status(400).json({ ok: false, message: "Informe o evento." });
    }

    lista.push(novo);
    salvarGratuidadesManualCejas(lista);

    res.json({
      ok: true,
      item: novo,
      message: "Gratuidade salva."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao salvar gratuidade: " + error.message
    });
  }
});

app.put("/api/gratuidades/:id", express.json({ limit: "2mb" }), (req, res) => {
  try {
    const id = req.params.id;
    const lista = carregarGratuidadesManualCejas();
    const index = lista.findIndex(item => item.id === id);

    if (index < 0) {
      return res.status(404).json({
        ok: false,
        message: "Gratuidade não encontrada."
      });
    }

    lista[index] = normalizarGratuidadeManualCejas({
      ...lista[index],
      ...req.body,
      id
    });

    salvarGratuidadesManualCejas(lista);

    res.json({
      ok: true,
      item: lista[index],
      message: "Gratuidade atualizada."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao editar gratuidade: " + error.message
    });
  }
});

app.delete("/api/gratuidades/:id", (req, res) => {
  try {
    const id = req.params.id;
    const lista = carregarGratuidadesManualCejas();
    const novaLista = lista.filter(item => item.id !== id);

    if (novaLista.length === lista.length) {
      return res.status(404).json({
        ok: false,
        message: "Gratuidade não encontrada."
      });
    }

    salvarGratuidadesManualCejas(novaLista);

    res.json({
      ok: true,
      message: "Gratuidade apagada."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao apagar gratuidade: " + error.message
    });
  }
});

app.get("/api/dashboard-financeiro", async (_req, res) => {
  try {
    const dados = await montarDashboardFinanceiroCejas();
    res.json(dados);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar dashboard financeiro: " + error.message
    });
  }
});
// CEJAS_GRATUIDADES_API_END




const USERS_FILE = path.join(__dirname, "data", "usuarios.json");

const PERMISSOES_DISPONIVEIS = [
  { id: "painel", nome: "Painel Geral" },
  { id: "agenda", nome: "Agenda Dinâmica" },
  { id: "orcamentos", nome: "Orçamentos" },
  { id: "relatorios", nome: "Importar Relatório PDF" },
  { id: "tarefas", nome: "Tarefas Pendentes" },
  { id: "servidor", nome: "Servidor de Arquivos" },
  { id: "financeiro", nome: "Financeiro" },
  { id: "gratuidades", nome: "Gratuidades" },
  { id: "usuarios", nome: "Acessos / Usuários" },
  { id: "configuracoes", nome: "Configurações" }
,
  { id: "financeiro_editar_status", nome: "Financeiro - Editar status" },
  { id: "financeiro_vincular_arquivos", nome: "Financeiro - Vincular arquivos" },
  { id: "financeiro_editar_valores", nome: "Financeiro - Editar valores" },
  { id: "financeiro_admin", nome: "Financeiro - Administrador" }
];

const PAGE_PERMISSION = {
  "/dashboard.html": "painel",
  "/agenda.html": "agenda",
  "/orcamentos.html": "orcamentos",
  "/importar-relatorio.html": "relatorios",
  "/tarefas.html": "tarefas",
  "/servidor.html": "servidor",
  "/financeiro.html": "financeiro",
  "/gratuidades.html": "gratuidades",
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
  if (permission === "financeiro") return true;
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
iniciarProtecaoServidorSupabase(SERVIDOR_DIR);

// CEJAS_SYNC_SERVIDOR_STORAGE_AFTER_MUTATION
app.use((req, res, next) => {
  if (req.path.startsWith("/api/servidor") && ["POST", "DELETE", "PUT", "PATCH"].includes(req.method)) {
    res.on("finish", () => {
      if (res.statusCode < 400) {
        setTimeout(() => {
          try {
            const { enviarDiretorioParaSupabaseServidor } = require("./lib/servidor-storage-persistente");
            enviarDiretorioParaSupabaseServidor(SERVIDOR_DIR).catch((error) => {
              console.warn("⚠️ Sync pós-alteração do servidor falhou:", error.message);
            });
          } catch (error) {
            console.warn("⚠️ Sync pós-alteração do servidor não iniciou:", error.message);
          }
        }, 800);
      }
    });
  }

  next();
});


// CEJAS_PROTECAO_DADOS_START
function cejasTimestampSeguro() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function copiarDiretorioSeguroCejas(origem, destino) {
  if (!fs.existsSync(origem)) return false;

  fs.mkdirSync(destino, { recursive: true });

  for (const entry of fs.readdirSync(origem, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;

    const origemItem = path.join(origem, entry.name);
    const destinoItem = path.join(destino, entry.name);

    if (entry.isDirectory()) {
      copiarDiretorioSeguroCejas(origemItem, destinoItem);
    } else if (entry.isFile()) {
      fs.mkdirSync(path.dirname(destinoItem), { recursive: true });
      fs.copyFileSync(origemItem, destinoItem);
    }
  }

  return true;
}

function criarBackupServidorAntesMudancaCejas(motivo = "mudanca") {
  try {
    const backupBase = path.join(__dirname, ".cejas-local-backups");
    const destino = path.join(backupBase, `servidor-${motivo}-${cejasTimestampSeguro()}`);

    fs.mkdirSync(backupBase, { recursive: true });

    if (fs.existsSync(SERVIDOR_DIR)) {
      copiarDiretorioSeguroCejas(SERVIDOR_DIR, destino);
    }

    return destino;
  } catch (error) {
    console.warn("⚠️ Não foi possível criar backup do servidor:", error.message);
    return "";
  }
}

function moverParaLixeiraServidorCejas(itemPath, relativePath = "") {
  const lixeiraDir = path.join(SERVIDOR_DIR, "_LIXEIRA", cejasTimestampSeguro().slice(0, 10));
  const destinoBase = path.join(lixeiraDir, relativePath || path.basename(itemPath));
  let destino = destinoBase;

  fs.mkdirSync(path.dirname(destino), { recursive: true });

  if (fs.existsSync(destino)) {
    const ext = path.extname(destinoBase);
    const name = path.basename(destinoBase, ext);
    const dir = path.dirname(destinoBase);
    let count = 1;

    while (fs.existsSync(destino)) {
      destino = path.join(dir, `${name}-${count}${ext}`);
      count++;
    }
  }

  fs.renameSync(itemPath, destino);

  return path.relative(SERVIDOR_DIR, destino).replace(/\\/g, "/");
}

app.post("/api/servidor/backup-seguranca", (_req, res) => {
  try {
    const destino = criarBackupServidorAntesMudancaCejas("manual");

    res.json({
      ok: true,
      destino,
      message: "Backup de segurança criado."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao criar backup: " + error.message
    });
  }
});
// CEJAS_PROTECAO_DADOS_END



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
    files: 10000
  }
});

const MESES_SERVIDOR_FINAL = [
  { numero: "01", nome: "JANEIRO", simples: "JANEIRO", aliases: ["JANEIRO", "JAN"] },
  { numero: "02", nome: "FEVEREIRO", simples: "FEVEREIRO", aliases: ["FEVEREIRO", "FEV"] },
  { numero: "03", nome: "MARÇO", simples: "MARÇO", aliases: ["MARCO", "MARÇO", "MAR"] },
  { numero: "04", nome: "ABRIL", simples: "ABRIL", aliases: ["ABRIL", "ABR"] },
  { numero: "05", nome: "MAIO", simples: "MAIO", aliases: ["MAIO", "MAI"] },
  { numero: "06", nome: "JUNHO", simples: "JUNHO", aliases: ["JUNHO", "JUN"] },
  { numero: "07", nome: "JULHO", simples: "JULHO", aliases: ["JULHO", "JUL"] },
  { numero: "08", nome: "AGOSTO", simples: "AGOSTO", aliases: ["AGOSTO", "AGO"] },
  { numero: "09", nome: "SETEMBRO", simples: "SETEMBRO", aliases: ["SETEMBRO", "SET"] },
  { numero: "10", nome: "OUTUBRO", simples: "OUTUBRO", aliases: ["OUTUBRO", "OUT"] },
  { numero: "11", nome: "NOVEMBRO", simples: "NOVEMBRO", aliases: ["NOVEMBRO", "NOV"] },
  { numero: "12", nome: "DEZEMBRO", simples: "DEZEMBRO", aliases: ["DEZEMBRO", "DEZ"] }
];

const PALAVRAS_DOCUMENTO_SERVIDOR_FINAL = [
  "CONTRATO", "CONTRATOS",
  "BOLETO", "BOLETOS",
  "DEMONSTRATIVO", "DEMONSTRATIVOS",
  "RELATORIO", "RELATÓRIO",
  "ORCAMENTO", "ORÇAMENTO",
  "PROPOSTA",
  "RECIBO", "RECIBOS",
  "COMPROVANTE", "COMPROVANTES",
  "NOTA FISCAL", "NOTAS FISCAIS", "NOTA", "NFS", "NF",
  "EVENTO", "EVENTOS",
  "ENTIDADE", "ENTIDADES",
  "ASSINADO", "ASSINADA",
  "FINAL", "OK", "PDF", "DOC", "DOCX", "XLS", "XLSX", "PNG", "JPG", "JPEG"
];

function normalizarServidorFinal(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function slugServidorFinal(texto, fallback = "VERIFICAR") {
  const limpo = normalizarServidorFinal(texto)
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  return limpo || fallback;
}

function nomeArquivoSeguroServidorFinal(texto, fallback = "arquivo") {
  return String(texto || fallback)
    .replace(/[\\/:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^\.+/, fallback) || fallback;
}

function itemMesServidorFinal(mes) {
  const numero = String(mes || "").padStart(2, "0");
  return MESES_SERVIDOR_FINAL.find(m => m.numero === numero) || null;
}

function pastaMesServidorFinal(mes) {
  const item = itemMesServidorFinal(mes);
  return item ? `${item.numero} ${item.nome}` : "MES NAO IDENTIFICADO";
}

function pastaMesVerificarServidorFinal(mes) {
  const item = itemMesServidorFinal(mes);
  return item ? item.simples : "SEM MES";
}

function mesPorNomeServidorFinal(texto) {
  const normal = normalizarServidorFinal(texto);

  for (const mes of MESES_SERVIDOR_FINAL) {
    for (const alias of mes.aliases) {
      const aliasNormal = normalizarServidorFinal(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(^|[^A-Z0-9])${aliasNormal}([^A-Z0-9]|$)`);
      if (re.test(normal)) return mes.numero;
    }
  }

  return "";
}

function detectarDataServidorFinal(texto, anoPadrao = "2026") {
  const original = String(texto || "");
  const anoDefault = String(anoPadrao || "2026");

  let match = original.match(/\b(20\d{2})[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ](\d{1,2})\b/);
  if (match) {
    return {
      ok: true,
      ano: match[1],
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[3]).padStart(2, "0"),
      anoExplicito: true
    };
  }

  match = original.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})[.\-_/ ](20\d{2}|\d{2})\b/);
  if (match) {
    return {
      ok: true,
      ano: String(match[3]).length === 2 ? `20${match[3]}` : match[3],
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      anoExplicito: true
    };
  }

  match = original.match(/(?:^|[^\d])(\d{1,2})\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?(?:[^\d]|$)/i);
  if (match) {
    return {
      ok: true,
      ano: match[3] ? (String(match[3]).length === 2 ? `20${match[3]}` : match[3]) : anoDefault,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      anoExplicito: Boolean(match[3])
    };
  }

  match = original.match(/(?:^|[^\d])(\d{1,2})\s+(0?[1-9]|1[0-2])(?:\s+(20\d{2}|\d{2}))?(?:[^\d]|$)/);
  if (match) {
    return {
      ok: true,
      ano: match[3] ? (String(match[3]).length === 2 ? `20${match[3]}` : match[3]) : anoDefault,
      mes: String(match[2]).padStart(2, "0"),
      dia: String(match[1]).padStart(2, "0"),
      anoExplicito: Boolean(match[3])
    };
  }

  const mesNome = mesPorNomeServidorFinal(original);
  const anoCompleto = original.match(/\b(20\d{2})\b/);

  return {
    ok: false,
    ano: anoCompleto ? anoCompleto[1] : anoDefault,
    mes: mesNome,
    dia: "",
    anoExplicito: Boolean(anoCompleto)
  };
}

function removerDatasServidorFinal(texto) {
  return String(texto || "")
    .replace(/\b20\d{2}[.\-_/ ](0?[1-9]|1[0-2])[.\-_/ ]\d{1,2}\b/g, " ")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}[.\-_/ ](20\d{2}|\d{2})\b/g, " ")
    .replace(/(^|[^\d])\d{1,2}\s*(?:DO|DE|\/|-|_|\.)\s*(0?[1-9]|1[0-2])(?:\s*(?:DE|DO|\/|-|_|\.)\s*(20\d{2}|\d{2}))?($|[^\d])/gi, " ")
    .replace(/(^|[^\d])\d{1,2}\s+(0?[1-9]|1[0-2])(?:\s+(20\d{2}|\d{2}))?($|[^\d])/g, " ");
}

function removerPalavrasDocumentoServidorFinal(texto) {
  let saida = normalizarServidorFinal(texto);

  for (const palavra of PALAVRAS_DOCUMENTO_SERVIDOR_FINAL) {
    const normal = normalizarServidorFinal(palavra).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`(^|[^A-Z0-9])${normal}([^A-Z0-9]|$)`, "gi");
    saida = saida.replace(re, " ");
  }

  for (const mes of MESES_SERVIDOR_FINAL) {
    for (const alias of mes.aliases) {
      const normal = normalizarServidorFinal(alias).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(^|[^A-Z0-9])${normal}([^A-Z0-9]|$)`, "gi");
      saida = saida.replace(re, " ");
    }
  }

  return saida;
}

function parteIgnoradaServidorFinal(parte) {
  const normal = normalizarServidorFinal(parte);

  if (!normal) return true;
  if (normal === "SERVIDOR") return true;
  if (normal === "DOCUMENTOS") return true;
  if (normal === "EVENTOS") return true;
  if (normal === "BOLETOS") return true;
  if (normal === "DEMONSTRATIVOS") return true;
  if (normal === "CONTRATOS") return true;
  if (normal === "ENTIDADES") return true;
  if (normal === "VERIFICAR") return true;
  if (normal === "UPLOADS") return true;
  if (normal === "ARQUIVOS") return true;
  if (/^20\d{2}$/.test(normal)) return true;
  if (/^\d{2}\s+[A-Z]/.test(normal)) return true;

  return MESES_SERVIDOR_FINAL.some(m => normal === m.simples || normal === `${m.numero} ${normalizarServidorFinal(m.nome)}`);
}

function limparNomeEventoServidorFinal(originalPath, fileName) {
  const partes = String(originalPath || fileName || "")
    .replace(/\\/g, "/")
    .split("/")
    .filter(Boolean);

  const candidatos = [];

  const baseArquivo = path.basename(String(fileName || partes[partes.length - 1] || "arquivo"), path.extname(String(fileName || "")));
  candidatos.push(baseArquivo);

  for (let i = partes.length - 2; i >= 0; i--) {
    if (!parteIgnoradaServidorFinal(partes[i])) {
      candidatos.push(partes[i]);
    }
  }

  for (const candidato of candidatos) {
    let nome = path.basename(String(candidato || ""), path.extname(String(candidato || "")));

    nome = removerDatasServidorFinal(nome);
    nome = removerPalavrasDocumentoServidorFinal(nome);

    nome = nome
      .replace(/[_\-.]+/g, " ")
      .replace(/\b(DO|DE|DA|DAS|DOS)\b$/gi, " ")
      .replace(/\s+/g, " ")
      .trim();

    if (nome.length >= 2) {
      return slugServidorFinal(nome, "VERIFICAR");
    }
  }

  return "";
}

function pastaEventoServidorFinal(titulo, data) {
  return slugServidorFinal(`${titulo} ${data.dia}.${data.mes}`, "VERIFICAR");
}

function destinoServidorFinal(originalPath, fileName, anoPadrao = "2026") {
  const textoCompleto = `${originalPath || ""} ${fileName || ""}`;
  const data = detectarDataServidorFinal(textoCompleto, anoPadrao);
  const titulo = limparNomeEventoServidorFinal(originalPath, fileName);
  const nomeArquivo = nomeArquivoSeguroServidorFinal(fileName || path.basename(originalPath || "arquivo"), "arquivo");

  if (data.ok && data.dia && data.mes && titulo) {
    const mesPasta = pastaMesServidorFinal(data.mes);
    const eventoPasta = pastaEventoServidorFinal(titulo, data);

    if (data.ano && data.ano !== String(anoPadrao || "2026")) {
      return `${data.ano}/${mesPasta}/${eventoPasta}/${nomeArquivo}`;
    }

    return `${mesPasta}/${eventoPasta}/${nomeArquivo}`;
  }

  const mesVerificar = data.mes ? pastaMesVerificarServidorFinal(data.mes) : "SEM MES";
  return `VERIFICAR/${mesVerificar}/${nomeArquivo}`;
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

function listarArquivosServidorRecursivo(dir, base = SERVIDOR_DIR, resultado = []) {
  if (!fs.existsSync(dir)) return resultado;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;

    const full = path.join(dir, entry.name);
    const rel = path.relative(base, full).replace(/\\/g, "/");

    if (entry.isDirectory()) {
      listarArquivosServidorRecursivo(full, base, resultado);
    } else if (entry.isFile()) {
      resultado.push({ full, rel, name: entry.name });
    }
  }

  return resultado;
}

function listarPastasServidorRecursivo(dir = SERVIDOR_DIR, base = SERVIDOR_DIR, resultado = []) {
  if (!fs.existsSync(dir)) return resultado;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tmp-servidor") continue;

    const full = path.join(dir, entry.name);
    const rel = path.relative(base, full).replace(/\\/g, "/");

    if (entry.isDirectory()) {
      resultado.push(rel);
      listarPastasServidorRecursivo(full, base, resultado);
    }
  }

  return resultado;
}

function pastaJaPareceCorretaServidor(rel) {
  const partes = String(rel || "").split("/").filter(Boolean);

  if (partes[0] === "VERIFICAR") return false;

  let idxMes = 0;

  if (/^20\d{2}$/.test(partes[0])) {
    idxMes = 1;
  }

  if (partes.length < idxMes + 3) return false;
  if (!/^\d{2}\s+[A-ZÁÉÍÓÚÂÊÔÃÕÇ]/.test(partes[idxMes])) return false;

  const nomeEvento = partes[idxMes + 1] || "";
  const normal = normalizarServidorFinal(nomeEvento);

  const bloqueadas = [
    "DOCUMENTOS", "EVENTOS", "BOLETOS", "DEMONSTRATIVOS",
    "CONTRATOS", "ENTIDADES", "NOTAS E RECIBOS", "VERIFICAR"
  ];

  if (bloqueadas.includes(normal)) return false;

  return /\b\d{2}\.\d{2}\b/.test(nomeEvento);
}

function listarVerificarServidor() {
  const verificarDir = safeServidorPath("VERIFICAR");

  if (!fs.existsSync(verificarDir)) return [];

  return listarArquivosServidorRecursivo(verificarDir)
    .map(item => ({
      path: item.rel,
      nome: item.name,
      pasta: path.dirname(item.rel).replace(/\\/g, "/"),
      mes: item.rel.split("/")[1] || "SEM MES"
    }))
    .sort((a, b) => a.path.localeCompare(b.path, "pt-BR"));
}














function listarArquivosParaDeleteServidorCejas(absPath, relPath, resultado = []) {
  if (!fs.existsSync(absPath)) return resultado;

  const stat = fs.statSync(absPath);

  if (stat.isFile()) {
    resultado.push(String(relPath || "").replace(/\\/g, "/"));
    return resultado;
  }

  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(absPath, { withFileTypes: true })) {
      const childAbs = path.join(absPath, entry.name);
      const childRel = path.join(relPath, entry.name).replace(/\\/g, "/");
      listarArquivosParaDeleteServidorCejas(childAbs, childRel, resultado);
    }
  }

  return resultado;
}




app.use(express.static(path.join(__dirname), { dotfiles: "deny" }));

app.use((error, _req, res, _next) => {
  console.error("Erro interno tratado pelo servidor:", error);

  let message = error.message || "Erro interno ao processar arquivo.";

  if (error instanceof multer.MulterError) {
    if (error.code === "LIMIT_FILE_SIZE") {
      message = "Arquivo muito grande para upload.";
    } else if (error.code === "LIMIT_FILE_COUNT") {
      message = "Quantidade de arquivos acima do limite permitido.";
    } else {
      message = "Erro no upload: " + error.message;
    }
  }

  return res.status(500).json({
    ok: false,
    message
  });
});


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











registrarAgendaDiaApi(app);


registrarDashboardPermissoesOrcamento(app);








registrarServidorPdfViewer(app);


registrarOrcamentoPdfServidor(app);


registrarConfiguracoesCejas(app);





registrarChatCejasApi(app);












// CEJAS_UPLOAD_JSON_ERROR_HANDLER_START
app.use((error, req, res, next) => {
  if (req.path && req.path.startsWith("/api/servidor/")) {
    return res.status(error.status || error.statusCode || 500).json({
      ok: false,
      message: "Erro no upload/servidor: " + (error.message || "erro desconhecido")
    });
  }

  next(error);
});
// CEJAS_UPLOAD_JSON_ERROR_HANDLER_END


app.listen(PORT, "0.0.0.0", () => {
  console.log(`✅ Sistema de Gestão CEJAS rodando em http://localhost:${PORT}`);
});
