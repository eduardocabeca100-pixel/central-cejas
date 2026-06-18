const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(__dirname, "..", "data");
const FINANCEIRO_FILE = path.join(DATA_DIR, "financeiro.json");
const UPLOADS_DIR = path.join(__dirname, "..", "uploads");

function agora() {
  return new Date().toISOString();
}

function garantirArquivo() {
  fs.mkdirSync(DATA_DIR, { recursive: true });

  if (!fs.existsSync(FINANCEIRO_FILE)) {
    fs.writeFileSync(
      FINANCEIRO_FILE,
      JSON.stringify({ itens: [], atualizadoEm: agora() }, null, 2),
      "utf8"
    );
  }
}

function lerDb() {
  garantirArquivo();

  try {
    const db = JSON.parse(fs.readFileSync(FINANCEIRO_FILE, "utf8"));
    if (!Array.isArray(db.itens)) db.itens = [];
    return db;
  } catch {
    return { itens: [], atualizadoEm: agora() };
  }
}

function salvarDb(db) {
  garantirArquivo();
  db.atualizadoEm = agora();
  fs.writeFileSync(FINANCEIRO_FILE, JSON.stringify(db, null, 2), "utf8");
}

function semAcento(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

function limparExtensao(nome) {
  return String(nome || "").replace(/\.[^.]+$/, "");
}

function detectarTipo(nomeArquivo) {
  const n = semAcento(limparExtensao(nomeArquivo)).toLowerCase();

  if (/\bboleto\b/.test(n)) return "boleto";
  if (/\bdemonstrativo\b/.test(n)) return "demonstrativo";
  if (/\borcamento\b/.test(n)) return "orcamento";

  return "orcamento";
}

function limparPrefixoDocumento(nome) {
  return limparExtensao(nome)
    .replace(/^\s*boleto\s*[-_–—:]?\s*/i, "")
    .replace(/^\s*demonstrativo\s*[-_–—:]?\s*/i, "")
    .replace(/^\s*orçamento\s*[-_–—:]?\s*/i, "")
    .replace(/^\s*orcamento\s*[-_–—:]?\s*/i, "")
    .trim();
}

function chaveDocumento(nome) {
  return semAcento(limparPrefixoDocumento(nome))
    .toLowerCase()
    .replace(/(\d{1,2})[./](\d{1,2})/g, "$1-$2")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function chaveGrupo(nome) {
  return semAcento(limparPrefixoDocumento(nome))
    .toLowerCase()
    .replace(/\b(atualizado|atualizada|novo|nova|final|corrigido|corrigida|revisado|revisada|versao|versão|v\d+)\b/g, " ")
    .replace(/(\d{1,2})[./](\d{1,2})/g, "$1-$2")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function nomeGrupo(nome) {
  return limparPrefixoDocumento(nome)
    .replace(/\b(atualizado|atualizada|novo|nova|final|corrigido|corrigida|revisado|revisada|versão|versao|v\d+)\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extrairDataEvento(nome) {
  const achou = String(nome || "").match(/(\d{1,2})[./-](\d{1,2})/);

  if (!achou) return "";

  return `${achou[1].padStart(2, "0")}/${achou[2].padStart(2, "0")}`;
}

function idNovo(prefixo = "fin") {
  return `${prefixo}-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`;
}

function statusDocumentoPadrao() {
  return {
    status: "nao_emitido",
    arquivos: [],
    vinculadoAoOrcamentoId: null,
    atualizadoEm: null
  };
}

function novoItem(nomeBase, origem = "manual") {
  const grupo = nomeGrupo(nomeBase) || nomeBase || "Evento sem nome";

  return {
    id: idNovo("financeiro"),
    chave: chaveGrupo(nomeBase) || chaveDocumento(nomeBase) || idNovo("grupo"),
    clienteEvento: grupo,
    dataEvento: extrairDataEvento(nomeBase),
    origem,
    orcamentos: [],
    boleto: statusDocumentoPadrao(),
    demonstrativo: statusDocumentoPadrao(),
    pagamento: {
      status: "pendente",
      valorPago: 0,
      pagoEm: null,
      atualizadoEm: null
    },
    faturamento: {
      status: "em_aberto",
      valorPrevisto: 0,
      valorFaturado: 0,
      atualizadoEm: null
    },
    observacoes: "",
    criadoEm: agora(),
    atualizadoEm: agora()
  };
}

function listarArquivosRecursivo(dir) {
  if (!fs.existsSync(dir)) return [];

  const resultado = [];

  for (const nome of fs.readdirSync(dir)) {
    const caminho = path.join(dir, nome);

    let stat;
    try {
      stat = fs.statSync(caminho);
    } catch {
      continue;
    }

    if (stat.isDirectory()) {
      resultado.push(...listarArquivosRecursivo(caminho));
    } else if (/\.pdf$/i.test(nome)) {
      resultado.push(caminho);
    }
  }

  return resultado;
}

function arquivoRelativo(caminho) {
  return path.relative(path.join(__dirname, ".."), caminho).replace(/\\/g, "/");
}


// CEJAS_FINANCEIRO_IGNORAR_RELATORIOS
function arquivoDeveSerIgnorado(caminhoAbsoluto, db = null) {
  const relativo = arquivoRelativo(caminhoAbsoluto);
  const relLower = String(relativo || "").toLowerCase();
  const nome = path.basename(caminhoAbsoluto);

  const ignorados = Array.isArray(db?.ignorados) ? db.ignorados : [];

  if (ignorados.includes(relativo)) return true;

  // Relatórios importados do Supera não são controle de faturamento.
  if (relLower.includes("uploads/relatorios/")) return true;
  if (relLower.includes("relatorio")) return true;

  // Arquivos com nome técnico automático, tipo 1781726412256-22.PDF,
  // normalmente são relatórios/importações, não orçamento/boleto/demonstrativo.
  if (/^\d{10,}-\d+\.pdf$/i.test(nome)) return true;

  return false;
}

function caminhoExisteRelativo(relativo) {
  if (!relativo) return false;
  return fs.existsSync(path.join(__dirname, "..", relativo));
}

function limparListaArquivos(lista, db) {
  if (!Array.isArray(lista)) return [];

  return lista.filter((arquivo) => {
    const relativo = arquivo.caminho || "";

    if (!relativo) return false;
    if (!caminhoExisteRelativo(relativo)) return false;

    const abs = path.join(__dirname, "..", relativo);

    return !arquivoDeveSerIgnorado(abs, db);
  });
}

function limparDbFinanceiro(db) {
  if (!Array.isArray(db.itens)) db.itens = [];
  if (!Array.isArray(db.ignorados)) db.ignorados = [];

  db.itens = db.itens.map((item) => {
    item.orcamentos = Array.isArray(item.orcamentos)
      ? item.orcamentos.filter((orc) => {
          if (!orc.caminho) return true;
          if (!caminhoExisteRelativo(orc.caminho)) return false;
          return !arquivoDeveSerIgnorado(path.join(__dirname, "..", orc.caminho), db);
        })
      : [];

    item.boleto = item.boleto || statusDocumentoPadrao();
    item.demonstrativo = item.demonstrativo || statusDocumentoPadrao();

    item.boleto.arquivos = limparListaArquivos(item.boleto.arquivos, db);
    item.demonstrativo.arquivos = limparListaArquivos(item.demonstrativo.arquivos, db);

    if (!item.boleto.arquivos.length && item.boleto.status !== "enviado") {
      item.boleto.status = "nao_emitido";
      item.boleto.vinculadoAoOrcamentoId = null;
    }

    if (!item.demonstrativo.arquivos.length && item.demonstrativo.status !== "enviado") {
      item.demonstrativo.status = "nao_emitido";
      item.demonstrativo.vinculadoAoOrcamentoId = null;
    }

    return item;
  });

  db.itens = db.itens.filter((item) => {
    const nome = String(item.clienteEvento || "").trim();

    // Remove linhas técnicas/números que vieram de relatório.
    if (/^\d{10,}-\d+$/i.test(nome)) return false;

    const temArquivos =
      (item.orcamentos || []).length ||
      (item.boleto?.arquivos || []).length ||
      (item.demonstrativo?.arquivos || []).length;

    // Mantém controles criados manualmente.
    if (item.origem === "manual") return true;

    return Boolean(temArquivos);
  });

  return db;
}

function acharOuCriarItem(db, nomeBase, origem) {
  const chave = chaveGrupo(nomeBase) || chaveDocumento(nomeBase);
  let item = db.itens.find((x) => x.chave === chave);

  if (!item) {
    item = novoItem(nomeBase, origem);
    item.chave = chave || item.chave;
    db.itens.push(item);
  }

  if (!item.dataEvento) {
    item.dataEvento = extrairDataEvento(nomeBase);
  }

  item.atualizadoEm = agora();

  return item;
}

function registrarOrcamento(item, info) {
  const chave = chaveDocumento(info.nomeArquivo);

  const existe = item.orcamentos.find((o) => {
    return o.chaveDocumento === chave || o.caminho === info.caminho;
  });

  if (!existe) {
    item.orcamentos.push({
      id: idNovo("orc"),
      nome: limparPrefixoDocumento(info.nomeArquivo),
      nomeArquivo: info.nomeArquivo,
      caminho: info.caminho,
      chaveDocumento: chave,
      status: "gerado",
      criadoEm: agora()
    });
  }
}

function registrarArquivoDocumento(item, campo, info) {
  if (!item[campo]) item[campo] = statusDocumentoPadrao();
  if (!Array.isArray(item[campo].arquivos)) item[campo].arquivos = [];

  const existeArquivo = item[campo].arquivos.find((a) => a.caminho === info.caminho);

  if (!existeArquivo) {
    item[campo].arquivos.push({
      id: idNovo(campo),
      nomeArquivo: info.nomeArquivo,
      caminho: info.caminho,
      criadoEm: agora()
    });
  }

  const chaveDoc = chaveDocumento(info.nomeArquivo);

  const orcamentoExato = item.orcamentos.find((orc) => {
    return orc.chaveDocumento === chaveDoc;
  });

  if (orcamentoExato) {
    item[campo].status = "emitido";
    item[campo].vinculadoAoOrcamentoId = orcamentoExato.id;
  } else if (item.orcamentos.length > 1) {
    item[campo].status = "precisa_vincular";
  } else {
    item[campo].status = "emitido";
    item[campo].vinculadoAoOrcamentoId = item.orcamentos[0]?.id || null;
  }

  item[campo].atualizadoEm = agora();
}

function registrarArquivoFinanceiro(db, caminhoAbsoluto) {
  if (arquivoDeveSerIgnorado(caminhoAbsoluto, db)) return false;

  const nomeArquivo = path.basename(caminhoAbsoluto);
  const tipo = detectarTipo(nomeArquivo);
  const nomeBase = limparPrefixoDocumento(nomeArquivo);
  const caminho = arquivoRelativo(caminhoAbsoluto);

  if (!nomeBase) return false;

  const item = acharOuCriarItem(db, nomeBase, "servidor");

  const info = {
    nomeArquivo,
    caminho,
    tipo
  };

  if (tipo === "orcamento") {
    registrarOrcamento(item, info);
  }

  if (tipo === "boleto") {
    registrarArquivoDocumento(item, "boleto", info);
  }

  if (tipo === "demonstrativo") {
    registrarArquivoDocumento(item, "demonstrativo", info);
  }

  item.atualizadoEm = agora();

  return true;
}

function sincronizarUploads() {
  const db = limparDbFinanceiro(lerDb());
  const arquivos = listarArquivosRecursivo(UPLOADS_DIR);

  let novos = 0;

  for (const arquivo of arquivos) {
    if (arquivoDeveSerIgnorado(arquivo, db)) continue;
    const antes = JSON.stringify(db.itens);
    registrarArquivoFinanceiro(db, arquivo);
    const depois = JSON.stringify(db.itens);

    if (antes !== depois) novos += 1;
  }

  limparDbFinanceiro(db);
  salvarDb(db);

  return { db, totalArquivosLidos: arquivos.length, alteracoes: novos };
}

function usuarioSessao(req) {
  const sessao = req.session || {};
  const user = sessao.user || sessao.usuario || sessao.currentUser || {};

  const permissoes = Array.isArray(user.permissoes)
    ? user.permissoes
    : Array.isArray(user.permissions)
      ? user.permissions
      : Array.isArray(sessao.permissoes)
        ? sessao.permissoes
        : [];

  const email = String(user.email || sessao.email || "").trim().toLowerCase();
  const adminEmail = String(process.env.ADMIN_EMAIL || "").trim().toLowerCase();

  const superadmin =
    Boolean(user.superadmin || user.isSuperAdmin || sessao.superadmin || sessao.isSuperAdmin) ||
    permissoes.includes("*") ||
    Boolean(adminEmail && email === adminEmail);

  return {
    email,
    nome: user.nome || user.name || sessao.nome || "Usuário",
    permissoes,
    superadmin
  };
}

function permissoesFinanceiro(req) {
  const usuario = usuarioSessao(req);
  const p = usuario.permissoes || [];
  const admin = usuario.superadmin || p.includes("financeiro_admin");

  return {
    visualizar: true,
    editarStatus: admin || p.includes("financeiro_editar_status"),
    vincularArquivos: admin || p.includes("financeiro_vincular_arquivos"),
    editarValores: admin || p.includes("financeiro_editar_valores"),
    admin
  };
}

function resumoFinanceiro(itens) {
  const resumo = {
    totalEventos: itens.length,
    orcamentosGerados: 0,
    boletosEmitidos: 0,
    boletosPendentes: 0,
    demonstrativosEmitidos: 0,
    demonstrativosPendentes: 0,
    pagamentosPendentes: 0,
    pagamentosRecebidos: 0,
    faturados: 0,
    emAberto: 0,
    precisamVincular: 0,
    valorPrevisto: 0,
    valorFaturado: 0
  };

  for (const item of itens) {
    resumo.orcamentosGerados += item.orcamentos?.length || 0;

    if (item.boleto?.status === "emitido" || item.boleto?.status === "enviado") resumo.boletosEmitidos += 1;
    else resumo.boletosPendentes += 1;

    if (item.demonstrativo?.status === "emitido" || item.demonstrativo?.status === "enviado") resumo.demonstrativosEmitidos += 1;
    else resumo.demonstrativosPendentes += 1;

    if (item.pagamento?.status === "pago") resumo.pagamentosRecebidos += 1;
    else resumo.pagamentosPendentes += 1;

    if (item.faturamento?.status === "faturado") resumo.faturados += 1;
    else resumo.emAberto += 1;

    if (item.boleto?.status === "precisa_vincular" || item.demonstrativo?.status === "precisa_vincular") {
      resumo.precisamVincular += 1;
    }

    resumo.valorPrevisto += Number(item.faturamento?.valorPrevisto || 0);
    resumo.valorFaturado += Number(item.faturamento?.valorFaturado || 0);
  }

  return resumo;
}

function ordenarItens(itens) {
  return [...itens].sort((a, b) => {
    return String(b.atualizadoEm || "").localeCompare(String(a.atualizadoEm || ""));
  });
}

function exigirEdicao(req, res, tipo = "status") {
  const p = permissoesFinanceiro(req);

  if (p.admin) return true;
  if (tipo === "status" && p.editarStatus) return true;
  if (tipo === "vincular" && p.vincularArquivos) return true;
  if (tipo === "valores" && p.editarValores) return true;

  res.status(403).json({
    ok: false,
    message: "Sem permissão para editar o Financeiro."
  });

  return false;
}

function registrarFinanceiroCejas(app) {
  app.get("/api/financeiro", (req, res) => {
    const { db } = sincronizarUploads();
    const itens = ordenarItens(db.itens);

    res.json({
      ok: true,
      resumo: resumoFinanceiro(itens),
      itens,
      permissoes: permissoesFinanceiro(req)
    });
  });

  app.post("/api/financeiro/sincronizar", (req, res) => {
    const resultado = sincronizarUploads();
    const itens = ordenarItens(resultado.db.itens);

    res.json({
      ok: true,
      message: "Financeiro sincronizado com os arquivos do servidor.",
      totalArquivosLidos: resultado.totalArquivosLidos,
      alteracoes: resultado.alteracoes,
      resumo: resumoFinanceiro(itens),
      itens,
      permissoes: permissoesFinanceiro(req)
    });
  });

  app.post("/api/financeiro/item", (req, res) => {
    if (!exigirEdicao(req, res, "status")) return;

    const nome = String(req.body.clienteEvento || "").trim();

    if (!nome) {
      return res.status(400).json({
        ok: false,
        message: "Informe o cliente/evento."
      });
    }

    const db = lerDb();
    const item = acharOuCriarItem(db, nome, "manual");

    item.clienteEvento = nome;
    item.dataEvento = req.body.dataEvento || item.dataEvento || "";
    item.observacoes = req.body.observacoes || item.observacoes || "";
    item.atualizadoEm = agora();

    salvarDb(db);

    res.json({
      ok: true,
      item
    });
  });

  app.patch("/api/financeiro/item/:id", (req, res) => {
    const campo = String(req.body.campo || "");

    const tipoPermissao =
      campo === "faturamento" || campo === "pagamento" || campo === "valores"
        ? "valores"
        : "status";

    if (!exigirEdicao(req, res, tipoPermissao)) return;

    const db = lerDb();
    const item = db.itens.find((x) => x.id === req.params.id);

    if (!item) {
      return res.status(404).json({
        ok: false,
        message: "Item financeiro não encontrado."
      });
    }

    if (campo === "boleto" || campo === "demonstrativo") {
      item[campo] = item[campo] || statusDocumentoPadrao();
      item[campo].status = req.body.status || item[campo].status;
      item[campo].atualizadoEm = agora();
    }

    if (campo === "pagamento") {
      item.pagamento = item.pagamento || {};
      item.pagamento.status = req.body.status || item.pagamento.status || "pendente";
      item.pagamento.valorPago = Number(req.body.valorPago ?? item.pagamento.valorPago ?? 0);
      item.pagamento.pagoEm = req.body.pagoEm ?? item.pagamento.pagoEm ?? null;
      item.pagamento.atualizadoEm = agora();
    }

    if (campo === "faturamento") {
      item.faturamento = item.faturamento || {};
      item.faturamento.status = req.body.status || item.faturamento.status || "em_aberto";
      item.faturamento.valorPrevisto = Number(req.body.valorPrevisto ?? item.faturamento.valorPrevisto ?? 0);
      item.faturamento.valorFaturado = Number(req.body.valorFaturado ?? item.faturamento.valorFaturado ?? 0);
      item.faturamento.atualizadoEm = agora();
    }

    if (campo === "observacoes") {
      item.observacoes = String(req.body.observacoes || "");
    }

    item.atualizadoEm = agora();

    salvarDb(db);

    res.json({
      ok: true,
      item
    });
  });

  app.post("/api/financeiro/item/:id/vincular", (req, res) => {
    if (!exigirEdicao(req, res, "vincular")) return;

    const db = lerDb();
    const item = db.itens.find((x) => x.id === req.params.id);

    if (!item) {
      return res.status(404).json({
        ok: false,
        message: "Item financeiro não encontrado."
      });
    }

    const campo = req.body.tipo === "demonstrativo" ? "demonstrativo" : "boleto";
    const orcamentoId = String(req.body.orcamentoId || "");

    if (!item[campo]) item[campo] = statusDocumentoPadrao();

    item[campo].vinculadoAoOrcamentoId = orcamentoId || null;
    item[campo].status = "emitido";
    item[campo].atualizadoEm = agora();
    item.atualizadoEm = agora();

    salvarDb(db);

    res.json({
      ok: true,
      item
    });
  });


  app.post("/api/financeiro/atualizar", (req, res) => {
    const resultado = sincronizarUploads();
    const itens = ordenarItens(resultado.db.itens);

    res.json({
      ok: true,
      message: "Lista financeira atualizada.",
      totalArquivosLidos: resultado.totalArquivosLidos,
      alteracoes: resultado.alteracoes,
      resumo: resumoFinanceiro(itens),
      itens,
      permissoes: permissoesFinanceiro(req)
    });
  });

  app.delete("/api/financeiro/item/:id", (req, res) => {
    if (!exigirEdicao(req, res, "status")) return;

    const db = lerDb();
    if (!Array.isArray(db.ignorados)) db.ignorados = [];

    const index = db.itens.findIndex((x) => x.id === req.params.id);

    if (index === -1) {
      return res.status(404).json({
        ok: false,
        message: "Item financeiro não encontrado."
      });
    }

    const item = db.itens[index];

    const caminhos = [
      ...(item.orcamentos || []).map((x) => x.caminho),
      ...(item.boleto?.arquivos || []).map((x) => x.caminho),
      ...(item.demonstrativo?.arquivos || []).map((x) => x.caminho)
    ].filter(Boolean);

    for (const caminho of caminhos) {
      if (!db.ignorados.includes(caminho)) {
        db.ignorados.push(caminho);
      }
    }

    db.itens.splice(index, 1);
    limparDbFinanceiro(db);
    salvarDb(db);

    return res.json({
      ok: true,
      message: "Controle financeiro apagado."
    });
  });

  console.log("✅ Financeiro CEJAS carregado.");
}

module.exports = {
  registrarFinanceiroCejas
};
