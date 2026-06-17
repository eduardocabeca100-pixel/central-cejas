const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

function usuarioAtual(req) {
  const sessao = req.session || {};
  const usuario = sessao.usuario || sessao.user || sessao.admin || {};

  const email =
    usuario.email ||
    sessao.email ||
    sessao.userEmail ||
    sessao.adminEmail ||
    process.env.ADMIN_EMAIL ||
    "admin@cejas.com.br";

  const nome =
    usuario.nome ||
    usuario.name ||
    sessao.nome ||
    sessao.userName ||
    "Eduardo";

  return { email, nome };
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
    const usuario = usuarioAtual(req);

    await supabaseAdmin.from("cejas_logs_atividades").insert({
      usuario_email: usuario.email,
      usuario_nome: usuario.nome,
      acao,
      entidade,
      entidade_id: entidadeId ? String(entidadeId) : null,
      detalhes,
      ip: req.ip || null
    });
  } catch (error) {
    console.log("⚠️ Log ignorado:", error.message);
  }
}

function registrarAgendaDiaLivre(app, express) {
  app.get("/api/agenda-dia", async (req, res) => {
    try {
      if (!isSupabaseConfigured()) {
        return res.status(500).json({
          ok: false,
          message: "Supabase não configurado."
        });
      }

      const dataFiltro = req.query.data || null;

      let querySupera = supabaseAdmin
        .from("cejas_eventos")
        .select("*")
        .order("data_evento", { ascending: true })
        .order("hora_inicial", { ascending: true });

      if (dataFiltro) {
        querySupera = querySupera.eq("data_evento", dataFiltro);
      }

      const supera = await querySupera;

      if (supera.error) {
        throw new Error("Erro ao buscar eventos do Supera: " + supera.error.message);
      }

      let queryManual = supabaseAdmin
        .from("cejas_agenda_manual")
        .select("*")
        .order("data", { ascending: true })
        .order("hora_inicial", { ascending: true });

      if (dataFiltro) {
        queryManual = queryManual.eq("data", dataFiltro);
      }

      const manual = await queryManual;

      if (manual.error) {
        throw new Error("Erro ao buscar agenda manual: " + manual.error.message);
      }

      const eventos = [
        ...(manual.data || []).map(eventoManual),
        ...(supera.data || []).map(eventoSupera)
      ].sort((a, b) => {
        // Prioridade: agenda manual sempre primeiro.
        if (a.origem !== b.origem) {
          if (a.origem === "manual") return -1;
          if (b.origem === "manual") return 1;
        }

        const da = `${a.data || ""} ${a.horaInicial || ""}`;
        const db = `${b.data || ""} ${b.horaInicial || ""}`;
        return da.localeCompare(db);
      });

      return res.json({
        ok: true,
        eventos
      });
    } catch (error) {
      console.error("❌ Erro em /api/agenda-dia:", error.message);

      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.post("/api/agenda-dia/manual", express.json({ limit: "2mb" }), async (req, res) => {
    try {
      if (!isSupabaseConfigured()) {
        return res.status(500).json({
          ok: false,
          message: "Supabase não configurado."
        });
      }

      const usuario = usuarioAtual(req);

      const payload = {
        titulo: req.body.titulo,
        data: req.body.data,
        hora_inicial: req.body.horaInicial || null,
        hora_final: req.body.horaFinal || null,
        tipo: req.body.tipo || "outro",
        status: normalizarStatus(req.body.status || "confirmado"),
        visibilidade: req.body.visibilidade || "privado",
        descricao: req.body.descricao || null,
        responsavel_email: usuario.email,
        responsavel_nome: usuario.nome,
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
      console.error("❌ Erro ao salvar agenda manual:", error.message);

      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.patch("/api/agenda-dia/status/:origem/:id", express.json({ limit: "2mb" }), async (req, res) => {
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
      console.error("❌ Erro ao alterar status:", error.message);

      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  console.log("✅ Agenda Dia Livre carregada antes das travas de sessão.");
}

module.exports = {
  registrarAgendaDiaLivre
};
