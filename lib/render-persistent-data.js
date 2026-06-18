const fs = require("fs");
const path = require("path");

const DYNAMIC_DATA_FILES = [
  "agenda-manual-local.json",
  "chat-mensagens-local.json",
  "financeiro.json",
  "orcamento-itens.json",
  "redefinicoes-senha-local.json",
  "relatorio-atual.json",
  "relatorio-supera.json",
  "ultimo-relatorio-texto-extraido.txt",
  "usuarios.json"
];

function lstatSafe(filePath) {
  try {
    return fs.lstatSync(filePath);
  } catch {
    return null;
  }
}

function existsOrSymlink(filePath) {
  return Boolean(lstatSafe(filePath));
}

function copyInitialFile(localPath, persistentPath) {
  const localStat = lstatSafe(localPath);

  if (!localStat || localStat.isSymbolicLink() || fs.existsSync(persistentPath)) {
    return;
  }

  fs.copyFileSync(localPath, persistentPath);
}

function linkDataFile(localPath, persistentPath) {
  const localStat = lstatSafe(localPath);

  if (localStat && localStat.isSymbolicLink()) return;

  if (localStat) {
    fs.rmSync(localPath, { force: true });
  }

  fs.symlinkSync(persistentPath, localPath);
}

function prepararDadosPersistentes(rootDir) {
  const persistentDir =
    process.env.CEJAS_PERSISTENT_DATA_DIR ||
    (process.env.RENDER ? path.join(rootDir, "uploads", ".data") : "");

  if (!persistentDir) return;

  const dataDir = path.join(rootDir, "data");

  try {
    fs.mkdirSync(dataDir, { recursive: true });
    fs.mkdirSync(persistentDir, { recursive: true });

    for (const fileName of DYNAMIC_DATA_FILES) {
      const localPath = path.join(dataDir, fileName);
      const persistentPath = path.join(persistentDir, fileName);

      copyInitialFile(localPath, persistentPath);

      if (fs.existsSync(persistentPath) || !existsOrSymlink(localPath)) {
        linkDataFile(localPath, persistentPath);
      }
    }

    console.log(`✅ Dados persistentes ativos em ${persistentDir}`);
  } catch (error) {
    console.log("⚠️ Dados persistentes não ativados:", error.message);
  }
}

module.exports = {
  prepararDadosPersistentes
};
