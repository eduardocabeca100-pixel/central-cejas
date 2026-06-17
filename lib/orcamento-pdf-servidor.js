const fs = require("fs");
const path = require("path");
const { supabaseAdmin, isSupabaseConfigured, SUPABASE_BUCKET } = require("./supabase");

const MESES_NOMES = [
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
    (email === process.env.ADMIN_EMAIL ? "Eduardo" : email);

  return { email, nome };
}

function limparAcentos(valor) {
  return String(valor || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
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

function normalizarData(dataEvento) {
  if (!dataEvento) return null;

  const texto = String(dataEvento).trim();

  if (/^\d{4}-\d{2}-\d{2}$/.test(texto)) return texto;

  const br = texto.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);

  if (br) {
    const dia = br[1].padStart(2, "0");
    const mes = br[2].padStart(2, "0");
    const ano = br[3];
    return `${ano}-${mes}-${dia}`;
  }

  throw new Error("Data do evento inválida. Use uma data válida no orçamento.");
}

function resolverPastaMesExistente(ano, mesIndex) {
  const mesNome = MESES_NOMES[mesIndex];
  const mesNumero = String(mesIndex + 1).padStart(2, "0");

  const pastaAnoLocal = path.join(__dirname, "..", "uploads", "servidor", ano);
  fs.mkdirSync(pastaAnoLocal, { recursive: true });

  const existentes = fs
    .readdirSync(pastaAnoLocal, { withFileTypes: true })
    .filter((item) => item.isDirectory())
    .map((item) => item.name);

  const alvoLimpo = limparAcentos(mesNome).toLowerCase();

  // Prioriza pasta sem número: "Dezembro", "Outubro", "Abril"
  const pastaSemNumero = existentes.find((nome) => {
    return limparAcentos(nome).toLowerCase() === alvoLimpo;
  });

  if (pastaSemNumero) return pastaSemNumero;

  // Se só existir com número, reaproveita, mas isso será evitado daqui para frente.
  const pastaComNumero = existentes.find((nome) => {
    const limpo = limparAcentos(nome).toLowerCase();
    return limpo === `${mesNumero} ${alvoLimpo}` || limpo.endsWith(` ${alvoLimpo}`);
  });

  if (pastaComNumero) return pastaComNumero;

  // Padrão oficial daqui para frente.
  const nova = mesNome;
  fs.mkdirSync(path.join(pastaAnoLocal, nova), { recursive: true });

  return nova;
}

function montarPastaEvento({ nomeEvento, empresa, dataEvento }) {
  const dataISO = normalizarData(dataEvento);
  const data = new Date(`${dataISO}T12:00:00`);

  if (Number.isNaN(data.getTime())) {
    throw new Error("Data do evento inválida.");
  }

  const ano = String(data.getFullYear());
  const mesIndex = data.getMonth();
  const mesPasta = resolverPastaMesExistente(ano, mesIndex);
  const dia = String(data.getDate()).padStart(2, "0");
  const mesNumero = String(mesIndex + 1).padStart(2, "0");

  const nomeBase = nomeSeguro(nomeEvento || empresa || "EVENTO");
  const pastaNome = `${nomeBase} ${dia}.${mesNumero}`;
  const nomeArquivo = `ORCAMENTO - ${pastaNome}.pdf`;

  return {
    ano,
    mesPasta,
    dia,
    mesNumero,
    pastaNome,
    nomeArquivo,
    caminhoLocalRelativo: path.join(ano, mesPasta, pastaNome),
    caminhoStorage: `${ano}/${mesPasta}/${pastaNome}/${nomeArquivo}`
  };
}

async function registrarLog(req, acao, entidade, entidadeId, detalhes = {}) {
  try {
    if (!isSupabaseConfigured()) return;

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

function registrarOrcamentoPdfServidor(app) {
  app.post("/api/orcamentos/salvar-pdf-servidor", async (req, res) => {
    try {
      const usuario = usuarioAtual(req);

      const empresa = req.body.empresa || "";
      const nomeEvento = req.body.nomeEvento || req.body.nome_evento || "";
      const dataEvento = req.body.dataEvento || req.body.data_evento || "";
      const pdfBase64 = req.body.pdfBase64 || "";

      if (!nomeEvento && !empresa) {
        return res.status(400).json({
          ok: false,
          message: "O sistema não encontrou o nome do evento/empresa no orçamento."
        });
      }

      if (!dataEvento) {
        return res.status(400).json({
          ok: false,
          message: "O sistema não encontrou a data do evento no orçamento."
        });
      }

      if (!pdfBase64) {
        return res.status(400).json({
          ok: false,
          message: "PDF não recebido pelo servidor."
        });
      }

      const pasta = montarPastaEvento({ nomeEvento, empresa, dataEvento });

      const base64Limpo = String(pdfBase64).replace(/^data:application\/pdf;base64,/, "");
      const buffer = Buffer.from(base64Limpo, "base64");

      const dirLocal = path.join(__dirname, "..", "uploads", "servidor", pasta.caminhoLocalRelativo);
      fs.mkdirSync(dirLocal, { recursive: true });

      const arquivoLocal = path.join(dirLocal, pasta.nomeArquivo);
      fs.writeFileSync(arquivoLocal, buffer);

      let storageSalvo = false;

      if (isSupabaseConfigured()) {
        const upload = await supabaseAdmin.storage
          .from(SUPABASE_BUCKET)
          .upload(pasta.caminhoStorage, buffer, {
            contentType: "application/pdf",
            upsert: true
          });

        if (upload.error) {
          console.log("⚠️ Não salvou no Supabase Storage:", upload.error.message);
        } else {
          storageSalvo = true;
        }

        try {
          await supabaseAdmin.from("cejas_arquivos").insert({
            nome: pasta.nomeArquivo,
            caminho: pasta.caminhoStorage,
            tipo: "application/pdf",
            origem: "orcamento",
            criado_por_email: usuario.email,
            criado_por_nome: usuario.nome
          });
        } catch (errorArquivo) {
          console.log("⚠️ Registro em cejas_arquivos ignorado:", errorArquivo.message);
        }
      }

      await registrarLog(req, "gerou_pdf_orcamento_e_salvou_servidor", "orcamento", null, {
        empresa,
        nomeEvento,
        dataEvento,
        pasta: pasta.caminhoLocalRelativo,
        arquivo: pasta.nomeArquivo,
        storagePath: pasta.caminhoStorage,
        storageSalvo
      });

      return res.json({
        ok: true,
        message: "PDF do orçamento salvo no servidor.",
        elaboradoPor: usuario.nome,
        pasta: pasta.caminhoLocalRelativo,
        arquivo: pasta.nomeArquivo,
        storagePath: pasta.caminhoStorage,
        storageSalvo
      });
    } catch (error) {
      console.error("❌ Erro ao salvar PDF do orçamento:", error.message);

      return res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });

  console.log("✅ Orçamentos: salvamento somente em PDF carregado.");
}

module.exports = {
  registrarOrcamentoPdfServidor
};
