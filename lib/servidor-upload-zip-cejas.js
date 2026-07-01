const path = require("path");
const multer = require("multer");
const AdmZip = require("adm-zip");

const uploadZip = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 1024 * 1024 * 1024
  }
});

function limparEnv(value) {
  return String(value || "").trim().replace(/^["']|["']$/g, "");
}

function getEnv() {
  const url =
    limparEnv(process.env.SUPABASE_URL) ||
    limparEnv(process.env.NEXT_PUBLIC_SUPABASE_URL) ||
    limparEnv(process.env.PUBLIC_SUPABASE_URL);

  const serviceRole =
    limparEnv(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    limparEnv(process.env.CEJAS_SUPABASE_SERVICE_ROLE_KEY) ||
    limparEnv(process.env.SUPABASE_SERVICE_KEY) ||
    limparEnv(process.env.SUPABASE_SERVICE_ROLE) ||
    limparEnv(process.env.SUPABASE_SECRET_KEY);

  const bucket =
    limparEnv(process.env.SUPABASE_STORAGE_BUCKET) ||
    limparEnv(process.env.SUPABASE_BUCKET) ||
    "servidor-cejas";

  return { url, serviceRole, bucket };
}

function assertEnv() {
  const env = getEnv();

  if (!env.url || !env.serviceRole || !env.bucket) {
    throw new Error("Supabase Storage não configurado para upload ZIP.");
  }

  return env;
}

function headers(extra = {}) {
  const env = assertEnv();

  return {
    apikey: env.serviceRole,
    Authorization: `Bearer ${env.serviceRole}`,
    ...extra
  };
}

function limparPath(value = "") {
  return String(value || "")
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .split("/")
    .filter(part => {
      if (!part) return false;
      if (part === ".") return false;
      if (part === "..") return false;
      return true;
    })
    .join("/");
}

function encodeStoragePath(value = "") {
  return limparPath(value).split("/").map(encodeURIComponent).join("/");
}

function mimePorNome(nome = "") {
  const ext = path.extname(nome).toLowerCase();

  const map = {
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".csv": "text/csv",
    ".txt": "text/plain",
    ".json": "application/json",
    ".mp3": "audio/mpeg",
    ".mp4": "video/mp4",
    ".mov": "video/quicktime"
  };

  return map[ext] || "application/octet-stream";
}

function deveIgnorarZipEntry(nome = "") {
  const clean = limparPath(nome);
  const base = path.posix.basename(clean);

  if (!clean) return true;
  if (clean.startsWith("__MACOSX/")) return true;
  if (clean.includes("/__MACOSX/")) return true;
  if (base === ".DS_Store") return true;
  if (base.startsWith("._")) return true;
  if (base === "Thumbs.db") return true;
  if (base === "desktop.ini") return true;

  return false;
}

function normalizarNomeArquivo(nome = "") {
  return String(nome || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[<>:"|?*\x00-\x1F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function mesPorNumero(numero) {
  const meses = {
    "01": "01 JANEIRO",
    "02": "02 FEVEREIRO",
    "03": "03 MARCO",
    "04": "04 ABRIL",
    "05": "05 MAIO",
    "06": "06 JUNHO",
    "07": "07 JULHO",
    "08": "08 AGOSTO",
    "09": "09 SETEMBRO",
    "10": "10 OUTUBRO",
    "11": "11 NOVEMBRO",
    "12": "12 DEZEMBRO"
  };

  return meses[String(numero).padStart(2, "0")] || "VERIFICAR";
}

function destinoArquivoSolto(nomeArquivo) {
  const nome = normalizarNomeArquivo(nomeArquivo);
  const semExt = nome.replace(/\.[^.]+$/, "");

  let match =
    semExt.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})[.\-_/ ](20\d{2})\b/) ||
    semExt.match(/\b(20\d{2})[.\-_/ ](\d{1,2})[.\-_/ ](\d{1,2})\b/);

  let ano = "2026";
  let mes = "VERIFICAR";
  let pastaEvento = "VERIFICAR";

  if (match) {
    if (match[1].startsWith("20")) {
      ano = match[1];
      mes = mesPorNumero(match[2]);
    } else {
      ano = match[3];
      mes = mesPorNumero(match[2]);
    }
  } else {
    const dataCurta = semExt.match(/\b(\d{1,2})[.\-_/ ](\d{1,2})\b/);
    if (dataCurta) {
      mes = mesPorNumero(dataCurta[2]);
    }
  }

  let candidato = semExt
    .replace(/\b(20\d{2})\b/g, "")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}[.\-_/ ]20\d{2}\b/g, "")
    .replace(/\b20\d{2}[.\-_/ ]\d{1,2}[.\-_/ ]\d{1,2}\b/g, "")
    .replace(/\b\d{1,2}[.\-_/ ]\d{1,2}\b/g, "")
    .replace(/\b(orcamento|orçamento|boleto|demonstrativo|comprovante|recibo|nota fiscal|nf|contrato)\b/gi, "")
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();

  if (candidato && candidato.length >= 2) {
    pastaEvento = candidato.slice(0, 80);
  }

  return limparPath(`${ano}/${mes}/${pastaEvento}/${nome}`);
}

function destinoZipEntry(entryName) {
  const clean = limparPath(entryName);
  const parts = clean.split("/").filter(Boolean).map(normalizarNomeArquivo);

  if (!parts.length) return "";

  if (parts.length === 1) {
    return destinoArquivoSolto(parts[0]);
  }

  return limparPath(parts.join("/"));
}

async function uploadBufferSupabase(caminho, buffer, mimeType) {
  const env = assertEnv();
  const storagePath = encodeStoragePath(caminho);

  const response = await fetch(
    `${env.url.replace(/\/$/, "")}/storage/v1/object/${encodeURIComponent(env.bucket)}/${storagePath}`,
    {
      method: "POST",
      headers: headers({
        "Content-Type": mimeType || "application/octet-stream",
        "Cache-Control": "3600",
        "x-upsert": "true"
      }),
      body: buffer
    }
  );

  const text = await response.text();

  if (!response.ok) {
    throw new Error(text || `HTTP ${response.status}`);
  }

  return {
    bucket: env.bucket,
    caminho
  };
}

function registrarUploadZipServidorCejas(app) {
  if (!app || app.__CEJAS_UPLOAD_ZIP_SERVIDOR__) return;

  app.__CEJAS_UPLOAD_ZIP_SERVIDOR__ = true;

  app.post("/api/servidor/upload-zip", uploadZip.single("zip"), async (req, res) => {
    try {
      if (!req.file || !req.file.buffer) {
        return res.status(400).json({
          ok: false,
          message: "Nenhum arquivo ZIP enviado."
        });
      }

      const nomeOriginal = req.file.originalname || "arquivos.zip";

      if (!nomeOriginal.toLowerCase().endsWith(".zip")) {
        return res.status(400).json({
          ok: false,
          message: "Envie um arquivo .zip."
        });
      }

      const zip = new AdmZip(req.file.buffer);
      const entries = zip.getEntries();

      let enviados = 0;
      let ignorados = 0;
      const falhas = [];
      const exemplos = [];

      for (const entry of entries) {
        try {
          if (entry.isDirectory) {
            ignorados += 1;
            continue;
          }

          const nomeEntrada = limparPath(entry.entryName);

          if (deveIgnorarZipEntry(nomeEntrada)) {
            ignorados += 1;
            continue;
          }

          const buffer = entry.getData();

          if (!buffer || !buffer.length) {
            ignorados += 1;
            continue;
          }

          const destino = destinoZipEntry(nomeEntrada);

          if (!destino) {
            ignorados += 1;
            continue;
          }

          await uploadBufferSupabase(destino, buffer, mimePorNome(destino));

          enviados += 1;

          if (exemplos.length < 20) {
            exemplos.push(destino);
          }
        } catch (error) {
          falhas.push({
            arquivo: entry.entryName,
            erro: error.message
          });
        }
      }

      res.set("Cache-Control", "no-store");

      res.json({
        ok: falhas.length === 0,
        partial: falhas.length > 0 && enviados > 0,
        arquivoZip: nomeOriginal,
        totalNoZip: entries.length,
        enviados,
        ignorados,
        falhas,
        exemplos,
        message: falhas.length
          ? `${enviados} arquivo(s) enviados. ${falhas.length} falha(s).`
          : `${enviados} arquivo(s) enviados com sucesso pelo ZIP.`
      });
    } catch (error) {
      res.status(500).json({
        ok: false,
        message: "Erro ao processar ZIP: " + error.message
      });
    }
  });
}

module.exports = {
  registrarUploadZipServidorCejas
};
