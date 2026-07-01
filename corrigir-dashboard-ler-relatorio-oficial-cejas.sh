#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "dashboard.html" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/dashboard-oficial-$STAMP"
mkdir -p "$BACKUP_DIR" lib

cp server.js dashboard.html "$BACKUP_DIR/" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

cat > lib/dashboard-relatorio-oficial-cejas.js <<'EOF'
const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(process.cwd(), "data");
const RELATORIO_SUPERA_FILE = path.join(DATA_DIR, "relatorio-supera.json");
const RELATORIO_ATUAL_FILE = path.join(DATA_DIR, "relatorio-atual.json");

function numero(valor) {
  if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

  const s = String(valor || "")
    .replace(/R\$/gi, "")
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".")
    .replace(/[^\d.-]/g, "");

  const n = Number(s);
  return Number.isFinite(n) ? n : 0;
}

function pareceEvento(item) {
  if (!item || typeof item !== "object" || Array.isArray(item)) return false;

  return Boolean(
    item.evento ||
    item.nomeEvento ||
    item.titulo ||
    item.title ||
    item.data ||
    item.dataEvento ||
    item.sala ||
    item.local ||
    item.status ||
    item.valorTotal ||
    item.valor_total ||
    item.receitaConfirmada ||
    item.valorPago ||
    item.empresa ||
    item.solicitante
  );
}

function extrairEventos(obj, lista = [], visitados = new Set()) {
  if (!obj || typeof obj !== "object") return lista;
  if (visitados.has(obj)) return lista;

  visitados.add(obj);

  if (Array.isArray(obj)) {
    const eventosDaLista = obj.filter(pareceEvento);

    if (eventosDaLista.length >= 10) {
      lista.push(...eventosDaLista);
      return lista;
    }

    obj.forEach(item => extrairEventos(item, lista, visitados));
    return lista;
  }

  Object.values(obj).forEach(value => {
    if (value && typeof value === "object") {
      extrairEventos(value, lista, visitados);
    }
  });

  return lista;
}

function lerRelatorio() {
  const arquivos = [RELATORIO_SUPERA_FILE, RELATORIO_ATUAL_FILE];

  for (const arquivo of arquivos) {
    try {
      if (!fs.existsSync(arquivo)) continue;

      const dados = JSON.parse(fs.readFileSync(arquivo, "utf8"));
      const eventos = Array.isArray(dados.eventos) && dados.eventos.length
        ? dados.eventos
        : extrairEventos(dados);

      if (eventos.length || dados.totalEventos || dados.total_eventos || dados.resumo) {
        return {
          arquivo,
          dados,
          eventos
        };
      }
    } catch {}
  }

  return {
    arquivo: null,
    dados: {},
    eventos: []
  };
}

function statusTexto(item) {
  return String(
    item.status ||
    item.situacao ||
    item.estado ||
    item.confirmacao ||
    item.tipoStatus ||
    ""
  ).toUpperCase();
}

function isConfirmado(item) {
  const s = statusTexto(item);

  if (!s) return false;

  return s.includes("CONFIRM") ||
    s.includes("REALIZAD") ||
    s.includes("APROVAD") ||
    s.includes("LIBERAD") ||
    s.includes("PAGO");
}

function isCancelado(item) {
  const s = statusTexto(item);

  return s.includes("CANCEL");
}

function isPendente(item) {
  const s = statusTexto(item);

  return s.includes("PEND") ||
    s.includes("ESPERA") ||
    s.includes("AGUARD") ||
    s.includes("ORÇAMENTO") ||
    s.includes("ORCAMENTO");
}

function valorEvento(item) {
  const campos = [
    item.valorTotal,
    item.valor_total,
    item.total,
    item.valor,
    item.valorPrevisto,
    item.valor_previsto,
    item.faturamentoPrevisto,
    item.faturamento_previsto,
    item.preco,
    item.preço
  ];

  for (const c of campos) {
    const n = numero(c);
    if (n > 0) return n;
  }

  return 0;
}

function receitaEvento(item) {
  const campos = [
    item.receitaConfirmada,
    item.receita_confirmada,
    item.valorConfirmado,
    item.valor_confirmado,
    item.valorPago,
    item.valor_pago,
    item.pago,
    item.recebido
  ];

  for (const c of campos) {
    const n = numero(c);
    if (n > 0) return n;
  }

  if (isConfirmado(item)) return valorEvento(item);

  return 0;
}

function descontoEvento(item) {
  const campos = [
    item.desconto,
    item.descontos,
    item.valorDesconto,
    item.valor_desconto,
    item.gratuidade,
    item.valorGratuidade,
    item.valor_gratuidade
  ];

  for (const c of campos) {
    const n = Math.abs(numero(c));
    if (n > 0) return n;
  }

  return 0;
}

function dataEvento(item) {
  const candidatos = [
    item.data,
    item.dataEvento,
    item.data_evento,
    item.inicio,
    item.start,
    item.date
  ];

  for (const c of candidatos) {
    if (!c) continue;

    if (typeof c === "string") {
      const br = c.match(/\b(\d{1,2})[\/.-](\d{1,2})[\/.-](20\d{2})\b/);
      if (br) return new Date(Number(br[3]), Number(br[2]) - 1, Number(br[1]));

      const iso = Date.parse(c);
      if (Number.isFinite(iso)) return new Date(iso);
    }
  }

  return null;
}

function resumoNumero(dados, ...chaves) {
  const fontes = [dados, dados.resumo, dados.totais, dados.dashboard].filter(Boolean);

  for (const fonte of fontes) {
    for (const chave of chaves) {
      const n = numero(fonte[chave]);
      if (n > 0) return n;
    }
  }

  return 0;
}

function montarDashboard() {
  const { arquivo, dados, eventos } = lerRelatorio();

  const totalEventos =
    resumoNumero(dados, "totalEventos", "total_eventos") ||
    eventos.length;

  const eventosConfirmados =
    resumoNumero(dados, "eventosConfirmados", "eventos_confirmados") ||
    eventos.filter(isConfirmado).length;

  const eventosEmEspera =
    resumoNumero(dados, "eventosEmEspera", "eventos_em_espera") ||
    eventos.filter(isPendente).length;

  const eventosCancelados =
    resumoNumero(dados, "eventosCancelados", "eventos_cancelados") ||
    eventos.filter(isCancelado).length;

  let faturamentoPrevisto =
    resumoNumero(
      dados,
      "faturamentoPrevisto",
      "faturamento_previsto",
      "valorPrevisto",
      "valor_previsto",
      "totalPrevisto",
      "total_previsto"
    );

  let receitaConfirmada =
    resumoNumero(
      dados,
      "receitaConfirmada",
      "receita_confirmada",
      "receita",
      "totalConfirmado",
      "total_confirmado",
      "valorConfirmado",
      "valor_confirmado"
    );

  let descontosAplicados =
    resumoNumero(
      dados,
      "descontosAplicados",
      "descontos_aplicados",
      "descontos",
      "totalDescontos",
      "total_descontos"
    );

  if (!faturamentoPrevisto) {
    faturamentoPrevisto = eventos.reduce((s, e) => s + valorEvento(e), 0);
  }

  if (!receitaConfirmada) {
    receitaConfirmada = eventos.reduce((s, e) => s + receitaEvento(e), 0);
  }

  if (!descontosAplicados) {
    descontosAplicados = eventos.reduce((s, e) => s + descontoEvento(e), 0);
  }

  const meses = Array.from({ length: 12 }, (_, i) => ({
    mes: i + 1,
    nome: [
      "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
      "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    ][i],
    receita: 0,
    eventos: 0
  }));

  eventos.forEach(evento => {
    const d = dataEvento(evento);
    if (!d) return;

    const idx = d.getMonth();
    meses[idx].eventos += 1;
    meses[idx].receita += receitaEvento(evento);
  });

  return {
    ok: true,
    fonte: arquivo,
    atualizadoEm: new Date().toISOString(),
    nomeArquivo: dados.nomeArquivo || dados.nome_arquivo || "relatorio-supera.json",
    totalEventos,
    eventosConfirmados,
    eventosEmEspera,
    eventosCancelados,
    eventosNaLista: eventos.length,
    faturamentoPrevisto,
    receitaConfirmada,
    descontosAplicados,
    fluxoCaixa: receitaConfirmada - descontosAplicados,
    meses
  };
}

function registrarDashboardRelatorioOficialCejas(app) {
  if (!app || app.__CEJAS_DASHBOARD_RELATORIO_OFICIAL__) return;

  app.__CEJAS_DASHBOARD_RELATORIO_OFICIAL__ = true;

  app.get("/api/dashboard/relatorio-oficial", (_req, res) => {
    try {
      res.set("Cache-Control", "no-store");
      res.json(montarDashboard());
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: error.message
      });
    }
  });
}

module.exports = {
  montarDashboard,
  registrarDashboardRelatorioOficialCejas
};
EOF

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

require_line = 'const { registrarDashboardRelatorioOficialCejas } = require("./lib/dashboard-relatorio-oficial-cejas");'

if require_line not in s:
    if 'const path = require("path");' in s:
        s = s.replace('const path = require("path");', 'const path = require("path");\n' + require_line, 1)
    elif 'const express = require("express");' in s:
        s = s.replace('const express = require("express");', 'const express = require("express");\n' + require_line, 1)
    else:
        s = require_line + "\n" + s

call_line = 'registrarDashboardRelatorioOficialCejas(app);'

if call_line not in s:
    marker = "const app = express();"
    if marker not in s:
        raise SystemExit("❌ Não encontrei const app = express();")
    s = s.replace(marker, marker + "\n" + call_line, 1)

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("dashboard.html")
s = p.read_text()

s = re.sub(
    r'\s*<script>\s*// CEJAS_DASHBOARD_OFICIAL_START[\s\S]*?// CEJAS_DASHBOARD_OFICIAL_END\s*</script>',
    '',
    s
)

js = r'''
<script>
// CEJAS_DASHBOARD_OFICIAL_START
(function () {
  if (window.__CEJAS_DASHBOARD_OFICIAL__) return;
  window.__CEJAS_DASHBOARD_OFICIAL__ = true;

  function brl(valor) {
    return Number(valor || 0).toLocaleString("pt-BR", {
      style: "currency",
      currency: "BRL"
    });
  }

  function normalizar(txt) {
    return String(txt || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toUpperCase()
      .trim();
  }

  function todosElementos() {
    return Array.from(document.querySelectorAll("body *"));
  }

  function acharElementoPorTexto(texto) {
    const alvo = normalizar(texto);

    return todosElementos().find(el => {
      const t = normalizar(el.textContent);
      return t === alvo || t.includes(alvo);
    });
  }

  function acharCard(label) {
    const el = acharElementoPorTexto(label);
    if (!el) return null;

    let atual = el;

    for (let i = 0; i < 8 && atual; i++) {
      const txt = atual.textContent || "";

      if (
        txt.includes("R$") ||
        normalizar(txt).includes("EVENTOS") ||
        atual.className && String(atual.className).toLowerCase().includes("card")
      ) {
        return atual;
      }

      atual = atual.parentElement;
    }

    return el.parentElement || el;
  }

  function setPrimeiroDinheiro(card, valor) {
    if (!card) return;

    const els = Array.from(card.querySelectorAll("*"));
    const alvo = els.find(el => /^R\$\s*/.test((el.textContent || "").trim()));

    if (alvo) {
      alvo.textContent = brl(valor);
    }
  }

  function setSubtexto(card, texto) {
    if (!card) return;

    const els = Array.from(card.querySelectorAll("*"));
    const alvo = els.find(el => {
      const t = normalizar(el.textContent);
      return t.includes("EVENTO") || t.includes("CONFIRMADO") || t.includes("CANCELADO") || t.includes("DESCONTO");
    });

    if (alvo) alvo.textContent = texto;
  }

  function setNumeroCard(card, numero, subtexto) {
    if (!card) return;

    const els = Array.from(card.querySelectorAll("*"));

    const alvo = els.find(el => {
      const t = (el.textContent || "").trim();
      return /^[0-9]+$/.test(t);
    });

    if (alvo) alvo.textContent = String(numero);

    setSubtexto(card, subtexto);
  }

  function atualizarTopo(dados) {
    const titulo = acharElementoPorTexto("Dashboard de Resultados");
    if (!titulo) return;

    const parent = titulo.parentElement || titulo;
    const els = Array.from(parent.querySelectorAll("*"));

    const sub = els.find(el => normalizar(el.textContent).includes("DADOS REAIS"));

    if (sub) {
      sub.textContent = `Dados reais do relatório oficial • ${dados.eventosNaLista} eventos carregados • Atualizado pelo Supabase`;
    }
  }

  function atualizarMensal(dados) {
    const card = acharCard("Receita confirmada por mês");
    if (!card) return;

    let box = card.querySelector(".cejas-dashboard-oficial-meses");

    if (!box) {
      box = document.createElement("div");
      box.className = "cejas-dashboard-oficial-meses";
      box.style.cssText = "display:grid;gap:10px;margin-top:16px;width:100%;";
      card.appendChild(box);
    }

    const meses = Array.isArray(dados.meses) ? dados.meses : [];
    const max = Math.max(...meses.map(m => Number(m.receita || 0)), 1);

    box.innerHTML = meses.map(m => {
      const largura = Math.max(3, Math.round((Number(m.receita || 0) / max) * 100));

      return `
        <div style="display:grid;grid-template-columns:92px 1fr 120px;gap:10px;align-items:center;font-size:12px;">
          <strong style="color:rgba(255,255,255,.82);">${m.nome}</strong>
          <div style="height:12px;border-radius:999px;background:rgba(255,255,255,.08);overflow:hidden;">
            <div style="height:100%;width:${largura}%;border-radius:999px;background:linear-gradient(90deg,#22c55e,#a855f7);"></div>
          </div>
          <span style="color:#22c55e;font-weight:900;text-align:right;">${brl(m.receita)}</span>
        </div>
      `;
    }).join("");
  }

  function atualizarGratuidades(dados) {
    const card = acharCard("Gratuidades");
    if (!card) return;
    setPrimeiroDinheiro(card, dados.descontosAplicados || 0);
  }

  function atualizarFluxo(dados) {
    const card = acharCard("Fluxo de Caixa");
    if (!card) return;
    setPrimeiroDinheiro(card, dados.fluxoCaixa || dados.receitaConfirmada || 0);
  }

  async function carregarDashboardOficial() {
    try {
      const res = await fetch(`/api/dashboard/relatorio-oficial?_ts=${Date.now()}`, {
        cache: "no-store"
      });

      const dados = await res.json();

      if (!dados || dados.ok === false) {
        console.warn("Dashboard oficial não carregou:", dados);
        return;
      }

      atualizarTopo(dados);

      const cardPrevisto = acharCard("Faturamento previsto");
      setPrimeiroDinheiro(cardPrevisto, dados.faturamentoPrevisto);
      setSubtexto(cardPrevisto, `${dados.eventosNaLista} eventos no relatório`);

      const cardReceita = acharCard("Receita confirmada");
      setPrimeiroDinheiro(cardReceita, dados.receitaConfirmada);
      setSubtexto(cardReceita, `${dados.eventosConfirmados} eventos confirmados`);

      const cardDescontos = acharCard("Descontos aplicados");
      setPrimeiroDinheiro(cardDescontos, dados.descontosAplicados);
      setSubtexto(cardDescontos, `${brl(dados.descontosAplicados)} em descontos`);

      const cardPendentes = acharCard("Eventos pendentes");
      setNumeroCard(
        cardPendentes,
        dados.eventosEmEspera || 0,
        `${dados.eventosConfirmados || 0} confirmados • ${dados.eventosCancelados || 0} cancelados`
      );

      atualizarGratuidades(dados);
      atualizarMensal(dados);
      atualizarFluxo(dados);

      window.__CEJAS_DASHBOARD_OFICIAL_DADOS__ = dados;
      console.log("✅ Dashboard atualizado pelo relatório oficial:", dados);
    } catch (error) {
      console.warn("⚠️ Falha ao atualizar dashboard oficial:", error);
    }
  }

  function ligarBotaoAtualizar() {
    document.addEventListener("click", function (event) {
      const btn = event.target.closest("button, a");
      if (!btn) return;

      if (normalizar(btn.textContent).includes("ATUALIZAR DADOS")) {
        setTimeout(carregarDashboardOficial, 300);
        setTimeout(carregarDashboardOficial, 1200);
      }
    }, true);
  }

  document.addEventListener("DOMContentLoaded", function () {
    carregarDashboardOficial();
    ligarBotaoAtualizar();

    setTimeout(carregarDashboardOficial, 800);
    setTimeout(carregarDashboardOficial, 2000);
    setTimeout(carregarDashboardOficial, 4500);
  });

  window.cejasCarregarDashboardOficial = carregarDashboardOficial;
})();
// CEJAS_DASHBOARD_OFICIAL_END
</script>
'''

if "</body>" in s:
    s = s.replace("</body>", js + "\n</body>", 1)
else:
    s += js

p.write_text(s)
PY

echo ""
echo "🔎 Verificando sintaxe..."
node --check lib/dashboard-relatorio-oficial-cejas.js
node --check server.js

echo ""
echo "✅ Dashboard corrigido para ler o relatório oficial restaurado."
echo ""
echo "Agora rode:"
echo "npm start"
