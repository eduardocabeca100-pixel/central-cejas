const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(__dirname, "..", "data");
const RELATORIO_FILE = path.join(DATA_DIR, "relatorio-supera.json");
const AGENDA_MANUAL_FILE = path.join(DATA_DIR, "agenda-manual-local.json");

function readJson(filePath, fallback) {
  try {
    if (!fs.existsSync(filePath)) return fallback;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

function writeJson(filePath, data) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), "utf8");
}

function dataParaISO(value) {
  const raw = String(value || "").trim();

  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;

  const match = raw.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!match) return raw || null;

  const [, dia, mes, ano] = match;
  return `${ano}-${mes.padStart(2, "0")}-${dia.padStart(2, "0")}`;
}

function normalizarStatus(status) {
  const s = String(status || "confirmado").toLowerCase().trim();

  if (s.includes("cancel")) return "cancelado";
  if (s.includes("espera") || s.includes("pendente")) return "em espera";
  return "confirmado";
}

function numero(value) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n : 0;
}

function eventoSuperaLocal(evento, index) {
  return {
    id: String(evento.id || `local-supera-${index + 1}`),
    origem: "supera",
    titulo: evento.evento || evento.empresa || "Evento do Supera",
    data: dataParaISO(evento.data || evento.data_evento),
    horaInicial: evento.horaInicial || evento.hora_inicial || null,
    horaFinal: evento.horaFinal || evento.hora_final || null,
    status: normalizarStatus(evento.status),
    tipo: "evento",
    sala: evento.sala || null,
    empresa: evento.empresa || null,
    responsavelNome: "Supera",
    valor: numero(evento.valor),
    participantes: numero(evento.participantes)
  };
}

function eventoManualLocal(evento) {
  return {
    id: String(evento.id),
    origem: "manual",
    titulo: evento.titulo || "Item manual",
    data: dataParaISO(evento.data),
    horaInicial: evento.horaInicial || evento.hora_inicial || null,
    horaFinal: evento.horaFinal || evento.hora_final || null,
    status: normalizarStatus(evento.status),
    tipo: evento.tipo || "outro",
    responsavelNome: evento.responsavelNome || evento.responsavel_nome || null,
    responsavelEmail: evento.responsavelEmail || evento.responsavel_email || null,
    criadoPorNome: evento.criadoPorNome || evento.criado_por_nome || null,
    criadoPorEmail: evento.criadoPorEmail || evento.criado_por_email || null,
    visibilidade: evento.visibilidade || "privado",
    descricao: evento.descricao || ""
  };
}

function ordenarEventos(eventos) {
  return [...eventos].sort((a, b) => {
    const da = `${a.data || ""} ${a.horaInicial || ""}`;
    const db = `${b.data || ""} ${b.horaInicial || ""}`;
    return da.localeCompare(db);
  });
}

function listarEventosLocais(dataFiltro = null) {
  const report = readJson(RELATORIO_FILE, {});
  const manuais = readJson(AGENDA_MANUAL_FILE, []);

  const eventosSupera = (report.eventos || []).map(eventoSuperaLocal);
  const eventosManuais = (Array.isArray(manuais) ? manuais : []).map(eventoManualLocal);

  const eventos = [...eventosSupera, ...eventosManuais].filter((evento) => {
    if (!dataFiltro) return true;
    return evento.data === dataFiltro;
  });

  return ordenarEventos(eventos);
}

function criarEventoManualLocal(payload, usuario) {
  const manuais = readJson(AGENDA_MANUAL_FILE, []);

  const evento = {
    id: `manual-local-${Date.now()}`,
    titulo: payload.titulo,
    data: dataParaISO(payload.data),
    horaInicial: payload.horaInicial || null,
    horaFinal: payload.horaFinal || null,
    tipo: payload.tipo || "outro",
    status: normalizarStatus(payload.status),
    visibilidade: payload.visibilidade || "privado",
    descricao: payload.descricao || "",
    responsavelNome: usuario.nome,
    responsavelEmail: usuario.email,
    criadoPorNome: usuario.nome,
    criadoPorEmail: usuario.email,
    criadoEm: new Date().toISOString()
  };

  manuais.push(evento);
  writeJson(AGENDA_MANUAL_FILE, manuais);

  return eventoManualLocal(evento);
}

function atualizarStatusLocal(origem, id, status) {
  const statusNormalizado = normalizarStatus(status);

  if (origem === "manual") {
    const manuais = readJson(AGENDA_MANUAL_FILE, []);
    const index = manuais.findIndex((evento) => String(evento.id) === String(id));

    if (index < 0) return null;

    manuais[index] = {
      ...manuais[index],
      status: statusNormalizado,
      atualizadoEm: new Date().toISOString()
    };

    writeJson(AGENDA_MANUAL_FILE, manuais);
    return eventoManualLocal(manuais[index]);
  }

  if (origem === "supera") {
    const report = readJson(RELATORIO_FILE, null);
    const eventos = report && Array.isArray(report.eventos) ? report.eventos : [];
    const index = eventos.findIndex((evento) => String(evento.id) === String(id));

    if (index < 0) return null;

    eventos[index] = {
      ...eventos[index],
      status: statusNormalizado
    };

    writeJson(RELATORIO_FILE, {
      ...report,
      atualizadoEm: new Date().toISOString(),
      eventos
    });

    return eventoSuperaLocal(eventos[index], index);
  }

  return null;
}

module.exports = {
  listarEventosLocais,
  criarEventoManualLocal,
  atualizarStatusLocal
};
