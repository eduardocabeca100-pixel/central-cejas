(function () {
  function criarEstilos() {
    const style = document.createElement("style");
    style.innerHTML = `
      .agenda-manual-btn {
        position: fixed;
        right: 24px;
        bottom: 24px;
        z-index: 9999;
        border: 0;
        border-radius: 999px;
        padding: 14px 20px;
        color: white;
        font-weight: 800;
        cursor: pointer;
        background: linear-gradient(135deg, #8b5cf6, #ec4899);
        box-shadow: 0 20px 50px rgba(0,0,0,.35);
      }

      .agenda-manual-modal {
        position: fixed;
        inset: 0;
        z-index: 10000;
        display: none;
        align-items: center;
        justify-content: center;
        padding: 24px;
        background: rgba(0,0,0,.72);
        backdrop-filter: blur(10px);
      }

      .agenda-manual-modal.ativo {
        display: flex;
      }

      .agenda-manual-card {
        width: min(620px, 100%);
        border: 1px solid rgba(255,255,255,.12);
        border-radius: 24px;
        background: #111827;
        color: white;
        box-shadow: 0 30px 90px rgba(0,0,0,.55);
        padding: 24px;
      }

      .agenda-manual-card h2 {
        margin: 0 0 18px;
      }

      .agenda-manual-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 12px;
      }

      .agenda-manual-field {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .agenda-manual-field.full {
        grid-column: 1 / -1;
      }

      .agenda-manual-field label {
        font-size: 12px;
        opacity: .75;
        font-weight: 700;
        text-transform: uppercase;
      }

      .agenda-manual-field input,
      .agenda-manual-field select,
      .agenda-manual-field textarea {
        width: 100%;
        border: 1px solid rgba(255,255,255,.12);
        border-radius: 14px;
        padding: 12px;
        background: rgba(255,255,255,.06);
        color: white;
        outline: none;
      }

      .agenda-manual-field textarea {
        min-height: 90px;
        resize: vertical;
      }

      .agenda-manual-actions {
        display: flex;
        gap: 10px;
        justify-content: flex-end;
        margin-top: 18px;
      }

      .agenda-manual-actions button {
        border: 0;
        border-radius: 14px;
        padding: 12px 16px;
        font-weight: 800;
        cursor: pointer;
      }

      .agenda-manual-cancelar {
        background: rgba(255,255,255,.1);
        color: white;
      }

      .agenda-manual-salvar {
        background: linear-gradient(135deg, #8b5cf6, #ec4899);
        color: white;
      }

      .agenda-manual-lista {
        position: fixed;
        right: 24px;
        bottom: 86px;
        z-index: 9998;
        width: min(360px, calc(100vw - 48px));
        max-height: 380px;
        overflow: auto;
        border: 1px solid rgba(255,255,255,.12);
        border-radius: 20px;
        background: rgba(17, 24, 39, .96);
        color: white;
        padding: 14px;
        box-shadow: 0 20px 60px rgba(0,0,0,.35);
      }

      .agenda-manual-lista h3 {
        margin: 0 0 12px;
        font-size: 15px;
      }

      .agenda-manual-item {
        border-radius: 14px;
        background: rgba(255,255,255,.06);
        padding: 10px;
        margin-bottom: 8px;
        border-left: 4px solid #8b5cf6;
      }

      .agenda-manual-item.confirmado { border-left-color: #22c55e; }
      .agenda-manual-item.em-espera { border-left-color: #a855f7; }
      .agenda-manual-item.cancelado { border-left-color: #ef4444; }

      .agenda-manual-item strong {
        display: block;
        font-size: 14px;
      }

      .agenda-manual-item span {
        display: block;
        font-size: 12px;
        opacity: .75;
        margin-top: 3px;
      }

      @media (max-width: 640px) {
        .agenda-manual-grid {
          grid-template-columns: 1fr;
        }
      }
    `;
    document.head.appendChild(style);
  }

  function normalizarStatus(status) {
    return String(status || "")
      .toLowerCase()
      .replace(/\s+/g, "-");
  }

  async function carregarEventos() {
    const lista = document.querySelector(".agenda-manual-lista-itens");
    if (!lista) return;

    try {
      const resposta = await fetch("/api/agenda/manual");
      const dados = await resposta.json();

      if (!dados.ok) {
        lista.innerHTML = `<p style="opacity:.7;font-size:13px;">${dados.message || "Não foi possível carregar."}</p>`;
        return;
      }

      const eventos = dados.eventos || [];

      if (!eventos.length) {
        lista.innerHTML = `<p style="opacity:.7;font-size:13px;">Nenhum item manual na agenda.</p>`;
        return;
      }

      lista.innerHTML = eventos.slice(0, 12).map((evento) => `
        <div class="agenda-manual-item ${normalizarStatus(evento.status)}">
          <strong>${evento.titulo || "Sem título"}</strong>
          <span>${evento.data || ""} ${evento.hora_inicial ? "• " + evento.hora_inicial.slice(0,5) : ""}</span>
          <span>${evento.status || "confirmado"} • ${evento.responsavel_nome || "Responsável"}</span>
        </div>
      `).join("");
    } catch (error) {
      lista.innerHTML = `<p style="opacity:.7;font-size:13px;">Erro ao carregar agenda manual.</p>`;
    }
  }

  function criarModal() {
    const wrapper = document.createElement("div");
    wrapper.innerHTML = `
      <button class="agenda-manual-btn" type="button">+ Agenda</button>

      <aside class="agenda-manual-lista">
        <h3>Itens manuais</h3>
        <div class="agenda-manual-lista-itens"></div>
      </aside>

      <div class="agenda-manual-modal">
        <div class="agenda-manual-card">
          <h2>Adicionar item na agenda</h2>

          <form id="agendaManualForm" class="agenda-manual-grid">
            <div class="agenda-manual-field full">
              <label>Título</label>
              <input name="titulo" placeholder="Ex: Reunião com cliente" required>
            </div>

            <div class="agenda-manual-field">
              <label>Data</label>
              <input name="data" type="date" required>
            </div>

            <div class="agenda-manual-field">
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

            <div class="agenda-manual-field">
              <label>Hora inicial</label>
              <input name="horaInicial" type="time">
            </div>

            <div class="agenda-manual-field">
              <label>Hora final</label>
              <input name="horaFinal" type="time">
            </div>

            <div class="agenda-manual-field">
              <label>Status</label>
              <select name="status">
                <option value="confirmado">Confirmado</option>
                <option value="em espera">Em espera</option>
                <option value="cancelado">Cancelado</option>
              </select>
            </div>

            <div class="agenda-manual-field">
              <label>Visibilidade</label>
              <select name="visibilidade">
                <option value="privado">Privado</option>
                <option value="equipe">Equipe</option>
                <option value="todos">Todos</option>
              </select>
            </div>

            <div class="agenda-manual-field full">
              <label>Descrição</label>
              <textarea name="descricao" placeholder="Observações..."></textarea>
            </div>

            <div class="agenda-manual-actions full">
              <button class="agenda-manual-cancelar" type="button">Cancelar</button>
              <button class="agenda-manual-salvar" type="submit">Salvar</button>
            </div>
          </form>
        </div>
      </div>
    `;

    document.body.appendChild(wrapper);

    const modal = document.querySelector(".agenda-manual-modal");
    const abrir = document.querySelector(".agenda-manual-btn");
    const cancelar = document.querySelector(".agenda-manual-cancelar");
    const form = document.querySelector("#agendaManualForm");

    abrir.addEventListener("click", () => modal.classList.add("ativo"));
    cancelar.addEventListener("click", () => modal.classList.remove("ativo"));

    form.addEventListener("submit", async (event) => {
      event.preventDefault();

      const dados = Object.fromEntries(new FormData(form).entries());

      const resposta = await fetch("/api/agenda/manual", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(dados)
      });

      const resultado = await resposta.json();

      if (!resultado.ok) {
        alert(resultado.message || "Erro ao salvar item.");
        return;
      }

      form.reset();
      modal.classList.remove("ativo");
      await carregarEventos();
      alert("Item adicionado na agenda.");
    });

    carregarEventos();
  }

  document.addEventListener("DOMContentLoaded", () => {
    criarEstilos();
    criarModal();
  });
})();
