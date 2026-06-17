console.log("✅ Agenda Plus carregou corretamente.");

document.addEventListener("DOMContentLoaded", () => {
  if (document.querySelector(".agenda-plus-fab")) return;

  const style = document.createElement("style");
  style.innerHTML = `
    .agenda-plus-fab {
      position: fixed;
      right: 24px;
      bottom: 24px;
      z-index: 999999;
      border: 0;
      border-radius: 999px;
      padding: 16px 24px;
      background: linear-gradient(135deg, #8b5cf6, #ec4899);
      color: white;
      font-weight: 900;
      cursor: pointer;
      box-shadow: 0 22px 70px rgba(0,0,0,.55);
    }

    .agenda-plus-overlay {
      position: fixed;
      inset: 0;
      z-index: 1000000;
      display: none;
      align-items: center;
      justify-content: center;
      background: rgba(0,0,0,.75);
      backdrop-filter: blur(12px);
      padding: 20px;
    }

    .agenda-plus-overlay.ativo {
      display: flex;
    }

    .agenda-plus-card {
      width: min(920px, 100%);
      max-height: 90vh;
      overflow: auto;
      border-radius: 26px;
      border: 1px solid rgba(255,255,255,.12);
      background: #111827;
      color: white;
      padding: 26px;
      box-shadow: 0 30px 100px rgba(0,0,0,.6);
      font-family: Arial, sans-serif;
    }

    .agenda-plus-top {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: flex-start;
      margin-bottom: 18px;
    }

    .agenda-plus-top h2 {
      margin: 0 0 6px;
      font-size: 30px;
    }

    .agenda-plus-top p {
      margin: 0;
      color: rgba(255,255,255,.7);
    }

    .agenda-plus-close {
      border: 0;
      border-radius: 12px;
      width: 42px;
      height: 42px;
      background: rgba(255,255,255,.1);
      color: white;
      font-size: 22px;
      cursor: pointer;
    }

    .agenda-plus-grid {
      display: grid;
      grid-template-columns: 1.1fr .9fr;
      gap: 18px;
    }

    .agenda-plus-box {
      border: 1px solid rgba(255,255,255,.1);
      border-radius: 20px;
      background: rgba(255,255,255,.04);
      padding: 16px;
    }

    .agenda-plus-box h3 {
      margin: 0 0 12px;
    }

    .agenda-plus-field {
      display: grid;
      gap: 6px;
      margin-bottom: 10px;
    }

    .agenda-plus-field label {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: .08em;
      color: rgba(255,255,255,.65);
      font-weight: 900;
    }

    .agenda-plus-field input,
    .agenda-plus-field select,
    .agenda-plus-field textarea {
      border: 1px solid rgba(255,255,255,.14);
      border-radius: 14px;
      padding: 12px;
      background: rgba(255,255,255,.07);
      color: white;
      outline: none;
    }

    .agenda-plus-field textarea {
      min-height: 80px;
      resize: vertical;
    }

    .agenda-plus-two {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }

    .agenda-plus-save,
    .agenda-plus-load {
      border: 0;
      border-radius: 14px;
      padding: 12px 16px;
      background: linear-gradient(135deg, #8b5cf6, #ec4899);
      color: white;
      font-weight: 900;
      cursor: pointer;
      width: 100%;
    }

    .agenda-plus-event {
      border: 1px solid rgba(255,255,255,.1);
      border-left: 5px solid #22c55e;
      border-radius: 16px;
      padding: 12px;
      margin-bottom: 10px;
      background: rgba(255,255,255,.055);
    }

    .agenda-plus-event.em-espera {
      border-left-color: #a855f7;
    }

    .agenda-plus-event.cancelado {
      border-left-color: #ef4444;
    }

    .agenda-plus-event strong {
      display: block;
      margin-bottom: 4px;
    }

    .agenda-plus-event small {
      color: rgba(255,255,255,.7);
      line-height: 1.5;
    }

    .agenda-plus-status {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 10px;
    }

    .agenda-plus-status button {
      border: 1px solid rgba(255,255,255,.12);
      border-radius: 999px;
      padding: 8px 10px;
      color: white;
      font-weight: 800;
      cursor: pointer;
      background: rgba(255,255,255,.08);
      font-size: 12px;
    }

    .agenda-plus-status button[data-status="confirmado"] {
      background: rgba(34,197,94,.22);
    }

    .agenda-plus-status button[data-status="em espera"] {
      background: rgba(168,85,247,.22);
    }

    .agenda-plus-status button[data-status="cancelado"] {
      background: rgba(239,68,68,.22);
    }

    @media (max-width: 850px) {
      .agenda-plus-grid {
        grid-template-columns: 1fr;
      }
      .agenda-plus-two {
        grid-template-columns: 1fr;
      }
    }
  `;

  document.head.appendChild(style);

  const hoje = new Date().toISOString().slice(0, 10);

  const btn = document.createElement("button");
  btn.className = "agenda-plus-fab";
  btn.type = "button";
  btn.textContent = "+ Agenda";

  const modal = document.createElement("div");
  modal.className = "agenda-plus-overlay";
  modal.innerHTML = `
    <div class="agenda-plus-card">
      <div class="agenda-plus-top">
        <div>
          <h2>Agenda do dia</h2>
          <p>Adicione itens manuais e altere status dos eventos.</p>
        </div>
        <button class="agenda-plus-close" type="button">×</button>
      </div>

      <div class="agenda-plus-grid">
        <section class="agenda-plus-box">
          <h3>Eventos</h3>

          <div class="agenda-plus-field">
            <label>Data</label>
            <input id="agendaPlusData" type="date" value="${hoje}">
          </div>

          <button class="agenda-plus-load" type="button">Carregar dia</button>

          <div id="agendaPlusLista" style="margin-top:14px;">
            Clique em carregar dia.
          </div>
        </section>

        <section class="agenda-plus-box">
          <h3>Adicionar item manual</h3>

          <form id="agendaPlusForm">
            <div class="agenda-plus-field">
              <label>Título</label>
              <input name="titulo" required placeholder="Ex: Reunião com Renato">
            </div>

            <div class="agenda-plus-two">
              <div class="agenda-plus-field">
                <label>Hora inicial</label>
                <input name="horaInicial" type="time">
              </div>

              <div class="agenda-plus-field">
                <label>Hora final</label>
                <input name="horaFinal" type="time">
              </div>
            </div>

            <div class="agenda-plus-two">
              <div class="agenda-plus-field">
                <label>Tipo</label>
                <select name="tipo">
                  <option value="reuniao">Reunião</option>
                  <option value="comercial">Comercial</option>
                  <option value="visita">Visita</option>
                  <option value="pessoal">Pessoal</option>
                  <option value="medico">Médico</option>
                  <option value="tarefa">Tarefa</option>
                  <option value="outro">Outro</option>
                </select>
              </div>

              <div class="agenda-plus-field">
                <label>Status</label>
                <select name="status">
                  <option value="confirmado">Confirmado</option>
                  <option value="em espera">Em espera</option>
                  <option value="cancelado">Cancelado</option>
                </select>
              </div>
            </div>

            <div class="agenda-plus-field">
              <label>Visibilidade</label>
              <select name="visibilidade">
                <option value="privado">Privado</option>
                <option value="equipe">Equipe</option>
                <option value="todos">Todos</option>
              </select>
            </div>

            <div class="agenda-plus-field">
              <label>Descrição</label>
              <textarea name="descricao" placeholder="Observações..."></textarea>
            </div>

            <button class="agenda-plus-save" type="submit">Salvar na agenda</button>
          </form>
        </section>
      </div>
    </div>
  `;

  document.body.appendChild(btn);
  document.body.appendChild(modal);

  const fechar = modal.querySelector(".agenda-plus-close");
  const carregar = modal.querySelector(".agenda-plus-load");
  const inputData = modal.querySelector("#agendaPlusData");
  const lista = modal.querySelector("#agendaPlusLista");
  const form = modal.querySelector("#agendaPlusForm");

  function statusClasse(status) {
    const s = String(status || "confirmado").toLowerCase();
    if (s.includes("cancel")) return "cancelado";
    if (s.includes("espera")) return "em-espera";
    return "confirmado";
  }

  async function carregarEventos() {
    const data = inputData.value || hoje;

    lista.innerHTML = "Carregando...";

    try {
      const resp = await fetch(`/api/agenda-plus/unificada?data=${encodeURIComponent(data)}`);
      const json = await resp.json();

      if (!json.ok) {
        lista.innerHTML = json.message || "Erro ao carregar agenda.";
        return;
      }

      const eventos = json.eventos || [];

      if (!eventos.length) {
        lista.innerHTML = "Nenhum evento neste dia.";
        return;
      }

      lista.innerHTML = eventos.map((ev) => `
        <div class="agenda-plus-event ${statusClasse(ev.status)}" data-id="${ev.id}" data-origem="${ev.origem}">
          <strong>${ev.titulo || "Sem título"}</strong>
          <small>
            ${ev.origem === "supera" ? "Supera" : "Manual"} · ${ev.status || "confirmado"}
            ${ev.horaInicial ? `<br>Horário: ${String(ev.horaInicial).slice(0,5)}${ev.horaFinal ? " até " + String(ev.horaFinal).slice(0,5) : ""}` : ""}
            ${ev.sala ? `<br>Sala: ${ev.sala}` : ""}
            ${ev.empresa ? `<br>Empresa: ${ev.empresa}` : ""}
            ${ev.responsavelNome ? `<br>Responsável: ${ev.responsavelNome}` : ""}
          </small>

          <div class="agenda-plus-status">
            <button type="button" data-status="confirmado">Confirmado</button>
            <button type="button" data-status="em espera">Em espera</button>
            <button type="button" data-status="cancelado">Cancelado</button>
          </div>
        </div>
      `).join("");
    } catch (err) {
      lista.innerHTML = "Erro ao carregar agenda.";
    }
  }

  async function alterarStatus(card, status) {
    const origem = card.dataset.origem;
    const id = card.dataset.id;

    const resp = await fetch(`/api/agenda-plus/status/${origem}/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status })
    });

    const json = await resp.json();

    if (!json.ok) {
      alert(json.message || "Erro ao alterar status.");
      return;
    }

    await carregarEventos();
  }

  btn.addEventListener("click", () => {
    modal.classList.add("ativo");
    carregarEventos();
  });

  fechar.addEventListener("click", () => {
    modal.classList.remove("ativo");
  });

  carregar.addEventListener("click", carregarEventos);

  lista.addEventListener("click", async (event) => {
    const botao = event.target.closest("button[data-status]");
    if (!botao) return;

    const card = botao.closest(".agenda-plus-event");
    if (!card) return;

    await alterarStatus(card, botao.dataset.status);
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const dados = Object.fromEntries(new FormData(form).entries());
    dados.data = inputData.value || hoje;

    const resp = await fetch("/api/agenda-plus/manual", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(dados)
    });

    const json = await resp.json();

    if (!json.ok) {
      alert(json.message || "Erro ao salvar item.");
      return;
    }

    form.reset();
    await carregarEventos();
    alert("Item salvo na agenda.");
  });
});
