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
    null;

  const nome =
    usuario.nome ||
    usuario.name ||
    sessao.nome ||
    sessao.userName ||
    (email === process.env.ADMIN_EMAIL ? "Eduardo" : email || "Usuário");

  const cargo =
    usuario.cargo ||
    usuario.funcao ||
    usuario.tipo_usuario ||
    usuario.tipo ||
    usuario.role ||
    sessao.cargo ||
    (email === process.env.ADMIN_EMAIL ? "Superadmin" : "Comercial");

  return { email, nome, cargo };
}

function exigirUsuario(req, res, next) {
  const usuario = usuarioAtual(req);

  if (!usuario.email) {
    return res.status(401).json({
      ok: false,
      message: "Sessão expirada."
    });
  }

  req.cejasUsuario = usuario;
  next();
}

function conversaId(a, b) {
  return [String(a).toLowerCase(), String(b).toLowerCase()].sort().join("__");
}

async function atualizarPresenca(usuario) {
  if (!isSupabaseConfigured()) return;

  await supabaseAdmin
    .from("cejas_chat_presencas")
    .upsert({
      email: usuario.email,
      nome: usuario.nome,
      cargo: usuario.cargo,
      online_em: new Date().toISOString(),
      atualizado_em: new Date().toISOString()
    }, { onConflict: "email" });
}

function estaOnline(presenca) {
  if (!presenca?.online_em) return false;

  const ultima = new Date(presenca.online_em).getTime();
  const agora = Date.now();

  return agora - ultima <= 1000 * 90;
}

async function listarUsuariosSistema(usuarioAtualEmail) {
  const usuarios = [];

  if (process.env.ADMIN_EMAIL) {
    usuarios.push({
      email: process.env.ADMIN_EMAIL,
      nome: "Eduardo",
      cargo: "Superadmin"
    });
  }

  if (isSupabaseConfigured()) {
    const { data, error } = await supabaseAdmin
      .from("cejas_usuarios")
      .select("*");

    if (!error && Array.isArray(data)) {
      data.forEach((u) => {
        if (!u.email) return;
        if (u.ativo === false) return;

        usuarios.push({
          email: u.email,
          nome: u.nome || u.name || u.email,
          cargo: u.cargo || u.funcao || u.tipo_usuario || u.tipo || "Comercial"
        });
      });
    }
  }

  const mapa = new Map();

  usuarios.forEach((u) => {
    const email = String(u.email || "").toLowerCase();

    if (!email) return;
    if (email === String(usuarioAtualEmail || "").toLowerCase()) return;

    mapa.set(email, {
      ...u,
      email
    });
  });

  return Array.from(mapa.values()).sort((a, b) => String(a.nome).localeCompare(String(b.nome)));
}

function registrarChatCejasApi(app) {
  app.post("/api/chat/heartbeat", exigirUsuario, async (req, res) => {
    try {
      await atualizarPresenca(req.cejasUsuario);

      res.json({
        ok: true,
        usuario: req.cejasUsuario
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.get("/api/chat/usuarios", exigirUsuario, async (req, res) => {
    try {
      await atualizarPresenca(req.cejasUsuario);

      const usuarios = await listarUsuariosSistema(req.cejasUsuario.email);

      const emails = usuarios.map((u) => u.email);

      let presencas = [];
      let naoLidas = [];

      if (emails.length) {
        const pres = await supabaseAdmin
          .from("cejas_chat_presencas")
          .select("*")
          .in("email", emails);

        if (!pres.error) presencas = pres.data || [];

        const unread = await supabaseAdmin
          .from("cejas_chat_mensagens")
          .select("de_email")
          .eq("para_email", req.cejasUsuario.email)
          .is("lida_em", null);

        if (!unread.error) naoLidas = unread.data || [];
      }

      const mapaPresenca = new Map(presencas.map((p) => [String(p.email).toLowerCase(), p]));
      const contagemNaoLidas = {};

      naoLidas.forEach((m) => {
        const email = String(m.de_email || "").toLowerCase();
        contagemNaoLidas[email] = (contagemNaoLidas[email] || 0) + 1;
      });

      const resultado = usuarios.map((u) => {
        const p = mapaPresenca.get(String(u.email).toLowerCase());

        return {
          ...u,
          online: estaOnline(p),
          ultimaPresenca: p?.online_em || null,
          naoLidas: contagemNaoLidas[String(u.email).toLowerCase()] || 0
        };
      });

      res.json({
        ok: true,
        usuarioAtual: req.cejasUsuario,
        usuarios: resultado
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.get("/api/chat/mensagens", exigirUsuario, async (req, res) => {
    try {
      await atualizarPresenca(req.cejasUsuario);

      const outroEmail = String(req.query.com || "").toLowerCase();

      if (!outroEmail) {
        return res.status(400).json({
          ok: false,
          message: "Informe o usuário da conversa."
        });
      }

      const id = conversaId(req.cejasUsuario.email, outroEmail);

      const { data, error } = await supabaseAdmin
        .from("cejas_chat_mensagens")
        .select("*")
        .eq("conversa_id", id)
        .order("criado_em", { ascending: true })
        .limit(120);

      if (error) throw new Error(error.message);

      await supabaseAdmin
        .from("cejas_chat_mensagens")
        .update({ lida_em: new Date().toISOString() })
        .eq("conversa_id", id)
        .eq("para_email", req.cejasUsuario.email)
        .is("lida_em", null);

      res.json({
        ok: true,
        conversaId: id,
        mensagens: data || []
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.post("/api/chat/mensagens", exigirUsuario, async (req, res) => {
    try {
      await atualizarPresenca(req.cejasUsuario);

      const paraEmail = String(req.body.paraEmail || req.body.para_email || "").toLowerCase();
      const paraNome = req.body.paraNome || req.body.para_nome || paraEmail;
      const texto = String(req.body.texto || "").trim();

      if (!paraEmail) {
        return res.status(400).json({
          ok: false,
          message: "Informe o destinatário."
        });
      }

      if (!texto) {
        return res.status(400).json({
          ok: false,
          message: "Digite uma mensagem."
        });
      }

      const id = conversaId(req.cejasUsuario.email, paraEmail);

      const { data, error } = await supabaseAdmin
        .from("cejas_chat_mensagens")
        .insert({
          conversa_id: id,
          de_email: req.cejasUsuario.email,
          de_nome: req.cejasUsuario.nome,
          para_email: paraEmail,
          para_nome: paraNome,
          texto
        })
        .select("*")
        .single();

      if (error) throw new Error(error.message);

      res.json({
        ok: true,
        mensagem: data
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.get("/api/chat/resumo", exigirUsuario, async (req, res) => {
    try {
      await atualizarPresenca(req.cejasUsuario);

      const { data, error } = await supabaseAdmin
        .from("cejas_chat_mensagens")
        .select("*")
        .eq("para_email", req.cejasUsuario.email)
        .is("lida_em", null)
        .order("criado_em", { ascending: false });

      if (error) throw new Error(error.message);

      res.json({
        ok: true,
        totalNaoLidas: (data || []).length,
        mensagens: data || []
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  console.log("✅ Chat Interno CEJAS carregado.");
}

module.exports = {
  registrarChatCejasApi
};
