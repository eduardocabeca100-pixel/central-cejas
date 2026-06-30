#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/servidor-painel-dia-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js package.json "$BACKUP_DIR/" 2>/dev/null || true
[ -f painel-dia.html ] && cp painel-dia.html "$BACKUP_DIR/" 2>/dev/null || true
[ -f lib/servidor-supabase-definitivo.js ] && cp lib/servidor-supabase-definitivo.js "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("lib/servidor-supabase-definitivo.js")

if not p.exists():
    raise SystemExit("❌ Não encontrei lib/servidor-supabase-definitivo.js.")

s = p.read_text()

# --------------------------------------------------------------------
# 1) Cache leve para não travar tanto a aba Servidor
# --------------------------------------------------------------------
if "CEJAS_CACHE_TREE_SERVIDOR_START" not in s:
    marker = "const uploadServidorSupabase = multer({"
    cache_block = r'''
// CEJAS_CACHE_TREE_SERVIDOR_START
let CEJAS_TREE_CACHE = {
  at: 0,
  root: null
};

function limparCacheServidorCejas() {
  CEJAS_TREE_CACHE = {
    at: 0,
    root: null
  };
}

async function listarStorageComCacheCejas() {
  const agora = Date.now();

  if (CEJAS_TREE_CACHE.root && agora - CEJAS_TREE_CACHE.at < 15000) {
    return CEJAS_TREE_CACHE.root;
  }

  const root = await listarStorage("");
  CEJAS_TREE_CACHE = {
    at: agora,
    root
  };

  return root;
}
// CEJAS_CACHE_TREE_SERVIDOR_END

'''
    if marker in s:
        s = s.replace(marker, cache_block + marker, 1)

# Limpa cache depois de alterações
for fn_name in ["uploadBuffer", "deletarItem", "moverItem"]:
    # Não mexe aqui por regex complexa; vamos limpar cache nas rotas.
    pass

# --------------------------------------------------------------------
# 2) Faz rotas usarem cache na leitura
# --------------------------------------------------------------------
s = s.replace("const root = await listarStorage();", "const root = await listarStorageComCacheCejas();")
s = s.replace("const root = await listarStorage(\"\");", "const root = await listarStorageComCacheCejas();")

# --------------------------------------------------------------------
# 3) Upload inteligente: não parar o lote inteiro quando um arquivo falhar
# --------------------------------------------------------------------
old_inteligente = r'''      const salvos = [];
      const verificar = [];

      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const originalRelative = paths[i] || file.originalname;
        const destino = destinoInteligente(originalRelative, file.originalname, anoPadrao);

        await uploadLocal(file.path, destino);
        fs.rmSync(file.path, { force: true });

        salvos.push(destino);
        if (destino.startsWith("VERIFICAR/")) verificar.push(destino);
      }

      res.json({
        ok: true,
        saved: salvos.length,
        verificar: verificar.length,
        exemplos: salvos.slice(0, 12),
        message: `${salvos.length} arquivo(s) salvos no Supabase Storage. ${verificar.length} foram para VERIFICAR.`
      });'''

new_inteligente = r'''      const salvos = [];
      const verificar = [];
      const falhas = [];

      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const originalRelative = paths[i] || file.originalname;
        const destino = destinoInteligente(originalRelative, file.originalname, anoPadrao);

        try {
          await uploadLocal(file.path, destino);
          salvos.push(destino);
          if (destino.startsWith("VERIFICAR/")) verificar.push(destino);
        } catch (error) {
          falhas.push({
            arquivo: file.originalname,
            destino,
            erro: error.message
          });
        } finally {
          try { fs.rmSync(file.path, { force: true }); } catch {}
        }
      }

      limparCacheServidorCejas();

      res.json({
        ok: falhas.length === 0,
        partial: falhas.length > 0 && salvos.length > 0,
        saved: salvos.length,
        failed: falhas.length,
        verificar: verificar.length,
        exemplos: salvos.slice(0, 12),
        falhas: falhas.slice(0, 30),
        message: falhas.length
          ? `${salvos.length} arquivo(s) salvos. ${falhas.length} arquivo(s) falharam. Veja a lista de falhas.`
          : `${salvos.length} arquivo(s) salvos no Supabase Storage. ${verificar.length} foram para VERIFICAR.`
      });'''

if old_inteligente in s:
    s = s.replace(old_inteligente, new_inteligente, 1)

# --------------------------------------------------------------------
# 4) Upload normal: não parar lote inteiro quando um arquivo falhar
# --------------------------------------------------------------------
old_upload = r'''      const salvos = [];

      if (!files.length) {
        return res.status(400).json({ ok: false, message: "Nenhum arquivo enviado." });
      }

      for (const file of files) {
        const destino = limparPath(path.posix.join(destinoPasta, nomeArquivoSeguro(file.originalname)));
        await uploadLocal(file.path, destino);
        fs.rmSync(file.path, { force: true });
        salvos.push(destino);
      }

      res.json({ ok: true, saved: salvos.length, exemplos: salvos.slice(0, 12), message: `${salvos.length} arquivo(s) salvos no Supabase Storage.` });'''

new_upload = r'''      const salvos = [];
      const falhas = [];

      if (!files.length) {
        return res.status(400).json({ ok: false, message: "Nenhum arquivo enviado." });
      }

      for (const file of files) {
        const destino = limparPath(path.posix.join(destinoPasta, nomeArquivoSeguro(file.originalname)));

        try {
          await uploadLocal(file.path, destino);
          salvos.push(destino);
        } catch (error) {
          falhas.push({
            arquivo: file.originalname,
            destino,
            erro: error.message
          });
        } finally {
          try { fs.rmSync(file.path, { force: true }); } catch {}
        }
      }

      limparCacheServidorCejas();

      res.json({
        ok: falhas.length === 0,
        partial: falhas.length > 0 && salvos.length > 0,
        saved: salvos.length,
        failed: falhas.length,
        exemplos: salvos.slice(0, 12),
        falhas: falhas.slice(0, 30),
        message: falhas.length
          ? `${salvos.length} arquivo(s) salvos. ${falhas.length} arquivo(s) falharam.`
          : `${salvos.length} arquivo(s) salvos no Supabase Storage.`
      });'''

if old_upload in s:
    s = s.replace(old_upload, new_upload, 1)

# --------------------------------------------------------------------
# 5) Limpa cache após mover/apagar
# --------------------------------------------------------------------
s = s.replace(
    'res.json({ ok: true, ...result, message: "Item movido no Supabase Storage." });',
    'limparCacheServidorCejas();\n      res.json({ ok: true, ...result, message: "Item movido no Supabase Storage." });'
)

s = s.replace(
    'res.json({ ok: true, ...result, message: `Item apagado definitivamente do Supabase Storage. Arquivos removidos: ${result.deleted}.` });',
    'limparCacheServidorCejas();\n      res.json({ ok: true, ...result, message: `Item apagado definitivamente do Supabase Storage. Arquivos removidos: ${result.deleted}.` });'
)

# --------------------------------------------------------------------
# 6) storage-status detalhado para conferir arquivos
# --------------------------------------------------------------------
old_status = r'''  app.get("/api/servidor/storage-status", async (_req, res) => {
    try {
      const arquivos = await listarArquivos();
      res.json({ ok: true, bucket: getRuntimeEnv().bucket, arquivos: arquivos.length, origem: "supabase-storage-rest" });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });'''

new_status = r'''  app.get("/api/servidor/storage-status", async (req, res) => {
    try {
      const arquivos = await listarArquivos();
      const detalhado = String(req.query.detalhado || "") === "1";

      res.json({
        ok: true,
        bucket: getRuntimeEnv().bucket,
        arquivos: arquivos.length,
        origem: "supabase-storage-rest",
        lista: detalhado ? arquivos.slice(0, 500) : undefined
      });
    } catch (error) {
      res.status(500).json({ ok: false, message: error.message });
    }
  });'''

if old_status in s:
    s = s.replace(old_status, new_status, 1)

p.write_text(s)
PY

# --------------------------------------------------------------------
# 7) Corrige duplicidade no Painel do Dia
# --------------------------------------------------------------------
if [ -f "painel-dia.html" ]; then
python3 <<'PY'
from pathlib import Path
import re

p = Path("painel-dia.html")
s = p.read_text()

# Remove versão antiga deste patch, se existir.
s = re.sub(
    r"\s*<script>\s*// CEJAS_DEDUPE_PAINEL_DIA_START[\s\S]*?// CEJAS_DEDUPE_PAINEL_DIA_END\s*</script>",
    "",
    s
)

js = r'''
<script>
// CEJAS_DEDUPE_PAINEL_DIA_START
(function () {
  if (window.__CEJAS_DEDUPE_PAINEL_DIA__) return;
  window.__CEJAS_DEDUPE_PAINEL_DIA__ = true;

  function normalizar(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/\s+/g, " ")
      .trim()
      .toUpperCase();
  }

  function chaveEventoObj(item) {
    if (!item || typeof item !== "object") return "";

    const evento =
      item.evento ||
      item.nomeEvento ||
      item.titulo ||
      item.title ||
      item.nome ||
      item.descricao ||
      "";

    const data =
      item.data ||
      item.dataEvento ||
      item.dataISO ||
      item.date ||
      "";

    const horario =
      item.horario ||
      item.hora ||
      item.periodo ||
      item.inicio ||
      item.start ||
      "";

    const sala =
      item.sala ||
      item.local ||
      item.espaco ||
      item.recurso ||
      "";

    const empresa =
      item.empresa ||
      item.cliente ||
      item.solicitante ||
      "";

    const status = item.status || "";

    return normalizar(`${data}|${horario}|${sala}|${evento}|${empresa}|${status}`);
  }

  function pareceEvento(item) {
    if (!item || typeof item !== "object") return false;

    return Boolean(
      item.evento ||
      item.nomeEvento ||
      item.titulo ||
      item.title ||
      item.sala ||
      item.local ||
      item.horario ||
      item.data ||
      item.dataEvento
    );
  }

  function dedupeArrays(obj) {
    if (!obj || typeof obj !== "object") return obj;

    if (Array.isArray(obj)) {
      const pareceListaEventos = obj.some(pareceEvento);

      if (pareceListaEventos) {
        const vistos = new Set();
        const nova = [];

        for (const item of obj) {
          const key = chaveEventoObj(item);

          if (!key || !vistos.has(key)) {
            if (key) vistos.add(key);
            nova.push(item);
          }
        }

        return nova.map(dedupeArrays);
      }

      return obj.map(dedupeArrays);
    }

    for (const key of Object.keys(obj)) {
      obj[key] = dedupeArrays(obj[key]);
    }

    return obj;
  }

  const originalFetch = window.fetch;

  window.fetch = async function () {
    const response = await originalFetch.apply(this, arguments);
    const url = String(arguments[0] || "");

    const deveDeduplicar =
      url.includes("painel") ||
      url.includes("agenda") ||
      url.includes("evento") ||
      url.includes("relatorio");

    if (!deveDeduplicar) return response;

    try {
      const clone = response.clone();
      const contentType = clone.headers.get("content-type") || "";

      if (!contentType.includes("application/json")) return response;

      const data = await clone.json();
      const limpo = dedupeArrays(data);

      const headers = new Headers(response.headers);
      headers.set("content-type", "application/json; charset=utf-8");

      return new Response(JSON.stringify(limpo), {
        status: response.status,
        statusText: response.statusText,
        headers
      });
    } catch {
      return response;
    }
  };

  function chaveCard(card) {
    const titulo =
      card.querySelector("h1,h2,h3,h4,strong")?.textContent ||
      "";

    const texto = card.textContent || "";

    const data = (texto.match(/Data:\s*([^\n\r]+)/i) || [])[1] || "";
    const horario = (texto.match(/Hor[aá]rio:\s*([^\n\r]+)/i) || [])[1] || "";
    const sala = (texto.match(/Sala:\s*([^\n\r]+)/i) || [])[1] || "";
    const empresa = (texto.match(/Empresa:\s*([^\n\r]+)/i) || [])[1] || "";

    return normalizar(`${data}|${horario}|${sala}|${titulo}|${empresa}`);
  }

  function dedupeDOM() {
    const candidatos = [
      ...document.querySelectorAll(".agenda-operacional article"),
      ...document.querySelectorAll(".agenda-operacional .card"),
      ...document.querySelectorAll(".event-card"),
      ...document.querySelectorAll("[data-evento-id]"),
      ...document.querySelectorAll("main article")
    ];

    const cards = candidatos.filter((card) => {
      const texto = normalizar(card.textContent || "");

      return texto.includes("DATA:") &&
        texto.includes("HORARIO:") &&
        texto.includes("SALA:");
    });

    const vistos = new Set();
    let removidos = 0;

    for (const card of cards) {
      const key = chaveCard(card);

      if (!key) continue;

      if (vistos.has(key)) {
        card.remove();
        removidos += 1;
      } else {
        vistos.add(key);
      }
    }

    if (removidos) {
      atualizarKPIs();
      atualizarSalas();
    }
  }

  function atualizarKPIs() {
    const cards = [...document.querySelectorAll("main article, .event-card, .card")].filter((card) => {
      const texto = normalizar(card.textContent || "");
      return texto.includes("DATA:") && texto.includes("HORARIO:") && texto.includes("SALA:");
    });

    const total = cards.length;
    const confirmados = cards.filter(card => normalizar(card.textContent).includes("CONFIRMADO")).length;
    const espera = cards.filter(card => normalizar(card.textContent).includes("ESPERA")).length;
    const cancelados = cards.filter(card => normalizar(card.textContent).includes("CANCELADO")).length;

    const labels = [...document.querySelectorAll("span,small,div,p")];

    function setValor(labelTexto, valor) {
      const label = labels.find(el => normalizar(el.textContent) === normalizar(labelTexto));
      if (!label) return;

      const box = label.closest("article, .kpi, .card, div");
      if (!box) return;

      const strong = box.querySelector("strong, h2, .numero, .value");
      if (strong) strong.textContent = String(valor);
    }

    setValor("EVENTOS", total);
    setValor("CONFIRMADOS", confirmados);
    setValor("EM ESPERA", espera);
    setValor("CANCELADOS", cancelados);
  }

  function atualizarSalas() {
    const cards = [...document.querySelectorAll("main article, .event-card, .card")].filter((card) => {
      const texto = normalizar(card.textContent || "");
      return texto.includes("DATA:") && texto.includes("HORARIO:") && texto.includes("SALA:");
    });

    const contagem = {};

    for (const card of cards) {
      const texto = card.textContent || "";
      const sala = (texto.match(/Sala:\s*([^\n\r]+)/i) || [])[1];

      if (!sala) continue;

      const key = normalizar(sala);
      contagem[key] = contagem[key] || {
        label: sala.trim(),
        total: 0
      };

      contagem[key].total += 1;
    }

    [...document.querySelectorAll("aside, section, div")].forEach((box) => {
      const texto = normalizar(box.textContent || "");
      if (!texto.includes("SALAS E RECURSOS")) return;

      const linhas = [...box.querySelectorAll("article, .sala, .room, .card, div")];

      for (const linha of linhas) {
        const linhaTexto = normalizar(linha.textContent || "");

        for (const item of Object.values(contagem)) {
          if (linhaTexto.includes(normalizar(item.label))) {
            const alvo = [...linha.querySelectorAll("span,small,strong,b")].find(el =>
              normalizar(el.textContent).includes("EVENTO")
            );

            if (alvo) alvo.textContent = `${item.total} evento(s)`;
          }
        }
      }
    });
  }

  const observer = new MutationObserver(() => {
    clearTimeout(window.__cejasDedupePainelTimer);
    window.__cejasDedupePainelTimer = setTimeout(dedupeDOM, 120);
  });

  document.addEventListener("DOMContentLoaded", () => {
    observer.observe(document.body, {
      childList: true,
      subtree: true
    });

    setTimeout(dedupeDOM, 300);
    setTimeout(dedupeDOM, 1000);
    setTimeout(dedupeDOM, 2500);
  });
})();
// CEJAS_DEDUPE_PAINEL_DIA_END
</script>
'''

# Coloca cedo no documento, antes dos scripts finais se possível.
if "</head>" in s:
    s = s.replace("</head>", js + "\n</head>", 1)
elif "</body>" in s:
    s = s.replace("</body>", js + "\n</body>", 1)
else:
    s += js

p.write_text(s)
PY
fi

echo ""
echo "🔎 Verificando sintaxe..."

node --check lib/servidor-supabase-definitivo.js
node --check server.js

if [ -f "painel-dia.html" ]; then
  node <<'NODE'
const fs = require("fs");
const html = fs.readFileSync("painel-dia.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-painel-dia", { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-painel-dia/script-${i + 1}.js`, code);
});
NODE

  for f in .cejas-local-backups/check-painel-dia/*.js; do
    [ -f "$f" ] && node --check "$f"
  done

  rm -rf .cejas-local-backups/check-painel-dia
fi

echo ""
echo "✅ Correção aplicada."
echo ""
echo "Agora rode:"
echo "npm run dev"
echo ""
echo "Depois teste:"
echo "1. Painel do Dia sem duplicar eventos."
echo "2. Servidor subindo arquivos."
echo "3. Abrir /api/servidor/storage-status?detalhado=1 para conferir lista."
