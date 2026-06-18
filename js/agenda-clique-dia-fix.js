(function () {
  if (window.__CEJAS_AGENDA_CLIQUE_FINAL__) return;
  window.__CEJAS_AGENDA_CLIQUE_FINAL__ = true;

  const meses = {
    janeiro: 0, fevereiro: 1, março: 2, marco: 2, abril: 3, maio: 4, junho: 5,
    julho: 6, agosto: 7, setembro: 8, outubro: 9, novembro: 10, dezembro: 11
  };

  let painelLateralFixo = null;
  let dataAtual = null;
  let eventosAtuais = [];

  function pad(n) {
    return String(n).padStart(2, "0");
  }

  function dataBR(iso) {
    const [ano, mes, dia] = String(iso || "").split("-");
    return dia && mes && ano ? `${dia}/${mes}/${ano}` : iso;
  }

  function dinheiro(valor) {
    return Number(valor || 0).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });
  }

  function statusClasse(status) {
    const s = String(status || "").toLowerCase();
    if (s.includes("cancel")) return "cancelado";
    if (s.includes("espera")) return "espera";
    return "confirmado";
  }

  function statusTexto(status) {
    const s = statusClasse(status);
    if (s === "cancelado") return "CANCELADO";
    if (s === "espera") return "EM ESPERA";
    return "CONFIRMADO";
  }

  function hora(ev) {
    const ini = ev.horaInicial || ev.hora_inicial || ev.inicio || ev.hora || "";
    const fim = ev.horaFinal || ev.hora_final || ev.fim || "";

    if (ini && fim) return `${String(ini).slice(0, 5)} até ${String(fim).slice(0, 5)}`;
    if (ini) return String(ini).slice(0, 5);

    return "Horário não informado";
  }

  function textoLimpo(el) {
    return String(el?.textContent || "").replace(/\s+/g, " ").trim();
  }

  function textoDireto(el) {
    return Array.from(el.childNodes || [])
      .filter((n) => n.nodeType === Node.TEXT_NODE)
      .map((n) => n.textContent)
      .join(" ")
      .trim();
  }

  function numeroDoDia(el) {
    const txt = textoDireto(el) || textoLimpo(el);
    const m = txt.match(/^(\d{1,2})\b/);
    if (!m) return null;

    const n = Number(m[1]);
    if (n < 1 || n > 31) return null;

    return n;
  }

  function elementoVisivel(el) {
    if (!el) return false;

    const r = el.getBoundingClientRect();
    const estilo = window.getComputedStyle ? window.getComputedStyle(el) : null;

    return r.width > 0 &&
      r.height > 0 &&
      estilo?.display !== "none" &&
      estilo?.visibility !== "hidden" &&
      !el.closest(".agenda-plus-overlay, .agenda-plus-card");
  }

  function pegarMesAnoAtual() {
    const selects = Array.from(document.querySelectorAll("select"));
    for (const s of selects) {
      const txt = textoLimpo(s.options?.[s.selectedIndex]) || textoLimpo(s);
      const m = txt.match(/(janeiro|fevereiro|março|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\s*(de)?\s*(20\d{2})/i);
      if (m) return { mes: meses[m[1].toLowerCase()], ano: Number(m[3]) };
    }

    const titulos = Array.from(document.querySelectorAll("h1,h2,h3,strong,div"));
    for (const el of titulos) {
      const txt = textoLimpo(el);
      const m = txt.match(/(janeiro|fevereiro|março|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\s*(de)?\s*(20\d{2})/i);
      if (m) return { mes: meses[m[1].toLowerCase()], ano: Number(m[3]) };
    }

    const hoje = new Date();
    return { mes: hoje.getMonth(), ano: hoje.getFullYear() };
  }

  function pareceCelulaCalendario(el) {
    if (!el || el.closest("aside")) return false;

    const dia = numeroDoDia(el);
    if (!dia) return false;

    const txt = textoLimpo(el).toLowerCase();
    if (txt.includes("agenda do dia")) return false;
    if (txt.includes("receita")) return false;
    if (txt.includes("pendentes")) return false;
    if (txt.includes("responsável")) return false;
    if (txt.includes("empresa:")) return false;

    const r = el.getBoundingClientRect();
    if (r.width < 60 || r.height < 55) return false;
    if (r.width > 260 || r.height > 260) return false;

    return true;
  }

  function acharCelulaClicada(target) {
    let atual = target;

    for (let i = 0; i < 8; i++) {
      if (!atual || atual === document.body) break;
      if (pareceCelulaCalendario(atual)) return atual;
      atual = atual.parentElement;
    }

    return null;
  }

  function todasCelulasCalendario() {
    return Array.from(document.querySelectorAll("main div, main button, main article"))
      .filter(pareceCelulaCalendario)
      .sort((a, b) => {
        const ra = a.getBoundingClientRect();
        const rb = b.getBoundingClientRect();
        return (ra.top - rb.top) || (ra.left - rb.left);
      });
  }

  function inferirData(cell) {
    const dia = numeroDoDia(cell);
    if (!dia) return null;

    const { mes, ano } = pegarMesAnoAtual();
    const cells = todasCelulasCalendario();
    const index = cells.indexOf(cell);

    let mesFinal = mes;
    let anoFinal = ano;

    if (index >= 0) {
      if (index < 7 && dia > 20) mesFinal -= 1;
      if (index > 27 && dia < 10) mesFinal += 1;
    }

    if (mesFinal < 0) {
      mesFinal = 11;
      anoFinal -= 1;
    }

    if (mesFinal > 11) {
      mesFinal = 0;
      anoFinal += 1;
    }

    return `${anoFinal}-${pad(mesFinal + 1)}-${pad(dia)}`;
  }

  function extrairDataCelula(cell) {
    if (!cell) return null;

    const dataAttr =
      cell.dataset?.date ||
      cell.dataset?.data ||
      cell.dataset?.iso ||
      cell.getAttribute("data-date") ||
      cell.getAttribute("data-data") ||
      cell.getAttribute("data-iso");

    if (/^\d{4}-\d{2}-\d{2}$/.test(String(dataAttr || ""))) {
      return String(dataAttr);
    }

    const onclick = cell.getAttribute("onclick") || "";
    const match = onclick.match(/selectDay\(['"](\d{4}-\d{2}-\d{2})['"]\)/);

    if (match) return match[1];

    return inferirData(cell);
  }

  function contemCalendario(el) {
    const qtdDias = Array.from(el.querySelectorAll("div,button,article"))
      .filter(pareceCelulaCalendario)
      .length;

    return qtdDias >= 10;
  }

  function acharPainelLateral() {
    if (painelLateralFixo && document.body.contains(painelLateralFixo) && elementoVisivel(painelLateralFixo)) {
      return painelLateralFixo;
    }

    const painelVisivel = Array.from(document.querySelectorAll(
      ".day-panel, [data-cejas-agenda-lateral='true']"
    )).find((el) => elementoVisivel(el));

    if (painelVisivel) {
      painelLateralFixo = painelVisivel;
      painelLateralFixo.setAttribute("data-cejas-agenda-lateral", "true");
      return painelLateralFixo;
    }

    const titulo = Array.from(document.querySelectorAll("h1,h2,h3,strong,div"))
      .find((el) => textoLimpo(el).toLowerCase() === "agenda do dia" && elementoVisivel(el));

    if (!titulo) return null;

    let escolhido = null;
    let atual = titulo;

    for (let i = 0; i < 10; i++) {
      if (!atual || atual === document.body || atual.tagName === "MAIN") break;

      const r = atual.getBoundingClientRect();
      const txt = textoLimpo(atual).toLowerCase();

      const valido =
        txt.includes("agenda do dia") &&
        r.width >= 260 &&
        r.width <= 760 &&
        r.height >= 220 &&
        !contemCalendario(atual);

      if (valido) {
        escolhido = atual;
      }

      atual = atual.parentElement;
    }

    painelLateralFixo = escolhido || titulo.parentElement;
    painelLateralFixo.setAttribute("data-cejas-agenda-lateral", "true");

    return painelLateralFixo;
  }

  function renderEvento(ev) {
    const status = statusClasse(ev.status);
    const statusVisual = status === "espera" ? "em-espera" : status;
    const titulo = ev.titulo || ev.evento || ev.nome_evento || ev.empresa || "Evento sem nome";
    const sala = ev.sala || ev.nome_sala || "Não informada";
    const empresa = ev.empresa || ev.cliente || "Não informada";
    const participantes = ev.participantes || ev.qtd_pessoas || ev.quantidade || "-";
    const origem = ev.origem === "manual" ? "Manual" : "Supera";
    const valor = ev.valor || ev.valorFinal || ev.valor_final || ev.receita || 0;
    const responsavel = ev.responsavelNome || ev.criadoPorNome || ev.responsavelEmail || ev.criadoPorEmail || origem;

    return `
      <article class="cejas-dia-card-plus ${ev.origem === "manual" ? "manual" : "supera"} ${statusVisual}" data-origem="${ev.origem}" data-id="${ev.id}">
        <span class="cejas-dia-tag-origem ${ev.origem === "manual" ? "manual" : "supera"}">
          ${origem}
        </span>

        <div class="cejas-dia-card-topo">
          <h3>${titulo}</h3>
          <span class="cejas-dia-pill-status ${statusVisual}">${statusTexto(ev.status)}</span>
        </div>

        <p>
          <strong>Horário:</strong> ${hora(ev)}<br>
          <strong>Sala:</strong> ${sala}<br>
          <strong>Empresa:</strong> ${empresa}<br>
          <strong>Participantes:</strong> ${participantes}<br>
          <strong>Responsável:</strong> ${responsavel}
          ${Number(valor || 0) > 0 ? `<br><br><strong>${dinheiro(valor)}</strong>` : ""}
        </p>

        <div class="cejas-status-bolinhas">
          <button title="Confirmado" type="button" class="cejas-bolinha-confirmado ${status === "confirmado" ? "ativo" : ""}" data-status="confirmado"></button>
          <button title="Em espera" type="button" class="cejas-bolinha-espera ${status === "espera" ? "ativo" : ""}" data-status="em espera"></button>
          <button title="Cancelado" type="button" class="cejas-bolinha-cancelado ${status === "cancelado" ? "ativo" : ""}" data-status="cancelado"></button>
        </div>
      </article>
    `;
  }

  function renderLateral(dataISO, eventos) {
    const painel = acharPainelLateral();
    if (!painel) return;

    dataAtual = dataISO;
    eventosAtuais = eventos;

    const receita = eventos.reduce((acc, ev) => {
      return acc + Number(ev.valor || ev.valorFinal || ev.valor_final || ev.receita || 0);
    }, 0);

    const pendentes = eventos.filter((ev) => statusClasse(ev.status) === "espera").length;

    painel.innerHTML = `
      <h2 class="cejas-dia-titulo">Agenda do dia</h2>
      <div class="cejas-dia-data">${dataBR(dataISO)}</div>

      <div class="cejas-dia-resumo">
        <div><span>EVENTOS</span><strong>${eventos.length}</strong></div>
        <div><span>RECEITA</span><strong>${dinheiro(receita)}</strong></div>
        <div><span>PENDENTES</span><strong>${pendentes}</strong></div>
      </div>

      <div class="cejas-dia-lista">
        ${
          eventos.length
            ? eventos.map(renderEvento).join("")
            : `<div class="cejas-dia-vazio">Nenhum evento nesta data.</div>`
        }
      </div>
    `;
  }

  async function carregarDia(dataISO) {
    const painel = acharPainelLateral();

    if (painel) {
      painel.innerHTML = `
        <h2 class="cejas-dia-titulo">Agenda do dia</h2>
        <div class="cejas-dia-data">${dataBR(dataISO)}</div>
        <div class="cejas-dia-vazio">Carregando eventos...</div>
      `;
    }

    try {
      const resposta = await fetch(`/api/agenda-dia?data=${encodeURIComponent(dataISO)}&ts=${Date.now()}`, {
        cache: "no-store"
      });

      const dados = await resposta.json();
      const eventos = dados.eventos || dados.agenda || [];

      renderLateral(dataISO, eventos);
    } catch (error) {
      renderLateral(dataISO, []);
    }
  }

  async function alterarStatus(card, status) {
    const origem = card?.dataset?.origem;
    const id = card?.dataset?.id;

    if (!origem || !id) return;

    const resposta = await fetch(`/api/agenda-dia/status/${origem}/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status })
    });

    const dados = await resposta.json();

    if (!dados.ok) {
      alert(dados.message || "Erro ao alterar status.");
      return;
    }

    eventosAtuais = eventosAtuais.map((evento) => {
      if (String(evento.id) === String(id) && evento.origem === origem) {
        return { ...evento, status };
      }

      return evento;
    });

    renderLateral(dataAtual, eventosAtuais);
  }

  function destacar(cell) {
    document.querySelectorAll(".cejas-dia-selecionado").forEach((x) => {
      x.classList.remove("cejas-dia-selecionado");
    });

    document.querySelectorAll(".day-cell.selected").forEach((x) => {
      x.classList.remove("selected");
    });

    cell.classList.add("cejas-dia-selecionado");
    cell.classList.add("selected");
  }

  function instalarClique() {
    document.addEventListener("click", (event) => {
      const cell = acharCelulaClicada(event.target);
      if (!cell) return;

      const dataISO = extrairDataCelula(cell);
      if (!dataISO) return;

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      destacar(cell);

      carregarDia(dataISO);

      setTimeout(() => carregarDia(dataISO), 120);
      setTimeout(() => carregarDia(dataISO), 450);
    }, true);
  }

  function instalarStatus() {
    document.addEventListener("click", async (event) => {
      const botao = event.target.closest(".cejas-status-bolinhas button[data-status]");
      if (!botao) return;

      const card = botao.closest(".cejas-dia-card-plus");
      if (!card) return;

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      await alterarStatus(card, botao.dataset.status);
    }, true);
  }

  function instalarCss() {
    if (document.getElementById("cejasAgendaLateralFinalCss")) return;

    const style = document.createElement("style");
    style.id = "cejasAgendaLateralFinalCss";

    style.innerHTML = `
      .cejas-dia-selecionado {
        outline: 2px solid #ec4fc6 !important;
        box-shadow: 0 0 0 4px rgba(236,79,198,.18) !important;
      }

      [data-cejas-agenda-lateral="true"] {
        align-self: start;
      }

      .cejas-dia-titulo {
        margin: 0 0 4px !important;
        font-size: 30px !important;
        color: #fff !important;
      }

      .cejas-dia-data {
        color: rgba(255,255,255,.66);
        margin-bottom: 14px;
        font-weight: 800;
      }

      .cejas-dia-resumo {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 8px;
        margin-bottom: 14px;
      }

      .cejas-dia-resumo div {
        border: 1px solid rgba(255,255,255,.10);
        background: rgba(255,255,255,.045);
        border-radius: 14px;
        padding: 10px;
      }

      .cejas-dia-resumo span {
        display: block;
        font-size: 11px;
        color: rgba(255,255,255,.55);
        font-weight: 900;
        letter-spacing: .08em;
      }

      .cejas-dia-resumo strong {
        display: block;
        margin-top: 4px;
        font-size: 18px;
        color: #fff;
      }

      .cejas-dia-lista {
        display: grid;
        gap: 10px;
      }

      .cejas-dia-card {
        border: 1px solid rgba(255,255,255,.10);
        border-left: 5px solid #22c55e;
        border-radius: 18px;
        padding: 14px;
        background: rgba(255,255,255,.055);
      }

      .cejas-dia-card.espera { border-left-color: #a855f7; }
      .cejas-dia-card.cancelado { border-left-color: #ef4444; }

      .cejas-dia-card-top {
        display: flex;
        justify-content: space-between;
        gap: 8px;
        align-items: center;
        margin-bottom: 8px;
      }

      .cejas-origem,
      .cejas-status {
        border-radius: 999px;
        padding: 5px 8px;
        font-size: 10px;
        font-weight: 900;
        text-transform: uppercase;
      }

      .cejas-origem {
        background: rgba(34,197,94,.16);
        color: #bbf7d0;
      }

      .cejas-status {
        background: rgba(34,197,94,.16);
        color: #bbf7d0;
      }

      .cejas-status.espera {
        background: rgba(168,85,247,.18);
        color: #e9d5ff;
      }

      .cejas-status.cancelado {
        background: rgba(239,68,68,.18);
        color: #fecaca;
      }

      .cejas-dia-card h3 {
        margin: 0 0 10px;
        font-size: 16px;
        color: #fff;
        line-height: 1.15;
      }

      .cejas-dia-card p {
        margin: 3px 0;
        color: rgba(255,255,255,.78);
        font-size: 13px;
      }

      .cejas-dia-card h4 {
        margin: 12px 0 0;
        font-size: 18px;
        color: #fff;
      }

      .cejas-dia-vazio {
        border: 1px dashed rgba(255,255,255,.16);
        color: rgba(255,255,255,.65);
        border-radius: 16px;
        padding: 18px;
        text-align: center;
      }
    `;

    document.head.appendChild(style);
  }

  document.addEventListener("DOMContentLoaded", () => {
    instalarCss();
    acharPainelLateral();
    instalarClique();
    instalarStatus();
  });
})();
