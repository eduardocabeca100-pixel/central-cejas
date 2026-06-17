const fs = require("fs");
const path = require("path");
const multer = require("multer");
const { supabaseAdmin, isSupabaseConfigured, SUPABASE_BUCKET } = require("./supabase");

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }
});

const MESES = [
  "01 JANEIRO",
  "02 FEVEREIRO",
  "03 MARÇO",
  "04 ABRIL",
  "05 MAIO",
  "06 JUNHO",
  "07 JULHO",
  "08 AGOSTO",
  "09 SETEMBRO",
  "10 OUTUBRO",
  "11 NOVEMBRO",
  "12 DEZEMBRO"
];

function usuarioAtual(req) {
  const sessao = req.session || {};
  const usuario = sessao.usuario || sessao.user || sessao.admin || req.usuario || {};

  const email =
    usuario.email ||
    sessao.email ||
    sessao.userEmail ||
    null;

  const nome =
    usuario.nome ||
    usuario.name ||
    sessao.nome ||
    sessao.userName ||
    email ||
    "Usuário";

  const permissoes =
    usuario.permissoes ||
    usuario.permissions ||
    sessao.permissoes ||
    [];

  return {
    email,
    nome,
    permissoes,
    tipo: usuario.tipo || usuario.tipo_usuario || usuario.role || sessao.tipo || null
  };
}

function isAdminMaster(usuario) {
  if (!usuario || !usuario.email) return false;

  if (process.env.ADMIN_EMAIL && usuario.email === process.env.ADMIN_EMAIL) return true;
  if (usuario.tipo === "admin_master") return true;
  if (Array.isArray(usuario.permissoes) && usuario.permissoes.includes("*")) return true;

  return false;
}

function exigirLogin(req, res, next) {
  const usuario = usuarioAtual(req);

  if (!usuario.email) {
    return res.status(401).json({
      ok: false,
      message: "Sessão expirada."
    });
  }

  req.cejasUsuario = usuario;
  req.cejasAdminMaster = isAdminMaster(usuario);

  return next();
}

function exigirAdminMaster(req, res, next) {
  if (!req.cejasAdminMaster) {
    return res.status(403).json({
      ok: false,
      message: "Acesso permitido apenas ao administrador principal."
    });
  }

  return next();
}

async function registrarLog(req, acao, entidade, entidadeId, detalhes = {}) {
  try {
    if (!isSupabaseConfigured()) return;

    const usuario = req.cejasUsuario || usuarioAtual(req);

    await supabaseAdmin.from("cejas_logs_atividades").insert({
      usuario_email: usuario.email || null,
      usuario_nome: usuario.nome || null,
      acao,
      entidade,
      entidade_id: entidadeId ? String(entidadeId) : null,
      detalhes,
      ip: req.ip || null
    });
  } catch (error) {
    console.error("⚠️ Falha ao registrar log:", error.message);
  }
}

function nomeSeguro(valor) {
  return String(valor || "SEM NOME")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\w\s.-]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase()
    .slice(0, 80);
}

function pastaPorEvento({ empresa, dataEvento }) {
  const data = new Date(`${dataEvento}T12:00:00`);

  if (Number.isNaN(data.getTime())) {
    throw new Error("Data do evento inválida.");
  }

  const ano = String(data.getFullYear());
  const mes = MESES[data.getMonth()];
  const dia = String(data.getDate()).padStart(2, "0");
  const mesNumero = String(data.getMonth() + 1).padStart(2, "0");

  const empresaLimpa = nomeSeguro(empresa);
  const pastaEvento = `${empresaLimpa} ${dia}.${mesNumero}`;

  return {
    ano,
    mes,
    pastaEvento,
    caminhoRelativo: path.join(ano, mes, pastaEvento),
    caminhoStorage: `${ano}/${mes}/${pastaEvento}`
  };
}

async function buscarConfig() {
  if (!isSupabaseConfigured()) {
    return null;
  }

  const { data, error } = await supabaseAdmin
    .from("cejas_configuracoes_sistema")
    .select("*")
    .eq("id", "principal")
    .maybeSingle();

  if (error) throw new Error(error.message);

  return data;
}

async function salvarConfig(parcial, usuarioEmail) {
  if (!isSupabaseConfigured()) {
    throw new Error("Supabase não configurado.");
  }

  const payload = {
    id: "principal",
    ...parcial,
    atualizado_por_email: usuarioEmail || null,
    atualizado_em: new Date().toISOString()
  };

  const { data, error } = await supabaseAdmin
    .from("cejas_configuracoes_sistema")
    .upsert(payload, { onConflict: "id" })
    .select("*")
    .single();

  if (error) throw new Error(error.message);

  return data;
}

function contentTypePorExt(ext) {
  const e = String(ext || "").toLowerCase();

  if (e === ".png") return "image/png";
  if (e === ".jpg" || e === ".jpeg") return "image/jpeg";
  if (e === ".svg") return "image/svg+xml";
  if (e === ".ico") return "image/x-icon";
  if (e === ".webp") return "image/webp";

  return "application/octet-stream";
}

function registrarRotasCejasFase2(app) {
  app.get("/api/logs-atividades", exigirLogin, exigirAdminMaster, async (req, res) => {
    try {
      const limite = Math.min(Number(req.query.limite || 100), 300);

      const { data, error } = await supabaseAdmin
        .from("cejas_logs_atividades")
        .select("*")
        .order("criado_em", { ascending: false })
        .limit(limite);

      if (error) throw new Error(error.message);

      res.json({ ok: true, logs: data || [] });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.get("/api/agenda/manual", exigirLogin, async (req, res) => {
    try {
      const usuario = req.cejasUsuario;
      const admin = req.cejasAdminMaster;

      let query = supabaseAdmin
        .from("cejas_agenda_manual")
        .select("*")
        .order("data", { ascending: true })
        .order("hora_inicial", { ascending: true });

      if (!admin) {
        query = query.or(`criado_por_email.eq.${usuario.email},responsavel_email.eq.${usuario.email},visibilidade.in.(equipe,todos)`);
      }

      const { data, error } = await query;

      if (error) throw new Error(error.message);

      res.json({
        ok: true,
        admin,
        eventos: data || []
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.post("/api/agenda/manual", exigirLogin, async (req, res) => {
    try {
      const usuario = req.cejasUsuario;

      const payload = {
        titulo: req.body.titulo,
        data: req.body.data,
        hora_inicial: req.body.horaInicial || req.body.hora_inicial || null,
        hora_final: req.body.horaFinal || req.body.hora_final || null,
        tipo: req.body.tipo || "outro",
        status: req.body.status || "confirmado",
        visibilidade: req.body.visibilidade || "privado",
        descricao: req.body.descricao || null,
        responsavel_email: req.body.responsavelEmail || usuario.email,
        responsavel_nome: req.body.responsavelNome || usuario.nome,
        criado_por_email: usuario.email,
        criado_por_nome: usuario.nome
      };

      if (!payload.titulo || !payload.data) {
        return res.status(400).json({
          ok: false,
          message: "Informe título e data."
        });
      }

      const { data, error } = await supabaseAdmin
        .from("cejas_agenda_manual")
        .insert(payload)
        .select("*")
        .single();

      if (error) throw new Error(error.message);

      await registrarLog(req, "criou_item_agenda", "agenda_manual", data.id, {
        titulo: data.titulo,
        data: data.data,
        status: data.status
      });

      res.json({ ok: true, evento: data });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.put("/api/agenda/manual/:id", exigirLogin, async (req, res) => {
    try {
      const usuario = req.cejasUsuario;
      const admin = req.cejasAdminMaster;
      const id = req.params.id;

      const { data: atual, error: atualError } = await supabaseAdmin
        .from("cejas_agenda_manual")
        .select("*")
        .eq("id", id)
        .single();

      if (atualError) throw new Error(atualError.message);

      if (!admin && atual.criado_por_email !== usuario.email && atual.responsavel_email !== usuario.email) {
        return res.status(403).json({
          ok: false,
          message: "Você só pode editar itens da sua agenda."
        });
      }

      const payload = {
        titulo: req.body.titulo ?? atual.titulo,
        data: req.body.data ?? atual.data,
        hora_inicial: req.body.horaInicial ?? req.body.hora_inicial ?? atual.hora_inicial,
        hora_final: req.body.horaFinal ?? req.body.hora_final ?? atual.hora_final,
        tipo: req.body.tipo ?? atual.tipo,
        status: req.body.status ?? atual.status,
        visibilidade: req.body.visibilidade ?? atual.visibilidade,
        descricao: req.body.descricao ?? atual.descricao,
        atualizado_em: new Date().toISOString()
      };

      const { data, error } = await supabaseAdmin
        .from("cejas_agenda_manual")
        .update(payload)
        .eq("id", id)
        .select("*")
        .single();

      if (error) throw new Error(error.message);

      await registrarLog(req, "alterou_item_agenda", "agenda_manual", id, payload);

      res.json({ ok: true, evento: data });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.delete("/api/agenda/manual/:id", exigirLogin, async (req, res) => {
    try {
      const usuario = req.cejasUsuario;
      const admin = req.cejasAdminMaster;
      const id = req.params.id;

      const { data: atual, error: atualError } = await supabaseAdmin
        .from("cejas_agenda_manual")
        .select("*")
        .eq("id", id)
        .single();

      if (atualError) throw new Error(atualError.message);

      if (!admin && atual.criado_por_email !== usuario.email && atual.responsavel_email !== usuario.email) {
        return res.status(403).json({
          ok: false,
          message: "Você só pode apagar itens da sua agenda."
        });
      }

      const { error } = await supabaseAdmin
        .from("cejas_agenda_manual")
        .delete()
        .eq("id", id);

      if (error) throw new Error(error.message);

      await registrarLog(req, "apagou_item_agenda", "agenda_manual", id, {
        titulo: atual.titulo,
        data: atual.data
      });

      res.json({ ok: true });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.get("/api/configuracoes-sistema", exigirLogin, async (req, res) => {
    try {
      const config = await buscarConfig();

      res.json({
        ok: true,
        config: {
          ...config,
          logo_url: config?.logo_path ? `/api/configuracoes-sistema/asset/logo?ts=${Date.now()}` : null,
          favicon_url: config?.favicon_path ? `/api/configuracoes-sistema/asset/favicon?ts=${Date.now()}` : null,
          assinatura_url: config?.assinatura_path ? `/api/configuracoes-sistema/asset/assinatura?ts=${Date.now()}` : null
        }
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.put("/api/configuracoes-sistema", exigirLogin, exigirAdminMaster, async (req, res) => {
    try {
      const config = await salvarConfig({
        nome_sistema: req.body.nomeSistema || req.body.nome_sistema || "Sistema de Gestão CEJAS",
        cor_principal: req.body.corPrincipal || req.body.cor_principal || "#8b5cf6",
        dados_cejas: req.body.dadosCejas || req.body.dados_cejas || {}
      }, req.cejasUsuario.email);

      await registrarLog(req, "alterou_configuracoes_sistema", "configuracoes_sistema", "principal", {
        nome_sistema: config.nome_sistema,
        cor_principal: config.cor_principal
      });

      res.json({ ok: true, config });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.post("/api/configuracoes-sistema/upload", exigirLogin, exigirAdminMaster, upload.single("arquivo"), async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ ok: false, message: "Nenhum arquivo enviado." });
      }

      const tipo = req.body.tipo;

      if (!["logo", "favicon", "assinatura"].includes(tipo)) {
        return res.status(400).json({ ok: false, message: "Tipo inválido." });
      }

      const ext = path.extname(req.file.originalname || "").toLowerCase() || ".png";
      const storagePath = `sistema/${tipo}-${Date.now()}${ext}`;

      const { error } = await supabaseAdmin.storage
        .from(SUPABASE_BUCKET)
        .upload(storagePath, req.file.buffer, {
          contentType: req.file.mimetype || contentTypePorExt(ext),
          upsert: true
        });

      if (error) throw new Error(error.message);

      const coluna = `${tipo}_path`;

      const config = await salvarConfig({
        [coluna]: storagePath
      }, req.cejasUsuario.email);

      await registrarLog(req, `alterou_${tipo}_sistema`, "configuracoes_sistema", "principal", {
        path: storagePath
      });

      res.json({
        ok: true,
        config,
        url: `/api/configuracoes-sistema/asset/${tipo}?ts=${Date.now()}`
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.get("/api/configuracoes-sistema/asset/:tipo", async (req, res) => {
    try {
      const tipo = req.params.tipo;

      if (!["logo", "favicon", "assinatura"].includes(tipo)) {
        return res.status(404).send("Arquivo não encontrado.");
      }

      const config = await buscarConfig();
      const storagePath = config?.[`${tipo}_path`];

      if (!storagePath) {
        return res.status(404).send("Arquivo não encontrado.");
      }

      const { data, error } = await supabaseAdmin.storage
        .from(SUPABASE_BUCKET)
        .download(storagePath);

      if (error) throw new Error(error.message);

      const arrayBuffer = await data.arrayBuffer();
      const buffer = Buffer.from(arrayBuffer);

      res.setHeader("Content-Type", data.type || contentTypePorExt(path.extname(storagePath)));
      res.send(buffer);
    } catch (error) {
      res.status(500).send(error.message);
    }
  });

  app.post("/api/orcamentos/salvar-servidor", exigirLogin, async (req, res) => {
    try {
      const usuario = req.cejasUsuario;
      const empresa = req.body.empresa;
      const dataEvento = req.body.dataEvento || req.body.data_evento;
      const nomeEvento = req.body.nomeEvento || req.body.nome_evento || "ORÇAMENTO";
      const conteudo = req.body.conteudo || req.body.orcamento || {};

      if (!empresa || !dataEvento) {
        return res.status(400).json({
          ok: false,
          message: "Informe empresa e data do evento."
        });
      }

      const pasta = pastaPorEvento({ empresa, dataEvento });

      const baseDir = path.join(__dirname, "..", "uploads", "servidor", pasta.caminhoRelativo);
      fs.mkdirSync(baseDir, { recursive: true });

      const arquivoNome = `ORCAMENTO - ${nomeSeguro(empresa)} - ${String(dataEvento).split("-").reverse().join(".")}.json`;
      const arquivoPath = path.join(baseDir, arquivoNome);

      const payload = {
        empresa,
        dataEvento,
        nomeEvento,
        criadoPorEmail: usuario.email,
        criadoPorNome: usuario.nome,
        criadoEm: new Date().toISOString(),
        conteudo
      };

      const buffer = Buffer.from(JSON.stringify(payload, null, 2), "utf8");

      fs.writeFileSync(arquivoPath, buffer);

      const storagePath = `${pasta.caminhoStorage}/${arquivoNome}`;

      if (isSupabaseConfigured()) {
        const { error } = await supabaseAdmin.storage
          .from(SUPABASE_BUCKET)
          .upload(storagePath, buffer, {
            contentType: "application/json",
            upsert: true
          });

        if (error) {
          console.error("⚠️ Não salvou orçamento no Storage:", error.message);
        }
      }

      await registrarLog(req, "salvou_orcamento_servidor", "orcamento", null, {
        empresa,
        dataEvento,
        pasta: pasta.caminhoRelativo,
        arquivo: arquivoNome,
        storagePath
      });

      res.json({
        ok: true,
        message: "Orçamento salvo no servidor.",
        elaboradoPor: usuario.nome,
        pasta: pasta.caminhoRelativo,
        arquivo: arquivoNome,
        storagePath
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  console.log("✅ Rotas CEJAS Fase 2 carregadas: segurança, logs, agenda manual e configurações.");
}

module.exports = {
  registrarRotasCejasFase2
};
