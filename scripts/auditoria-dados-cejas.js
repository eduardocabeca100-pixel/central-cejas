const fs = require("fs");
const path = require("path");

const root = process.cwd();

function walk(dir, result = []) {
  if (!fs.existsSync(dir)) return result;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);

    if (entry.name === "tmp-servidor") continue;

    if (entry.isDirectory()) {
      walk(full, result);
    } else if (entry.isFile()) {
      const stat = fs.statSync(full);
      result.push({
        path: path.relative(root, full).replace(/\\/g, "/"),
        size: stat.size,
        updatedAt: stat.mtime.toISOString()
      });
    }
  }

  return result;
}

const arquivosServidor = walk(path.join(root, "uploads", "servidor"));
const arquivosData = walk(path.join(root, "data"));
const lixeira = arquivosServidor.filter(item => item.path.includes("_LIXEIRA"));

console.log("");
console.log("📊 Auditoria de dados CEJAS");
console.log("");
console.log(`Arquivos no servidor: ${arquivosServidor.length}`);
console.log(`Arquivos em data/: ${arquivosData.length}`);
console.log(`Arquivos na lixeira: ${lixeira.length}`);

const totalServidor = arquivosServidor.reduce((acc, item) => acc + item.size, 0);
console.log(`Tamanho servidor: ${(totalServidor / 1024 / 1024).toFixed(2)} MB`);

console.log("");
console.log("Últimos arquivos do servidor:");
arquivosServidor
  .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
  .slice(0, 20)
  .forEach(item => {
    console.log(`- ${item.path}`);
  });
