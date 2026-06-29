#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "package.json" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js e package.json."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/gratuidades-menu-manual-deploy-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js package.json .gitignore "$BACKUP_DIR/" 2>/dev/null || true
cp *.html "$BACKUP_DIR/" 2>/dev/null || true
[ -d data ] && cp -R data "$BACKUP_DIR/data" 2>/dev/null || true
[ -d js ] && cp -R js "$BACKUP_DIR/js" 2>/dev/null || true
[ -d lib ] && cp -R lib "$BACKUP_DIR/lib" 2>/dev/null || true
[ -d scripts ] && cp -R scripts "$BACKUP_DIR/scripts" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

mkdir -p data scripts

echo "🧹 Limpando gratuidades antigas..."
cat > data/gratuidades-manuais.json <<'EOF'
[]
EOF

cat > data/gratuidades-ocultas.json <<'EOF'
[]
EOF

python3 <<'PY'
from pathlib import Path
import re

print("🔧 Ajustando menu lateral em todas as páginas...")

html_files = [p for p in Path(".").glob("*.html") if p.name not in {"login.html"}]

financeiro_patterns = [
    '<a href="financeiro.html">💰 Financeiro</a>',
    '<a href="/financeiro.html">💰 Financeiro</a>',
    '<a class="active" href="financeiro.html">💰 Financeiro</a>',
    '<a class="active" href="/financeiro.html">💰 Financeiro</a>',
]

for p in html_files:
    s = p.read_text()

    # Remove duplicações antigas de gratuidades no menu.
    s = re.sub(r'\n\s*<a[^>]*href=["\']/gratuidades\.html["\'][^>]*>[^<]*Gratuidades[^<]*</a>', '', s)
    s = re.sub(r'\n\s*<a[^>]*href=["\']gratuidades\.html["\'][^>]*>[^<]*Gratuidades[^<]*</a>', '', s)

    href = "/gratuidades.html" if 'href="/financeiro.html"' in s or 'href="/dashboard.html"' in s else "gratuidades.html"
    active = ' class="active"' if p.name == "gratuidades.html" else ""
    grat_link = f'<a{active} href="{href}">🏷 Gratuidades</a>'

    inserted = False

    for pat in financeiro_patterns:
        if pat in s:
            s = s.replace(pat, pat + "\n        " + grat_link, 1)
            inserted = True
            break

    # Se não achou financeiro, coloca antes de importar relatório.
    if not inserted:
        rel_patterns = [
            '<a href="importar-relatorio.html">▤ Importar Relatório (PDF)</a>',
            '<a href="/importar-relatorio.html">▤ Importar Relatório (PDF)</a>',
        ]

        for pat in rel_patterns:
            if pat in s:
                s = s.replace(pat, grat_link + "\n        " + pat, 1)
                inserted = True
                break

    # Se tiver mapa de permissões, garante permissão gratuidades.
    if '"gratuidades.html": "gratuidades"' not in s:
        s = s.replace(
            '"financeiro.html": "financeiro",',
            '"financeiro.html": "financeiro",\n        "gratuidades.html": "gratuidades",'
        )
        s = s.replace(
            "'financeiro.html': 'financeiro',",
            "'financeiro.html': 'financeiro',\n        'gratuidades.html': 'gratuidades',"
        )

    p.write_text(s)

print("✅ Menus HTML ajustados.")
PY

python3 <<'PY'
from pathlib import Path

p = Path("js/cejas-mobile-menu.js")

if p.exists():
    s = p.read_text()

    if '"/gratuidades.html"' not in s and "Gratuidades" not in s:
        s = s.replace(
            '{ href: "/financeiro.html", texto: "💰 Financeiro" },',
            '{ href: "/financeiro.html", texto: "💰 Financeiro" },\n      { href: "/gratuidades.html", texto: "🏷 Gratuidades" },'
        )

    p.write_text(s)
    print("✅ Menu mobile ajustado.")
else:
    print("⚠️ js/cejas-mobile-menu.js não encontrado. Pulando menu mobile.")
PY

python3 <<'PY'
from pathlib import Path

p = Path("server.js")
s = p.read_text()

start_marker = "// CEJAS_GRATUIDADES_API_START"
end_marker = "// CEJAS_GRATUIDADES_API_END"

api_block = r'''
// CEJAS_GRATUIDADES_API_START
const cryptoCejasGratManual = require("crypto");

const GRATUIDADES_FILE = path.join(__dirname, "data", "gratuidades-manuais.json");

function garantirArquivoGratuidadesManualCejas() {
  fs.mkdirSync(path.join(__dirname, "data"), { recursive: true });

  if (!fs.existsSync(GRATUIDADES_FILE)) {
    fs.writeFileSync(GRATUIDADES_FILE, "[]", "utf8");
  }
}

function carregarGratuidadesManualCejas() {
  garantirArquivoGratuidadesManualCejas();

  try {
    const data = JSON.parse(fs.readFileSync(GRATUIDADES_FILE, "utf8"));
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
}

function salvarGratuidadesManualCejas(lista) {
  garantirArquivoGratuidadesManualCejas();
  fs.writeFileSync(GRATUIDADES_FILE, JSON.stringify(lista || [], null, 2), "utf8");
}

function numeroGratManualCejas(valor) {
  if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;

  const texto = String(valor || "")
    .replace(/R\$/gi, "")
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".");

  const numero = Number(texto);
  return Number.isFinite(numero) ? numero : 0;
}

function perdaNegativaManualCejas(valor) {
  const numero = numeroGratManualCejas(valor);
  if (!numero) return 0;
  return numero > 0 ? -Math.abs(numero) : numero;
}

function calcularPerdaManualCejas(valorTotal, valorPago, valorPerdaInformado) {
  const informado = numeroGratManualCejas(valorPerdaInformado);

  if (informado !== 0) {
    return perdaNegativaManualCejas(informado);
  }

  const total = numeroGratManualCejas(valorTotal);
  const pago = numeroGratManualCejas(valorPago);
  const perda = Math.min(pago - total, 0);

  return perdaNegativaManualCejas(perda);
}

function dataParaISOManualCejas(data) {
  const texto = String(data || "").trim();

  if (!texto) return "";

  if (/^\d{4}-\d{2}-\d{2}/.test(texto)) {
    return texto.slice(0, 10);
  }

  let match = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/);
  if (match) {
    return `${match[3]}-${String(match[2]).padStart(2, "0")}-${String(match[1]).padStart(2, "0")}`;
  }

  match = texto.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2})\b/);
  if (match) {
    return `20${match[3]}-${String(match[2]).padStart(2, "0")}-${String(match[1]).padStart(2, "0")}`;
  }

  return "";
}

function isoParaDataBRManualCejas(iso) {
  if (!iso || !String(iso).includes("-")) return "";
  const [ano, mes, dia] = String(iso).slice(0, 10).split("-");
  if (!ano || !mes || !dia) return "";
  return `${dia}/${mes}/${ano}`;
}

function nomeMesManualCejas(key) {
  const nomes = [
    "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
    "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
  ];

  const [ano, mes] = String(key || "").split("-");
  const idx = Number(mes) - 1;

  if (!ano || idx < 0 || idx > 11) return key || "Sem mês";
  return `${nomes[idx]} de ${ano}`;
}

function normalizarBuscaManualCejas(texto) {
  return String(texto || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function normalizarGratuidadeManualCejas(item) {
  const dataISO = dataParaISOManualCejas(item?.dataISO || item?.data || "");

  const valorTotal = numeroGratManualCejas(
    item?.valorTotal ??
    item?.valorEvento ??
    item?.total ??
    0
  );

  const valorPago = numeroGratManualCejas(
    item?.valorPago ??
    item?.pago ??
    0
  );

  const valorPerda = calcularPerdaManualCejas(
    valorTotal,
    valorPago,
    item?.valorPerda ??
    item?.perda ??
    item?.valorGratuidade ??
    0
  );

  return {
    id: item?.id || `manual-${Date.now()}-${cryptoCejasGratManual.randomBytes(4).toString("hex")}`,
    origem: "manual",
    tipo: "manual",
    editavel: true,
    data: isoParaDataBRManualCejas(dataISO),
    dataISO,
    evento: String(item?.evento || "Gratuidade sem evento").trim(),
    valorTotal,
    valorPago,
    valorPerda,
    orgaoAssociado: String(
      item?.orgaoAssociado ||
      item?.orgao ||
      item?.associado ||
      item?.referencia ||
      "NÃO INFORMADO"
    ).trim(),
    referencia: String(item?.referencia || "").trim(),
    observacao: String(item?.observacao || "").trim(),
    criadoEm: item?.criadoEm || new Date().toISOString(),
    atualizadoEm: new Date().toISOString()
  };
}

function filtrarGratuidadesManualCejas(lista, query = {}) {
  const de = String(query.de || "").slice(0, 10);
  const ate = String(query.ate || "").slice(0, 10);
  const busca = normalizarBuscaManualCejas(query.busca || "");

  let itens = lista.map(normalizarGratuidadeManualCejas);

  if (de || ate) {
    itens = itens.filter(item => {
      if (!item.dataISO) return false;
      if (de && item.dataISO < de) return false;
      if (ate && item.dataISO > ate) return false;
      return true;
    });
  }

  if (busca) {
    itens = itens.filter(item => {
      const texto = normalizarBuscaManualCejas(`${item.evento} ${item.orgaoAssociado} ${item.referencia} ${item.observacao}`);
      return texto.includes(busca);
    });
  }

  itens.sort((a, b) => String(b.dataISO || "").localeCompare(String(a.dataISO || "")) || String(a.evento).localeCompare(String(b.evento)));

  return itens;
}

function resumirGratuidadesManualCejas(itens) {
  return itens.reduce((acc, item) => {
    acc.quantidade += 1;
    acc.valorTotal += numeroGratManualCejas(item.valorTotal);
    acc.valorPago += numeroGratManualCejas(item.valorPago);
    acc.valorPerda += perdaNegativaManualCejas(item.valorPerda);
    acc.manual += 1;
    return acc;
  }, {
    quantidade: 0,
    valorTotal: 0,
    valorPago: 0,
    valorPerda: 0,
    manual: 0,
    automatica: 0
  });
}

function graficosGratuidadesManualCejas(itens) {
  const porMes = {};
  const porOrgao = {};
  const porOrigem = {
    manual: {
      key: "manual",
      label: "Manual",
      quantidade: 0,
      valorPerda: 0
    }
  };

  for (const item of itens) {
    const mesKey = item.dataISO ? item.dataISO.slice(0, 7) : "SEM DATA";
    const orgao = item.orgaoAssociado || "NÃO INFORMADO";
    const perda = perdaNegativaManualCejas(item.valorPerda);

    porMes[mesKey] = porMes[mesKey] || {
      key: mesKey,
      label: nomeMesManualCejas(mesKey),
      quantidade: 0,
      valorPerda: 0
    };

    porOrgao[orgao] = porOrgao[orgao] || {
      key: orgao,
      label: orgao,
      quantidade: 0,
      valorPerda: 0
    };

    porMes[mesKey].quantidade += 1;
    porMes[mesKey].valorPerda += perda;

    porOrgao[orgao].quantidade += 1;
    porOrgao[orgao].valorPerda += perda;

    porOrigem.manual.quantidade += 1;
    porOrigem.manual.valorPerda += perda;
  }

  return {
    porMes: Object.values(porMes).sort((a, b) => String(a.key).localeCompare(String(b.key))),
    porOrigem: Object.values(porOrigem),
    porOrgao: Object.values(porOrgao).sort((a, b) => Math.abs(b.valorPerda) - Math.abs(a.valorPerda)).slice(0, 12)
  };
}

async function montarGratuidadesCejas(query = {}) {
  const lista = carregarGratuidadesManualCejas();
  const itens = filtrarGratuidadesManualCejas(lista, query);

  return {
    itens,
    resumo: resumirGratuidadesManualCejas(itens),
    graficos: graficosGratuidadesManualCejas(itens),
    atualizadoEm: new Date().toISOString()
  };
}

async function montarDashboardFinanceiroCejas() {
  const gratuidades = await montarGratuidadesCejas({});

  return {
    ok: true,
    receitaMensal: [],
    resumo: {
      totalReceitaConfirmada: 0,
      totalEventosConfirmados: 0,
      mesesComReceita: 0,
      gratuidades: gratuidades.resumo
    },
    graficosGratuidades: gratuidades.graficos,
    atualizadoEm: new Date().toISOString()
  };
}

app.get("/api/gratuidades", async (req, res) => {
  try {
    const dados = await montarGratuidadesCejas(req.query || {});
    res.json({ ok: true, ...dados });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar gratuidades: " + error.message
    });
  }
});

app.post("/api/gratuidades", express.json({ limit: "2mb" }), (req, res) => {
  try {
    const lista = carregarGratuidadesManualCejas();
    const novo = normalizarGratuidadeManualCejas(req.body || {});

    if (!novo.dataISO) {
      return res.status(400).json({ ok: false, message: "Informe a data da gratuidade." });
    }

    if (!novo.evento || novo.evento === "Gratuidade sem evento") {
      return res.status(400).json({ ok: false, message: "Informe o evento." });
    }

    lista.push(novo);
    salvarGratuidadesManualCejas(lista);

    res.json({
      ok: true,
      item: novo,
      message: "Gratuidade salva."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao salvar gratuidade: " + error.message
    });
  }
});

app.put("/api/gratuidades/:id", express.json({ limit: "2mb" }), (req, res) => {
  try {
    const id = req.params.id;
    const lista = carregarGratuidadesManualCejas();
    const index = lista.findIndex(item => item.id === id);

    if (index < 0) {
      return res.status(404).json({
        ok: false,
        message: "Gratuidade não encontrada."
      });
    }

    lista[index] = normalizarGratuidadeManualCejas({
      ...lista[index],
      ...req.body,
      id
    });

    salvarGratuidadesManualCejas(lista);

    res.json({
      ok: true,
      item: lista[index],
      message: "Gratuidade atualizada."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao editar gratuidade: " + error.message
    });
  }
});

app.delete("/api/gratuidades/:id", (req, res) => {
  try {
    const id = req.params.id;
    const lista = carregarGratuidadesManualCejas();
    const novaLista = lista.filter(item => item.id !== id);

    if (novaLista.length === lista.length) {
      return res.status(404).json({
        ok: false,
        message: "Gratuidade não encontrada."
      });
    }

    salvarGratuidadesManualCejas(novaLista);

    res.json({
      ok: true,
      message: "Gratuidade apagada."
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao apagar gratuidade: " + error.message
    });
  }
});

app.get("/api/dashboard-financeiro", async (_req, res) => {
  try {
    const dados = await montarDashboardFinanceiroCejas();
    res.json(dados);
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: "Erro ao carregar dashboard financeiro: " + error.message
    });
  }
});
// CEJAS_GRATUIDADES_API_END
'''

if start_marker in s and end_marker in s:
    start = s.index(start_marker)
    end = s.index(end_marker, start) + len(end_marker)
    s = s[:start] + api_block + s[end:]
else:
    insert_before = 'const USERS_FILE = path.join(__dirname, "data", "usuarios.json");'
    if insert_before not in s:
        raise SystemExit("❌ Não encontrei ponto seguro para inserir API de gratuidades.")
    s = s.replace(insert_before, api_block + "\n\n" + insert_before, 1)

# Garante permissão da aba Gratuidades para quem já tem financeiro ou admin.
if '{ id: "gratuidades", nome: "Gratuidades" }' not in s:
    s = s.replace(
        '{ id: "financeiro", nome: "Financeiro" },',
        '{ id: "financeiro", nome: "Financeiro" },\n  { id: "gratuidades", nome: "Gratuidades" },',
        1
    )

if '"/gratuidades.html": "gratuidades"' not in s:
    s = s.replace(
        '"/financeiro.html": "financeiro",',
        '"/financeiro.html": "financeiro",\n  "/gratuidades.html": "gratuidades",',
        1
    )

p.write_text(s)

print("✅ API de gratuidades ajustada para MANUAL apenas.")
PY

echo "🔎 Verificando sintaxe..."

node --check server.js

if [ -f js/cejas-mobile-menu.js ]; then
  node --check js/cejas-mobile-menu.js
fi

node <<'NODE'
const fs = require("fs");

for (const html of fs.readdirSync(".").filter((f) => f.endsWith(".html") && f !== "login.html")) {
  const content = fs.readFileSync(html, "utf8");
  const scripts = [...content.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

  fs.mkdirSync(".cejas-local-backups/check-menu-gratuidades", { recursive: true });

  scripts.forEach((code, index) => {
    fs.writeFileSync(`.cejas-local-backups/check-menu-gratuidades/${html}-${index + 1}.js`, code);
  });
}
NODE

for f in .cejas-local-backups/check-menu-gratuidades/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-menu-gratuidades

echo ""
echo "🛡️ Check de persistência/deploy..."

if npm run persist:check >/dev/null 2>&1; then
  npm run persist:check
else
  echo "⚠️ npm run persist:check não encontrado ou falhou."
fi

echo ""
echo "☁️ Sincronizando limpeza das gratuidades com Supabase..."

if npm run persist:sync >/dev/null 2>&1; then
  npm run persist:sync
else
  echo "⚠️ npm run persist:sync não encontrado ou falhou."
  echo "⚠️ Se você já usa Supabase Storage para persistência, rode manualmente o comando de sync antes do deploy."
fi

echo ""
echo "✅ Correção concluída."
echo ""
echo "Agora rode:"
echo "npm run dev"
echo ""
echo "Teste:"
echo "http://localhost:5500/gratuidades.html"
