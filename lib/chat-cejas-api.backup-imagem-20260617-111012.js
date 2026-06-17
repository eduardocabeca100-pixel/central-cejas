const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { supabaseAdmin, isSupabaseConfigured } = require("./supabase");

const DATA_DIR = path.join(__dirname, "..", "data");
const CHAT_FILE = path.join(DATA_DIR, "chat-mensagens-local.json");

function garantirDataDir() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

function lerMensagensLocais() {
  try {
    garantirDataDir();

    if (!fs.existsSync(CHAT_FILE)) {
      fs.writeFileSync(CHAT_FILE, JSON.stringify([], null, 2));
    }

    return JSON.parse(fs.readFileSync(CHAT_FILE, "utf8"));
  } catch {
    return [];
  }
}

function salvarMensagensLocais(lista) {
  garantirDataDir();
  fs.writeFileSync(CHAT_FILE, JSON.stringify(lista, null, 2));
}

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

  return {
    email: email ? String(email).toLowerCase() : null,
    nome,
    cargo
  };
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

function estaOnline(presenca) {
  if (!presenca?.online_em) return false;

  const ultima = new Date(presenca.online_em).getTime();
  return Date.now() - ultima <= 1000 * 90;
}

function normalizarUsuario(u) {
  if (!u) return null;

  const email =
    u.email ||
    u.usuario_email ||
    u.login ||
    u.user_email ||
    null;

  if (!email) return null;

  const ativo = u.ativo ?? u.is_active ?? u.active ?? true;

  if (ativo === false || ativo === "false" || ativo === 0) return null;

  return {
    email: String(email).toLowerCase(),
    nome: u.nome || u.name || u.nome_completo || String(email).split("@")[0],
    cargo: u.cargo || u.funcao || u.tipo_usuario || u.tipo || u.role || "Comercial"
  };
}

function usuariosDoArquivoLocal() {
  try {
    const arquivo = path.join(__dirname, "..", "data", "usuarios.json");

    if (!fs.existsSync(arquivo)) return [];

    const bruto = JSON.parse(fs.readFileSync(arquivo, "utf8"));

    let lista = [];

    if (Array.isArray(bruto)) lista = bruto;
    else if (Array.isArray(bruto.usuarios)) lista = bruto.usuarios;
    else if (Array.isArray(bruto.users)) lista = bruto.users;
    else if (typeof bruto === "object" && bruto !== null) lista = Object.values(bruto);

    return lista.map(normalizarUsuario).filter(Boolean);
  } catch {
    return [];
  }
}

async function usuariosDoSupabase() {
  if (!isSupabaseConfigured()) return [];

  try {
    const { data, error } = await supabaseAdmin
      .from("cejas_usuarios")
      .select("*");

    if (error) return [];

    return (data || []).map(normalizarUsuario).filter(Boolean);
  } catch {
    return [];
  }
}

async function chatTabelaExiste() {
  if (!isSupabaseConfigured()) return false;

  try {
    const { error } = await supabaseAdmin
      .from("cejas_chat_mensagens")
      .select("id")
      .limit(1);

    if (error) {
      console.log("⚠️ Chat Supabase indisponível, usando modo local:", error.message);
      return false;
    }

    return true;
  } catch {
    return false;
  }
}

async function atualizarPresenca(usuario) {
  if (!isSupabaseConfigured()) return;

  try {
    await supabaseAdmin
      .from("cejas_chat_presencas")
      .upsert({
        email: usuario.email,
        nome: usuario.nome,
        cargo: usuario.cargo,
        online_em: new Date().toISOString(),
        atualizado_em: new Date().toISOString()
      }, { onConflict: "email" });
  } catch {
    // Se a tabela ainda não existir, não quebra o chat.
  }
}

async function listarUsuariosSistema(usuarioAtualEmail) {
  const usuarios = [];

  if (process.env.ADMIN_EMAIL) {
    usuarios.push({
      email: String(process.env.ADMIN_EMAIL).toLowerCase(),
      nome: "Eduardo",
      cargo: "Superadmin"
    });
  }

  usuarios.push(...usuariosDoArquivoLocal());
  usuarios.push(...await usuariosDoSupabase());

  const mapa = new Map();

  usuarios.forEach((u) => {
    const normalizado = normalizarUsuario(u);

    if (!normalizado) return;
    if (normalizado.email === String(usuarioAtualEmail || "").toLowerCase()) return;

    mapa.set(normalizado.email, normalizado);
  });

  return Array.from(mapa.values()).sort((a, b) => String(a.nome).localeCompare(String(b.nome)));
}

async function buscarPresencas(emails) {
  if (!isSupabaseConfigured() || !emails.length) return [];

  try {
    const { data, error } = await supabaseAdmin
      .from("cejas_chat_presencas")
      .select("*")
      .in("email", emails);

    if (error) return [];

    return data || [];
  } catch {
    return [];
  }
}

async function buscarNaoLidas(usuarioEmail) {
  const usaSupabase = await chatTabelaExiste();

  if (usaSupabase) {
    try {
      const { data, error } = await supabaseAdmin
        .from("cejas_chat_mensagens")
        .select("*")
        .eq("para_email", usuarioEmail)
        .is("lida_em", null)
        .order("criado_em", { ascending: false });

      if (!error) return data || [];
    } catch {}
  }

  return lerMensagensLocais()
    .filter((m) => m.para_email === usuarioEmail && !m.lida_em)
    .sort((a, b) => new Date(b.criado_em) - new Date(a.criado_em));
}

function registrarChatCejasApi(app) {
  app.post("/api/chat/heartbeat", exigirUsuario, async (req, res) => {
    await atualizarPresenca(req.cejasUsuario);

    res.json({
      ok: true,
      usuario: req.cejasUsuario
    });
  });

  app.get("/api/chat/usuarios", exigirUsuario, async (req, res) => {
    try {
      await atualizarPresenca(req.cejasUsuario);

      const usuarios = await listarUsuariosSistema(req.cejasUsuario.email);
      const emails = usuarios.map((u) => u.email);
      const presencas = await buscarPresencas(emails);
      const naoLidas = await buscarNaoLidas(req.cejasUsuario.email);

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
      const usaSupabase = await chatTabelaExiste();

      if (usaSupabase) {
        const { data, error } = await supabaseAdmin
          .from("cejas_chat_mensagens")
          .select("*")
          .eq("conversa_id", id)
          .order("criado_em", { ascending: true })
          .limit(120);

        if (!error) {
          await supabaseAdmin
            .from("cejas_chat_mensagens")
            .update({ lida_em: new Date().toISOString() })
            .eq("conversa_id", id)
            .eq("para_email", req.cejasUsuario.email)
            .is("lida_em", null);

          return res.json({
            ok: true,
            modo: "supabase",
            conversaId: id,
            mensagens: data || []
          });
        }
      }

      const mensagens = lerMensagensLocais();
      const agora = new Date().toISOString();

      mensagens.forEach((m) => {
        if (m.conversa_id === id && m.para_email === req.cejasUsuario.email && !m.lida_em) {
          m.lida_em = agora;
        }
      });

      salvarMensagensLocais(mensagens);

      return res.json({
        ok: true,
        modo: "local",
        conversaId: id,
        mensagens: mensagens
          .filter((m) => m.conversa_id === id)
          .sort((a, b) => new Date(a.criado_em) - new Date(b.criado_em))
          .slice(-120)
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
      const usaSupabase = await chatTabelaExiste();

      if (usaSupabase) {
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

        if (!error) {
          return res.json({
            ok: true,
            modo: "supabase",
            mensagem: data
          });
        }
      }

      const mensagens = lerMensagensLocais();

      const mensagem = {
        id: crypto.randomUUID(),
        conversa_id: id,
        de_email: req.cejasUsuario.email,
        de_nome: req.cejasUsuario.nome,
        para_email: paraEmail,
        para_nome: paraNome,
        texto,
        lida_em: null,
        criado_em: new Date().toISOString()
      };

      mensagens.push(mensagem);
      salvarMensagensLocais(mensagens);

      return res.json({
        ok: true,
        modo: "local",
        mensagem
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

      const mensagens = await buscarNaoLidas(req.cejasUsuario.email);

      res.json({
        ok: true,
        totalNaoLidas: mensagens.length,
        mensagens
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  console.log("✅ Chat Interno CEJAS carregado com fallback local.");
}

module.exports = {
  registrarChatCejasApi
};
