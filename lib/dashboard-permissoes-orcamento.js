const fs = require("fs");
const path = require("path");
const { supabaseAdmin, isSupabaseConfigured, SUPABASE_BUCKET } = require("./supabase");

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

const MODULOS = [
  { id: "dashboard", nome: "Painel Geral", href: "/dashboard.html", permissao: "painel" },
  { id: "agenda", nome: "Agenda Dinâmica", href: "/agenda.html", permissao: "agenda" },
  { id: "orcamentos", nome: "Orçamentos", href: "/orcamentos.html", permissao: "orcamentos" },
  { id: "importar", nome: "Importar Relatório", href: "/importar-relatorio.html", permissao: "relatorios" },
  { id: "tarefas", nome: "Tarefas Pendentes", href: "/tarefas.html", permissao: "tarefas" },
  { id: "servidor", nome: "Servidor", href: "/servidor.html", permissao: "servidor" },
  { id: "usuarios", nome: "Acessos / Usuários", href: "/usuarios.html", permissao: "usuarios" },
  { id: "contratos", nome: "Contratos", href: "/contratos.html", permissao: "contratos" },
  { id: "configuracoes", nome: "Configurações", href: "/configuracoes.html", permissao: "configuracoes" }
];

function usuarioSessao(req) {
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
    (email === process.env.ADMIN_EMAIL ? "Eduardo" : email);

  return {
    email,
    nome
  };
}

async function buscarUsuarioSistema(email) {
  if (!email || !isSupabaseConfigured()) return null;

  try {
    const { data, error } = await supabaseAdmin
      .from("cejas_usuarios")
      .select("*")
      .eq("email", email)
      .maybeSingle();

    if (error) {
      console.log("⚠️ Não foi possível buscar usuário no Supabase:", error.message);
      return null;
    }

    return data || null;
  } catch (error) {
    console.log("⚠️ Usuário local usado:", error.message);
    return null;
  }
}

async function montarUsuarioAtual(req) {
  const base = usuarioSessao(req);

  if (process.env.ADMIN_EMAIL && base.email === process.env.ADMIN_EMAIL) {
    return {
      email: base.email,
      nome: "Eduardo",
      cargo: "Superadmin",
      tipo: "superadmin",
      permissoes: ["*"],
      superadmin: true
    };
  }

  const usuarioBanco = await buscarUsuarioSistema(base.email);

  if (usuarioBanco) {
    const permissoes =
      Array.isArray(usuarioBanco.permissoes)
        ? usuarioBanco.permissoes
        : [];

    return {
      email: usuarioBanco.email || base.email,
      nome: usuarioBanco.nome || base.nome,
      cargo: usuarioBanco.cargo || usuarioBanco.funcao || "Comercial",
      tipo: usuarioBanco.tipo_usuario || usuarioBanco.tipo || "comercial",
      permissoes,
      superadmin: permissoes.includes("*")
    };
  }

  // Padrão para usuário não-superadmin ainda não cadastrado.
  return {
    email: base.email,
    nome: base.nome || "Usuário",
    cargo: "Comercial",
    tipo: "comercial",
    permissoes: ["painel", "agenda", "orcamentos", "tarefas", "servidor", "contratos"],
    superadmin: false
  };
}

function permitido(usuario, permissao) {
  if (!usuario) return false;
  if (usuario.superadmin) return true;
  if (Array.isArray(usuario.permissoes) && usuario.permissoes.includes("*")) return true;
  return Array.isArray(usuario.permissoes) && usuario.permissoes.includes(permissao);
}

function nomeSeguro(valor) {
  return String(valor || "SEM NOME")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\w\s.-]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase()
    .slice(0, 90);
}

function pastaEvento({ nomeEvento, empresa, dataEvento }) {
  const data = new Date(`${dataEvento}T12:00:00`);

  if (Number.isNaN(data.getTime())) {
    throw new Error("Data do evento inválida.");
  }

  const ano = String(data.getFullYear());
  const mes = MESES[data.getMonth()];
  const dia = String(data.getDate()).padStart(2, "0");
  const mesNumero = String(data.getMonth() + 1).padStart(2, "0");

  const baseNome = nomeSeguro(nomeEvento || empresa || "EVENTO");
  const pastaNome = `${baseNome} ${dia}.${mesNumero}`;

  return {
    ano,
    mes,
    dia,
    mesNumero,
    pastaNome,
    relativo: path.join(ano, mes, pastaNome),
    storage: `${ano}/${mes}/${pastaNome}`
  };
}

async function registrarLog(req, acao, entidade, entidadeId, detalhes = {}) {
  try {
    if (!isSupabaseConfigured()) return;

    const usuario = await montarUsuarioAtual(req);

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

function registrarDashboardPermissoesOrcamento(app) {
  app.get("/api/usuario-atual", async (req, res) => {
    try {
      const usuario = await montarUsuarioAtual(req);

      const modulos = MODULOS
        .filter((modulo) => permitido(usuario, modulo.permissao))
        .map((modulo) => ({
          id: modulo.id,
          nome: modulo.nome,
          href: modulo.href,
          permissao: modulo.permissao
        }));

      return res.json({
        ok: true,
        usuario,
        modulos
      });
    } catch (error) {
      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  app.post("/api/orcamentos/auto-salvar-servidor", async (req, res) => {
    try {
      const usuario = await montarUsuarioAtual(req);

      if (!permitido(usuario, "orcamentos")) {
        return res.status(403).json({
          ok: false,
          message: "Usuário sem permissão para salvar orçamentos."
        });
      }

      const empresa = req.body.empresa || "";
      const nomeEvento = req.body.nomeEvento || req.body.nome_evento || "";
      const dataEvento = req.body.dataEvento || req.body.data_evento || "";
      const conteudo = req.body.conteudo || req.body.orcamento || {};
      const formato = req.body.formato || "json";

      if (!nomeEvento && !empresa) {
        return res.status(400).json({
          ok: false,
          message: "Informe o nome do evento ou empresa."
        });
      }

      if (!dataEvento) {
        return res.status(400).json({
          ok: false,
          message: "Informe a data do evento."
        });
      }

      const pasta = pastaEvento({ nomeEvento, empresa, dataEvento });

      const dirLocal = path.join(__dirname, "..", "uploads", "servidor", pasta.relativo);
      fs.mkdirSync(dirLocal, { recursive: true });

      const nomeArquivoBase = `ORCAMENTO - ${pasta.pastaNome}`;
      const nomeArquivo = formato === "pdf" ? `${nomeArquivoBase}.pdf` : `${nomeArquivoBase}.json`;
      const arquivoLocal = path.join(dirLocal, nomeArquivo);

      let buffer;

      if (formato === "pdf" && req.body.pdfBase64) {
        buffer = Buffer.from(String(req.body.pdfBase64).replace(/^data:application\/pdf;base64,/, ""), "base64");
      } else {
        const payload = {
          tipo: "orcamento",
          empresa,
          nomeEvento,
          dataEvento,
          pastaServidor: pasta.relativo,
          elaboradoPorNome: usuario.nome,
          elaboradoPorEmail: usuario.email,
          criadoEm: new Date().toISOString(),
          conteudo
        };

        buffer = Buffer.from(JSON.stringify(payload, null, 2), "utf8");
      }

      fs.writeFileSync(arquivoLocal, buffer);

      const storagePath = `${pasta.storage}/${nomeArquivo}`;

      if (isSupabaseConfigured()) {
        const { error } = await supabaseAdmin.storage
          .from(SUPABASE_BUCKET)
          .upload(storagePath, buffer, {
            contentType: formato === "pdf" ? "application/pdf" : "application/json",
            upsert: true
          });

        if (error) {
          console.log("⚠️ Não salvou no Supabase Storage:", error.message);
        }

        try {
          await supabaseAdmin.from("cejas_arquivos").insert({
            nome: nomeArquivo,
            caminho: storagePath,
            tipo: formato === "pdf" ? "application/pdf" : "application/json",
            origem: "orcamento",
            criado_por_email: usuario.email,
            criado_por_nome: usuario.nome
          });
        } catch (arquivoError) {
          console.log("⚠️ Registro em cejas_arquivos ignorado:", arquivoError.message);
        }
      }

      await registrarLog(req, "salvou_orcamento_no_servidor", "orcamento", null, {
        empresa,
        nomeEvento,
        dataEvento,
        pasta: pasta.relativo,
        arquivo: nomeArquivo,
        storagePath
      });

      return res.json({
        ok: true,
        message: "Orçamento salvo automaticamente no servidor.",
        elaboradoPor: usuario.nome,
        pasta: pasta.relativo,
        arquivo: nomeArquivo,
        storagePath
      });
    } catch (error) {
      console.error("❌ Erro ao salvar orçamento no servidor:", error.message);

      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  console.log("✅ Dashboard permissões e orçamento automático carregados.");
}

module.exports = {
  registrarDashboardPermissoesOrcamento
};
