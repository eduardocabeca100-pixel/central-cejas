const fs = require("fs");
const path = require("path");
const multer = require("multer");
const { supabaseAdmin, isSupabaseConfigured, SUPABASE_BUCKET } = require("./supabase");

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024 }
});

function usuarioAtual(req) {
  const sessao = req.session || {};
  const usuario = sessao.usuario || sessao.user || sessao.admin || {};

  const email =
    usuario.email ||
    sessao.email ||
    sessao.userEmail ||
    sessao.adminEmail ||
    null;

  const nome =
    usuario.nome ||
    usuario.name ||
    sessao.nome ||
    sessao.userName ||
    (email === process.env.ADMIN_EMAIL ? "Eduardo" : email);

  const permissoes =
    usuario.permissoes ||
    usuario.permissions ||
    sessao.permissoes ||
    [];

  const tipo =
    usuario.tipo ||
    usuario.tipo_usuario ||
    usuario.role ||
    sessao.tipo ||
    null;

  return { email, nome, permissoes, tipo };
}

function ehSuperadmin(req) {
  const usuario = usuarioAtual(req);

  if (process.env.ADMIN_EMAIL && usuario.email === process.env.ADMIN_EMAIL) return true;
  if (usuario.tipo === "superadmin" || usuario.tipo === "admin_master") return true;
  if (Array.isArray(usuario.permissoes) && usuario.permissoes.includes("*")) return true;

  return false;
}

function exigirSuperadmin(req, res, next) {
  if (!ehSuperadmin(req)) {
    return res.status(403).json({
      ok: false,
      message: "Somente o Superadmin pode acessar ou alterar as configurações do sistema."
    });
  }

  next();
}

function configPadrao() {
  return {
    identidade: {
      nomeSistema: "Sistema de Gestão CEJAS",
      subtitulo: "Painel Administrativo",
      corPrincipal: "#8b5cf6",
      corSecundaria: "#ec4899",
      corBotao: "#2563eb",
      rodape: "Sistema Comercial CEJAS v2026"
    },
    cejas: {
      nomeInstitucional: "Centro Empresarial de Jaraguá do Sul - CEJAS",
      cnpj: "83.784.124/0001-32",
      endereco: "Rua Octaviano Lombardi, 100. Czerniewicz",
      cidadeUf: "Jaraguá do Sul - SC",
      telefone: "(47) 3275-7000",
      email: "marcel@cejas.com.br",
      pix: "83.784.124/0001-32",
      banco: "Sicredi Norte",
      responsavelPadrao: "Eduardo Cabeça"
    },
    orcamentos: {
      validadeHoras: 72,
      horarioLimite: "22:00",
      textoCondicoes: "Orçamento válido por 72 horas. A pré-reserva garante o espaço por este período; após o prazo, o evento é considerado cancelado.",
      textoAtencao: "ATENÇÃO: O HORÁRIO LIMITE PARA FECHAMENTO TOTAL DO PRÉDIO É IMPRETERIVELMENTE ÀS 22:00H.",
      formasPagamento: "Transferência/Depósito: Sicredi Norte\\nBoleto Bancário via Sicredi Norte.\\nPIX CNPJ: 83.784.124/0001-32",
      assinaturaNome: "Eduardo Cabeça",
      assinaturaContato: "Cel: (47) 98835-7184\\nE-mail: marcel@cejas.com.br"
    },
    comercial: {
      prazoRetornoHoras: 72,
      pipeline: [
        "Novo orçamento",
        "Enviado ao cliente",
        "Aguardando resposta",
        "Aprovado",
        "Perdido / Cancelado"
      ],
      modelosMensagem: {
        envioOrcamento: "Olá! Segue orçamento conforme solicitado. A proposta possui validade de 72 horas.",
        followup24h: "Olá! Passando para confirmar se conseguiu avaliar o orçamento enviado.",
        followup72h: "Olá! O orçamento enviado está próximo do vencimento. Posso manter sua pré-reserva?",
        confirmacao: "Reserva confirmada. Em breve encaminhamos os próximos detalhes.",
        cancelamento: "Conforme alinhado, o orçamento/reserva será cancelado. Ficamos à disposição."
      }
    },
    checklist: {
      itens: [
        "Orçamento enviado",
        "Retorno feito em até 72h",
        "Cliente confirmou o evento",
        "Contrato/termo encaminhado",
        "Boleto ou dados de pagamento enviados",
        "Sala reservada",
        "Recursos/equipamentos conferidos",
        "Café/apoio solicitado, se houver",
        "Equipe interna avisada"
      ]
    },
    painelDia: {
      mostrarEventosHoje: true,
      mostrarSalas: true,
      mostrarRecursos: true,
      mostrarPendencias: true,
      mostrarResponsavel: true,
      mostrarStatusComercial: true
    }
  };
}

async function registrarLog(req, acao, entidade, entidadeId, detalhes = {}) {
  try {
    if (!isSupabaseConfigured()) return;

    const usuario = usuarioAtual(req);

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
    console.log("⚠️ Log ignorado:", error.message);
  }
}

async function buscarConfig() {
  if (!isSupabaseConfigured()) {
    throw new Error("Supabase não configurado.");
  }

  const { data, error } = await supabaseAdmin
    .from("cejas_configuracoes_sistema")
    .select("*")
    .eq("id", "principal")
    .maybeSingle();

  if (error) throw new Error(error.message);

  if (!data) {
    const padrao = configPadrao();

    const criado = await supabaseAdmin
      .from("cejas_configuracoes_sistema")
      .insert({
        id: "principal",
        nome_sistema: padrao.identidade.nomeSistema,
        cor_principal: padrao.identidade.corPrincipal,
        dados_cejas: padrao
      })
      .select("*")
      .single();

    if (criado.error) throw new Error(criado.error.message);

    return criado.data;
  }

  return {
    ...data,
    dados_cejas: {
      ...configPadrao(),
      ...(data.dados_cejas || {})
    }
  };
}

function extensaoSegura(nome) {
  const ext = path.extname(nome || "").toLowerCase();

  if ([".png", ".jpg", ".jpeg", ".svg", ".ico", ".webp"].includes(ext)) {
    return ext;
  }

  return ".png";
}

function contentType(ext) {
  if (ext === ".png") return "image/png";
  if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
  if (ext === ".svg") return "image/svg+xml";
  if (ext === ".ico") return "image/x-icon";
  if (ext === ".webp") return "image/webp";
  return "application/octet-stream";
}

function registrarConfiguracoesCejas(app) {
  app.get("/api/configuracoes-cejas", exigirSuperadmin, async (req, res) => {
    try {
      const config = await buscarConfig();

      res.json({
        ok: true,
        config: {
          ...config,
          logo_url: config.logo_path ? `/api/configuracoes-cejas/asset/logo?ts=${Date.now()}` : null,
          favicon_url: config.favicon_path ? `/api/configuracoes-cejas/asset/favicon?ts=${Date.now()}` : null,
          assinatura_url: config.assinatura_path ? `/api/configuracoes-cejas/asset/assinatura?ts=${Date.now()}` : null
        }
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.put("/api/configuracoes-cejas", exigirSuperadmin, async (req, res) => {
    try {
      const usuario = usuarioAtual(req);
      const payload = req.body || {};
      const dados = {
        ...configPadrao(),
        ...payload
      };

      const { data, error } = await supabaseAdmin
        .from("cejas_configuracoes_sistema")
        .upsert({
          id: "principal",
          nome_sistema: dados.identidade?.nomeSistema || "Sistema de Gestão CEJAS",
          cor_principal: dados.identidade?.corPrincipal || "#8b5cf6",
          dados_cejas: dados,
          atualizado_por_email: usuario.email,
          atualizado_em: new Date().toISOString()
        }, { onConflict: "id" })
        .select("*")
        .single();

      if (error) throw new Error(error.message);

      await registrarLog(req, "alterou_configuracoes", "configuracoes", "principal", {
        secoes: Object.keys(dados)
      });

      res.json({ ok: true, config: data });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.post("/api/configuracoes-cejas/upload", exigirSuperadmin, upload.single("arquivo"), async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ ok: false, message: "Nenhum arquivo enviado." });
      }

      const tipo = req.body.tipo;

      if (!["logo", "favicon", "assinatura"].includes(tipo)) {
        return res.status(400).json({ ok: false, message: "Tipo inválido." });
      }

      const ext = extensaoSegura(req.file.originalname);
      const storagePath = `sistema/${tipo}-${Date.now()}${ext}`;

      if (isSupabaseConfigured()) {
        const uploadResult = await supabaseAdmin.storage
          .from(SUPABASE_BUCKET)
          .upload(storagePath, req.file.buffer, {
            contentType: req.file.mimetype || contentType(ext),
            upsert: true
          });

        if (uploadResult.error) throw new Error(uploadResult.error.message);

        const coluna = `${tipo}_path`;

        const { data, error } = await supabaseAdmin
          .from("cejas_configuracoes_sistema")
          .update({
            [coluna]: storagePath,
            atualizado_por_email: usuarioAtual(req).email,
            atualizado_em: new Date().toISOString()
          })
          .eq("id", "principal")
          .select("*")
          .single();

        if (error) throw new Error(error.message);

        await registrarLog(req, `alterou_${tipo}`, "configuracoes", "principal", {
          path: storagePath
        });

        return res.json({
          ok: true,
          config: data,
          url: `/api/configuracoes-cejas/asset/${tipo}?ts=${Date.now()}`
        });
      }

      const localDir = path.join(__dirname, "..", "uploads", "configuracoes");
      fs.mkdirSync(localDir, { recursive: true });

      const localName = `${tipo}-${Date.now()}${ext}`;
      const localPath = path.join(localDir, localName);
      fs.writeFileSync(localPath, req.file.buffer);

      res.json({
        ok: true,
        url: `/uploads/configuracoes/${localName}`
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });

  app.get("/api/configuracoes-cejas/asset/:tipo", async (req, res) => {
    try {
      const tipo = req.params.tipo;

      if (!["logo", "favicon", "assinatura"].includes(tipo)) {
        return res.status(404).send("Arquivo não encontrado.");
      }

      const config = await buscarConfig();
      const storagePath = config[`${tipo}_path`];

      if (!storagePath) {
        return res.status(404).send("Arquivo não encontrado.");
      }

      const { data, error } = await supabaseAdmin.storage
        .from(SUPABASE_BUCKET)
        .download(storagePath);

      if (error) throw new Error(error.message);

      const arrayBuffer = await data.arrayBuffer();
      const buffer = Buffer.from(arrayBuffer);

      res.setHeader("Content-Type", data.type || contentType(path.extname(storagePath)));
      res.send(buffer);
    } catch (error) {
      res.status(500).send(error.message);
    }
  });

  app.get("/api/configuracoes-cejas/logs", exigirSuperadmin, async (req, res) => {
    try {
      const limite = Math.min(Number(req.query.limite || 80), 300);

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

  console.log("✅ Configurações CEJAS 2.0 carregadas.");
}

module.exports = {
  registrarConfiguracoesCejas
};
