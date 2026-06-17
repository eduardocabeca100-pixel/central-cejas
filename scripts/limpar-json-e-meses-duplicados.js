const fs = require("fs");
const path = require("path");

const base = path.join(__dirname, "..", "uploads", "servidor");

const mapaMeses = {
  "01 JANEIRO": "Janeiro",
  "02 FEVEREIRO": "Fevereiro",
  "03 MARÇO": "Março",
  "03 MARCO": "Março",
  "04 ABRIL": "Abril",
  "05 MAIO": "Maio",
  "06 JUNHO": "Junho",
  "07 JULHO": "Julho",
  "08 AGOSTO": "Agosto",
  "09 SETEMBRO": "Setembro",
  "10 OUTUBRO": "Outubro",
  "11 NOVEMBRO": "Novembro",
  "12 DEZEMBRO": "Dezembro"
};

function walk(dir, callback) {
  if (!fs.existsSync(dir)) return;

  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, item.name);

    if (item.isDirectory()) walk(full, callback);
    else callback(full);
  }
}

function removerJsonOrcamento() {
  walk(base, (file) => {
    const nome = path.basename(file).toLowerCase();

    if (nome.endsWith(".json") && nome.includes("orcamento")) {
      fs.unlinkSync(file);
      console.log("🗑️ JSON de orçamento removido:", path.relative(base, file));
    }
  });
}

function moverConteudo(origem, destino) {
  fs.mkdirSync(destino, { recursive: true });

  for (const item of fs.readdirSync(origem)) {
    const from = path.join(origem, item);
    const to = path.join(destino, item);

    if (fs.existsSync(to)) {
      console.log("⚠️ Já existe, mantendo:", path.relative(base, to));
      continue;
    }

    fs.renameSync(from, to);
    console.log("✅ Movido:", path.relative(base, from), "->", path.relative(base, to));
  }

  try {
    fs.rmdirSync(origem);
    console.log("✅ Pasta duplicada removida:", path.relative(base, origem));
  } catch {
    console.log("⚠️ Pasta duplicada ainda contém arquivos:", path.relative(base, origem));
  }
}

function corrigirMesesDuplicados() {
  if (!fs.existsSync(base)) return;

  for (const ano of fs.readdirSync(base, { withFileTypes: true })) {
    if (!ano.isDirectory()) continue;
    if (!/^\d{4}$/.test(ano.name)) continue;

    const pastaAno = path.join(base, ano.name);

    for (const pasta of fs.readdirSync(pastaAno, { withFileTypes: true })) {
      if (!pasta.isDirectory()) continue;

      const chave = pasta.name
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toUpperCase();

      const destinoNome = mapaMeses[chave];

      if (!destinoNome) continue;

      const origem = path.join(pastaAno, pasta.name);
      const destino = path.join(pastaAno, destinoNome);

      if (origem === destino) continue;

      moverConteudo(origem, destino);
    }
  }
}

removerJsonOrcamento();
corrigirMesesDuplicados();

console.log("✅ Limpeza concluída.");
