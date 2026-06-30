#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "server.js" ] || [ ! -f "servidor.html" ] || [ ! -f "lib/servidor-supabase-definitivo.js" ]; then
  echo "❌ Rode dentro da pasta raiz do projeto, onde ficam server.js, servidor.html e lib/servidor-supabase-definitivo.js."
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".cejas-local-backups/servidor-estabilidade-apagar-tudo-$STAMP"
mkdir -p "$BACKUP_DIR"

cp server.js servidor.html package.json "$BACKUP_DIR/" 2>/dev/null || true
cp lib/servidor-supabase-definitivo.js "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Backup criado em: $BACKUP_DIR"

python3 <<'PY'
from pathlib import Path
import re

p = Path("lib/servidor-supabase-definitivo.js")
s = p.read_text()

# ---------------------------------------------------------------------
# 1. Garante listagem plana mais estável e sem cache local.
# ---------------------------------------------------------------------
if "CEJAS_LISTAGEM_ESTAVEL_SERVIDOR_START" not in s:
    marker = "function registrarRotasServidorSupabaseDefinitivo(app) {"
    if marker not in s:
        raise SystemExit("❌ Não encontrei registrarRotasServidorSupabaseDefinitivo(app).")

    helper = r'''
// CEJAS_LISTAGEM_ESTAVEL_SERVIDOR_START
async function listarArquivosComRetryCejas(tentativas = 3) {
  let ultimoErro = null;

  for (let i = 1; i <= tentativas; i++) {
    try {
      const arquivos = await listarArquivos();

      return Array.isArray(arquivos) ? arquivos : [];
    } catch (error) {
      ultimoErro = error;
      await new Promise(resolve => setTimeout(resolve, 450 * i));
    }
  }

  throw ultimoErro || new Error("Falha ao listar arquivos.");
}

async function listarStorageEstavelCejas() {
  const arquivos = await listarArquivosComRetryCejas(3);
  return montarArvoreDeArquivos(
    arquivos.map(pathItem => ({
      type: "file",
      name: path.posix.basename(pathItem),
      path: pathItem,
      size: 0,
      updatedAt: new Date().toISOString()
    }))
  );
}

function headersNoCacheCejas(res) {
  res.set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
  res.set("Pragma", "no-cache");
  res.set("Expires", "0");
}
// CEJAS_LISTAGEM_ESTAVEL_SERVIDOR_END

'''
    s = s.replace(marker, helper + "\n" + marker, 1)

# Troca rotas de leitura para sempre usar listagem estável.
s = re.sub(
    r'const root = await listarStorage\(\);',
    'const root = await listarStorageEstavelCejas();',
    s
)

# Troca headers antigos por helper único.
s = re.sub(
    r'res\.set\("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate"\);',
    'headersNoCacheCejas(res);',
    s
)

# ---------------------------------------------------------------------
# 2. Corrige storage-status para retry/listagem estável.
# ---------------------------------------------------------------------
s = re.sub(
    r'const arquivos = await listarArquivos\(\);',
    'const arquivos = await listarArquivosComRetryCejas(3);',
    s
)

# ---------------------------------------------------------------------
# 3. Cria função apagar tudo.
# ---------------------------------------------------------------------
if "async function apagarTudoServidorCejas" not in s:
    insert_before = "function registrarRotasServidorSupabaseDefinitivo(app) {"
    apagar_fn = r'''
async function apagarTudoServidorCejas() {
  const arquivos = await listarArquivosComRetryCejas(3);

  if (!arquivos.length) {
    return {
      ok: true,
      deleted: 0,
      message: "Servidor já estava vazio."
    };
  }

  const env = assertStorageEnv();
  let deleted = 0;
  const falhas = [];

  for (let i = 0; i < arquivos.length; i += 100) {
    const chunk = arquivos.slice(i, i + 100);

    try {
      await storageRequest(`/object/${encodeURIComponent(env.bucket)}`, {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prefixes: chunk
        })
      });

      deleted += chunk.length;
    } catch (error) {
      falhas.push({
        lote: `${i + 1}-${Math.min(i + 100, arquivos.length)}`,
        erro: error.message
      });
    }
  }

  return {
    ok: falhas.length === 0,
    partial: falhas.length > 0 && deleted > 0,
    deleted,
    failedBatches: falhas.length,
    falhas,
    message: falhas.length
      ? `${deleted} arquivo(s) apagados. ${falhas.length} lote(s) falharam.`
      : `${deleted} arquivo(s) apagados definitivamente do Supabase Storage.`
  };
}

'''
    s = s.replace(insert_before, apagar_fn + "\n" + insert_before, 1)

# ---------------------------------------------------------------------
# 4. Adiciona rota DELETE /api/servidor/tudo
# ---------------------------------------------------------------------
if 'app.delete("/api/servidor/tudo"' not in s:
    rota = r'''
  app.delete("/api/servidor/tudo", express.json({ limit: "2mb" }), async (req, res) => {
    try {
      const confirmacao = String(req.body?.confirmacao || req.query.confirmacao || "").trim();

      if (confirmacao !== "APAGAR TUDO") {
        return res.status(400).json({
          ok: false,
          message: "Confirmação inválida. Digite exatamente: APAGAR TUDO"
        });
      }

      const result = await apagarTudoServidorCejas();

      headersNoCacheCejas(res);

      res.json({
        ...result,
        bucket: getRuntimeEnv().bucket
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao apagar tudo: " + error.message
      });
    }
  });

'''
    s = s.replace('  app.get("/api/servidor/storage-status"', rota + '  app.get("/api/servidor/storage-status"', 1)

# Export opcional
if "apagarTudoServidorCejas" not in s.split("module.exports")[-1]:
    s = s.replace(
        "getSupabaseRuntimeStatus\n};",
        "getSupabaseRuntimeStatus,\n  apagarTudoServidorCejas\n};"
    )

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path
import re

p = Path("servidor.html")
s = p.read_text()

# Remove patch anterior, se existir.
s = re.sub(
    r'\s*<script>\s*// CEJAS_SERVIDOR_ESTAVEL_APAGAR_TUDO_START[\s\S]*?// CEJAS_SERVIDOR_ESTAVEL_APAGAR_TUDO_END\s*</script>',
    '',
    s
)

js = r'''
<script>
// CEJAS_SERVIDOR_ESTAVEL_APAGAR_TUDO_START
(function () {
  if (window.__CEJAS_SERVIDOR_ESTAVEL_APAGAR_TUDO__) return;
  window.__CEJAS_SERVIDOR_ESTAVEL_APAGAR_TUDO__ = true;

  const originalFetch = window.fetch;

  window.fetch = function (input, options) {
    let url = typeof input === "string" ? input : String(input && input.url || "");

    if (url.includes("/api/servidor/")) {
      const sep = url.includes("?") ? "&" : "?";
      url = `${url}${sep}_ts=${Date.now()}`;

      options = {
        ...(options || {}),
        cache: "no-store",
        headers: {
          ...((options && options.headers) || {}),
          "Cache-Control": "no-cache",
          "Pragma": "no-cache"
        }
      };

      return originalFetch(url, options);
    }

    return originalFetch(input, options);
  };

  function criarBotaoApagarTudo() {
    if (document.getElementById("cejasApagarTudoServidor")) return;

    const botoesArea =
      document.querySelector(".actions") ||
      document.querySelector(".topbar") ||
      document.querySelector("main") ||
      document.body;

    const btn = document.createElement("button");
    btn.id = "cejasApagarTudoServidor";
    btn.type = "button";
    btn.textContent = "Apagar tudo";
    btn.style.cssText = `
      border:1px solid rgba(239,68,68,.35);
      background:rgba(239,68,68,.16);
      color:#fecaca;
      border-radius:12px;
      padding:11px 14px;
      font-weight:900;
      cursor:pointer;
      margin-left:8px;
    `;

    btn.addEventListener("click", apagarTudoServidorCejas);

    botoesArea.appendChild(btn);
  }

  async function respostaJsonSegura(response) {
    const text = await response.text();

    try {
      return JSON.parse(text);
    } catch {
      throw new Error(text.slice(0, 400) || `Resposta inválida HTTP ${response.status}`);
    }
  }

  async function apagarTudoServidorCejas() {
    const aviso1 = confirm(
      "ATENÇÃO: isso vai apagar TODOS os arquivos do Servidor no Supabase Storage. Esta ação não volta. Continuar?"
    );

    if (!aviso1) return;

    const digitado = prompt('Para confirmar, digite exatamente: APAGAR TUDO');

    if (digitado !== "APAGAR TUDO") {
      alert("Confirmação cancelada. Nada foi apagado.");
      return;
    }

    const aviso2 = confirm(
      "Última confirmação: apagar definitivamente todos os arquivos do Servidor?"
    );

    if (!aviso2) return;

    try {
      const response = await fetch("/api/servidor/tudo", {
        method: "DELETE",
        cache: "no-store",
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-cache"
        },
        body: JSON.stringify({
          confirmacao: "APAGAR TUDO"
        })
      });

      const data = await respostaJsonSegura(response);

      if (!response.ok || data.ok === false) {
        throw new Error(data.message || "Erro ao apagar tudo.");
      }

      alert(data.message || "Arquivos apagados.");

      setTimeout(() => {
        if (typeof window.carregarServidor === "function") {
          window.carregarServidor();
        } else {
          location.reload();
        }
      }, 600);
    } catch (error) {
      alert("Erro ao apagar tudo: " + error.message);
    }
  }

  function melhorarCarregamentoServidor() {
    const botoes = [...document.querySelectorAll("button, a")];

    for (const b of botoes) {
      const txt = String(b.textContent || "").toLowerCase();

      if (txt.includes("atualizar") && !b.__cejasRefreshFix) {
        b.__cejasRefreshFix = true;

        b.addEventListener("click", () => {
          setTimeout(() => {
            if (typeof window.carregarServidor === "function") {
              window.carregarServidor();
            }
          }, 300);
        });
      }
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    criarBotaoApagarTudo();
    melhorarCarregamentoServidor();

    setTimeout(() => {
      if (typeof window.carregarServidor === "function") {
        window.carregarServidor();
      }
    }, 500);

    setTimeout(() => {
      criarBotaoApagarTudo();
      melhorarCarregamentoServidor();
    }, 1500);
  });

  window.apagarTudoServidorCejas = apagarTudoServidorCejas;
})();
// CEJAS_SERVIDOR_ESTAVEL_APAGAR_TUDO_END
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

node --check lib/servidor-supabase-definitivo.js
node --check server.js

node <<'NODE'
const fs = require("fs");
const html = fs.readFileSync("servidor.html", "utf8");
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

fs.mkdirSync(".cejas-local-backups/check-servidor-estavel", { recursive: true });

scripts.forEach((code, i) => {
  fs.writeFileSync(`.cejas-local-backups/check-servidor-estavel/script-${i + 1}.js`, code);
});
NODE

for f in .cejas-local-backups/check-servidor-estavel/*.js; do
  [ -f "$f" ] && node --check "$f"
done

rm -rf .cejas-local-backups/check-servidor-estavel

echo ""
echo "✅ Ajustes aplicados."
echo ""
echo "Agora rode:"
echo "npm start"
