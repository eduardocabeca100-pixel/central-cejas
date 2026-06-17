const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

function usuarioAtual(req) {
  const sessao = req.session || {};
  const usuario = sessao.usuario || sessao.user || sessao.admin || {};

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
      message: "Sessão expirada. Faça login novamente."
    });
  }

  req.cejasUsuario = usuario;
  req.cejasAdminMaster = isAdminMaster(usuario);

  return next();
}

function normalizarStatus(status) {
  const s = String(status || "confirmado").toLowerCase().trim();

  if (s.includes("cancel")) return "cancelado";
  if (s.includes("espera") || s.includes("pendente")) return "em espera";
  return "confirmado";
}

function eventoSupera(evento) {
  return {
    id: evento.id,
    origem: "supera",
    titulo: evento.evento || evento.empresa || "Evento do Supera",
    data: evento.data_evento,
    horaInicial: evento.hora_inicial,
    horaFinal: evento.hora_final,
    status: normalizarStatus(evento.status),
    tipo: "evento",
    sala: evento.sala,
    empresa: evento.empresa,
    responsavelNome: "Supera",
    descricao: evento.bloco_original || "",
    valor: evento.valor || 0,
    participantes: evento.participantes || 0
  };
}

function eventoManual(evento) {
  return {
    id: evento.id,
    origem: "manual",
    titulo: evento.titulo || "Item manual",
    data: evento.data,
    horaInicial: evento.hora_inicial,
    horaFinal: evento.hora_final,
    status: normalizarStatus(evento.status),
    tipo: evento.tipo || "outro",
    responsavelNome: evento.responsavel_nome,
    responsavelEmail: evento.responsavel_email,
    criadoPorNome: evento.criado_por_nome,
    criadoPorEmail: evento.criado_por_email,
    visibilidade: evento.visibilidade,
    descricao: evento.descricao || ""
  };
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

function registrarAgendaPlusApi(app) {
  app.get("/api/agenda-plus/unificada", exigirLogin, async (req, res) => {
    try {
      if (!isSupabaseConfigured()) {
        return res.status(500).json({
          ok: false,
          message: "Supabase não configurado."
        });
      }

      const usuario = req.cejasUsuario;
      const admin = req.cejasAdminMaster;
      const dataFiltro = req.query.data || null;

      let querySupera = supabaseAdmin
        .from("cejas_eventos")
        .select("*")
        .order("data_evento", { ascending: true })
        .order("hora_inicial", { ascending: true });

      if (dataFiltro) {
        querySupera = querySupera.eq("data_evento", dataFiltro);
      }

      let queryManual = supabaseAdmin
        .from("cejas_agenda_manual")
        .select("*")
        .order("data", { ascending: true })
        .order("hora_inicial", { ascending: true });

      if (dataFiltro) {
        queryManual = queryManual.eq("data", dataFiltro);
      }

      if (!admin) {
        queryManual = queryManual.or(
          `criado_por_email.eq.${usuario.email},responsavel_email.eq.${usuario.email},visibilidade.in.(equipe,todos)`
        );
      }

      const [supera, manual] = await Promise.all([querySupera, queryManual]);

      if (supera.error) throw new Error("Supera: " + supera.error.message);
      if (manual.error) throw new Error("Agenda manual: " + manual.error.message);

      const eventos = [
        ...(supera.data || []).map(eventoSupera),
        ...(manual.data || []).map(eventoManual)
      ].sort((a, b) => {
        const da = `${a.data || ""} ${a.horaInicial || ""}`;
        const db = `${b.data || ""} ${b.horaInicial || ""}`;
        return da.localeCompare(db);
      });

      return res.json({
        ok: true,
        admin,
        eventos
      });
    } catch (error) {
      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.post("/api/agenda-plus/manual", exigirLogin, async (req, res) => {
    try {
      if (!isSupabaseConfigured()) {
        return res.status(500).json({
          ok: false,
          message: "Supabase não configurado."
        });
      }

      const usuario = req.cejasUsuario;

      const payload = {
        titulo: req.body.titulo,
        data: req.body.data,
        hora_inicial: req.body.horaInicial || req.body.hora_inicial || null,
        hora_final: req.body.horaFinal || req.body.hora_final || null,
        tipo: req.body.tipo || "outro",
        status: normalizarStatus(req.body.status || "confirmado"),
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

      return res.json({
        ok: true,
        evento: eventoManual(data)
      });
    } catch (error) {
      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.patch("/api/agenda-plus/status/:origem/:id", exigirLogin, async (req, res) => {
    try {
      if (!isSupabaseConfigured()) {
        return res.status(500).json({
          ok: false,
          message: "Supabase não configurado."
        });
      }

      const origem = req.params.origem;
      const id = req.params.id;
      const status = normalizarStatus(req.body.status);

      if (!["confirmado", "em espera", "cancelado"].includes(status)) {
        return res.status(400).json({
          ok: false,
          message: "Status inválido."
        });
      }

      if (origem === "supera") {
        const { data, error } = await supabaseAdmin
          .from("cejas_eventos")
          .update({ status })
          .eq("id", id)
          .select("*")
          .single();

        if (error) throw new Error(error.message);

        await registrarLog(req, "alterou_status_evento_supera", "cejas_eventos", id, {
          status,
          empresa: data.empresa,
          evento: data.evento,
          data: data.data_evento
        });

        return res.json({
          ok: true,
          evento: eventoSupera(data)
        });
      }

      if (origem === "manual") {
        const usuario = req.cejasUsuario;
        const admin = req.cejasAdminMaster;

        const { data: atual, error: atualError } = await supabaseAdmin
          .from("cejas_agenda_manual")
          .select("*")
          .eq("id", id)
          .single();

        if (atualError) throw new Error(atualError.message);

        if (!admin && atual.criado_por_email !== usuario.email && atual.responsavel_email !== usuario.email) {
          return res.status(403).json({
            ok: false,
            message: "Você só pode alterar itens da sua agenda."
          });
        }

        const { data, error } = await supabaseAdmin
          .from("cejas_agenda_manual")
          .update({
            status,
            atualizado_em: new Date().toISOString()
          })
          .eq("id", id)
          .select("*")
          .single();

        if (error) throw new Error(error.message);

        await registrarLog(req, "alterou_status_agenda_manual", "agenda_manual", id, {
          status,
          titulo: data.titulo,
          data: data.data
        });

        return res.json({
          ok: true,
          evento: eventoManual(data)
        });
      }

      return res.status(400).json({
        ok: false,
        message: "Origem inválida."
      });
    } catch (error) {
      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  console.log("✅ Agenda Plus API corrigida e ativa.");
}

module.exports = {
  registrarAgendaPlusApi
};
