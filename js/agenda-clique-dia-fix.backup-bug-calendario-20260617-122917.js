(function () {
  if (window.__CEJAS_AGENDA_CLIQUE_DIA_FIX__) return;
  window.__CEJAS_AGENDA_CLIQUE_DIA_FIX__ = true;

  const meses = {
    janeiro: 0,
    fevereiro: 1,
    março: 2,
    marco: 2,
    abril: 3,
    maio: 4,
    junho: 5,
    julho: 6,
    agosto: 7,
    setembro: 8,
    outubro: 9,
    novembro: 10,
    dezembro: 11
  };

  function pad(n) {
    return String(n).padStart(2, "0");
  }

  function dinheiro(valor) {
    const n = Number(valor || 0);
    return n.toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });
  }

  function dataBR(iso) {
    if (!iso) return "";
    const [ano, mes, dia] = String(iso).split("-");
    return `${dia}/${mes}/${ano}`;
  }

  function hora(ev) {
    const ini = ev.horaInicial || ev.hora_inicial || ev.inicio || ev.hora || "";
    const fim = ev.horaFinal || ev.hora_final || ev.fim || "";

    if (ini && fim) return `${String(ini).slice(0, 5)} até ${String(fim).slice(0, 5)}`;
    if (ini) return String(ini).slice(0, 5);

    return "Horário não informado";
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

  function pegarMesAnoAtual() {
    const textos = Array.from(document.querySelectorAll("h1,h2,h3,strong,div,select option:checked"))
      .map((el) => String(el.textContent || el.value || "").trim())
      .filter(Boolean);

    for (const texto of textos) {
      const match = texto.match(/(janeiro|fevereiro|março|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\s*(de)?\s*(20\d{2})/i);

      if (match) {
        const mesNome = match[1].toLowerCase();
        return {
          mes: meses[mesNome],
          ano: Number(match[3])
        };
      }
    }

    const hoje = new Date();

    return {
      mes: hoje.getMonth(),
      ano: hoje.getFullYear()
    };
  }

  function textoDireto(el) {
    return Array.from(el.childNodes)
      .filter((n) => n.nodeType === Node.TEXT_NODE)
      .map((n) => n.textContent)
      .join(" ")
      .trim();
  }

  function numeroDoDia(el) {
    const direto = textoDireto(el);
    const txt = direto || String(el.textContent || "").trim();
    const match = txt.match(/^(\d{1,2})\b/);

    if (!match) return null;

    const n = Number(match[1]);

    if (n < 1 || n > 31) return null;

    return n;
  }

  function candidatosCalendario() {
    return Array.from(document.querySelectorAll("main div, main button, main article"))
      .filter((el) => {
        const n = numeroDoDia(el);
        if (!n) return false;

        if (el.closest("aside")) return false;

        const txt = String(el.textContent || "").toLowerCase();

        if (txt.includes("agenda do dia")) return false;
        if (txt.includes("receita")) return false;
        if (txt.includes("eventos")) return false && txt.length < 20;

        const rect = el.getBoundingClientRect();

        return rect.width > 50 && rect.height > 40;
      });
  }

  function ehCelulaCalendario(el) {
    const n = numeroDoDia(el);
    if (!n) return false;

    const parent = el.parentElement;
    const grand = parent?.parentElement;

    const irmaos = Array.from(parent?.children || []).filter((x) => numeroDoDia(x));
    const primos = Array.from(grand?.querySelectorAll(":scope > * > *") || []).filter((x) => numeroDoDia(x));

    return irmaos.length >= 5 || primos.length >= 14;
  }

  function inferirData(el) {
    const dia = numeroDoDia(el);

    if (!dia) return null;

    const { mes, ano } = pegarMesAnoAtual();
    const cells = candidatosCalendario().filter(ehCelulaCalendario);
    const index = cells.indexOf(el);

    let mesFinal = mes;
    let anoFinal = ano;

    if (index >= 0) {
      if (index < 7 && dia > 20) {
        mesFinal -= 1;
      }

      if (index > 27 && dia < 10) {
        mesFinal += 1;
      }
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

  function acharBoxAgendaDia() {
    const titulo = Array.from(document.querySelectorAll("h1,h2,h3,strong,div"))
      .find((el) => String(el.textContent || "").trim().toLowerCase() === "agenda do dia");

    if (!titulo) return null;

    let atual = titulo;

    for (let i = 0; i < 8; i++) {
      if (!atual) break;

      const rect = atual.getBoundingClientRect();
      const txt = String(atual.textContent || "").toLowerCase();

      if (
        rect.width >= 220 &&
        rect.height >= 250 &&
        txt.includes("agenda do dia")
      ) {
        return atual;
      }

      atual = atual.parentElement;
    }

    return titulo.parentElement;
  }

  function renderEvento(ev) {
    const status = statusClasse(ev.status);
    const titulo = ev.titulo || ev.evento || ev.nome_evento || ev.empresa || "Evento sem nome";
    const sala = ev.sala || ev.nome_sala || "Não informada";
    const empresa = ev.empresa || ev.cliente || "Não informada";
    const participantes = ev.participantes || ev.qtd_pessoas || ev.quantidade || "-";
    const origem = ev.origem === "manual" ? "Manual" : "Supera";
    const valor = ev.valor || ev.valorFinal || ev.valor_final || ev.receita || 0;

    return `
      <div class="cejas-agenda-dia-card ${status}">
        <div class="cejas-agenda-dia-card-top">
          <span class="cejas-origem">${origem}</span>
          <span class="cejas-status ${status}">${statusTexto(ev.status)}</span>
        </div>

        <h3>${titulo}</h3>

        <p><strong>Horário:</strong> ${hora(ev)}</p>
        <p><strong>Sala:</strong> ${sala}</p>
        <p><strong>Empresa:</strong> ${empresa}</p>
        <p><strong>Participantes:</strong> ${participantes}</p>
        <p><strong>Responsável:</strong> ${origem}</p>

        ${Number(valor || 0) > 0 ? `<h4>${dinheiro(valor)}</h4>` : ""}
      </div>
    `;
  }

  function renderAgendaDia(dataISO, eventos) {
    const box = acharBoxAgendaDia();

    if (!box) return;

    const total = eventos.length;
    const receita = eventos.reduce((acc, ev) => {
      return acc + Number(ev.valor || ev.valorFinal || ev.valor_final || ev.receita || 0);
    }, 0);

    const pendentes = eventos.filter((ev) => statusClasse(ev.status) === "espera").length;

    box.innerHTML = `
      <h2 class="cejas-agenda-titulo">Agenda do dia</h2>
      <div class="cejas-agenda-data">${dataBR(dataISO)}</div>

      <div class="cejas-agenda-resumo">
        <div>
          <span>EVENTOS</span>
          <strong>${total}</strong>
        </div>
        <div>
          <span>RECEITA</span>
          <strong>${dinheiro(receita)}</strong>
        </div>
        <div>
          <span>PENDENTES</span>
          <strong>${pendentes}</strong>
        </div>
      </div>

      <div class="cejas-agenda-lista">
        ${
          eventos.length
            ? eventos.map(renderEvento).join("")
            : `<div class="cejas-agenda-vazio">Nenhum evento nesta data.</div>`
        }
      </div>
    `;
  }

  async function carregarDia(dataISO) {
    const box = acharBoxAgendaDia();

    if (box) {
      box.innerHTML = `
        <h2 class="cejas-agenda-titulo">Agenda do dia</h2>
        <div class="cejas-agenda-data">${dataBR(dataISO)}</div>
        <div class="cejas-agenda-vazio">Carregando eventos...</div>
      `;
    }

    const resposta = await fetch(`/api/agenda-dia?data=${encodeURIComponent(dataISO)}&ts=${Date.now()}`, {
      cache: "no-store"
    });

    const dados = await resposta.json();

    const eventos = dados.eventos || dados.agenda || [];

    renderAgendaDia(dataISO, eventos);
  }

  function destacarCelula(el) {
    document.querySelectorAll(".cejas-dia-selecionado").forEach((x) => {
      x.classList.remove("cejas-dia-selecionado");
    });

    el.classList.add("cejas-dia-selecionado");
  }

  function instalarClique() {
    document.addEventListener("click", (event) => {
      const alvo = event.target.closest("div,button,article");

      if (!alvo) return;
      if (!ehCelulaCalendario(alvo)) return;

      const dataISO = inferirData(alvo);

      if (!dataISO) return;

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      destacarCelula(alvo);
      carregarDia(dataISO);
    }, true);
  }

  function instalarCss() {
    const style = document.createElement("style");

    style.innerHTML = `
      .cejas-dia-selecionado {
        outline: 2px solid #ec4fc6 !important;
        box-shadow: 0 0 0 4px rgba(236,79,198,.18) !important;
      }

      .cejas-agenda-titulo {
        margin: 0 0 4px !important;
        font-size: 30px !important;
        color: #fff !important;
      }

      .cejas-agenda-data {
        color: rgba(255,255,255,.66);
        margin-bottom: 14px;
        font-weight: 700;
      }

      .cejas-agenda-resumo {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 8px;
        margin-bottom: 14px;
      }

      .cejas-agenda-resumo div {
        border: 1px solid rgba(255,255,255,.10);
        background: rgba(255,255,255,.045);
        border-radius: 14px;
        padding: 10px;
      }

      .cejas-agenda-resumo span {
        display: block;
        font-size: 11px;
        color: rgba(255,255,255,.55);
        font-weight: 900;
        letter-spacing: .08em;
      }

      .cejas-agenda-resumo strong {
        display: block;
        margin-top: 4px;
        font-size: 18px;
        color: #fff;
      }

      .cejas-agenda-lista {
        display: grid;
        gap: 10px;
      }

      .cejas-agenda-dia-card {
        border: 1px solid rgba(255,255,255,.10);
        border-left: 5px solid #22c55e;
        border-radius: 18px;
        padding: 14px;
        background: rgba(255,255,255,.055);
      }

      .cejas-agenda-dia-card.espera {
        border-left-color: #a855f7;
      }

      .cejas-agenda-dia-card.cancelado {
        border-left-color: #ef4444;
      }

      .cejas-agenda-dia-card-top {
        display: flex;
        justify-content: space-between;
        gap: 8px;
        align-items: center;
        margin-bottom: 8px;
      }

      .cejas-origem {
        background: rgba(34,197,94,.16);
        color: #bbf7d0;
        border-radius: 999px;
        padding: 4px 8px;
        font-size: 10px;
        font-weight: 900;
        text-transform: uppercase;
      }

      .cejas-status {
        border-radius: 999px;
        padding: 5px 8px;
        font-size: 10px;
        font-weight: 900;
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

      .cejas-agenda-dia-card h3 {
        margin: 0 0 10px;
        font-size: 16px;
        color: #fff;
        line-height: 1.15;
      }

      .cejas-agenda-dia-card p {
        margin: 3px 0;
        color: rgba(255,255,255,.78);
        font-size: 13px;
      }

      .cejas-agenda-dia-card h4 {
        margin: 12px 0 0;
        font-size: 18px;
        color: #fff;
      }

      .cejas-agenda-vazio {
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
    instalarClique();
  });
})();
