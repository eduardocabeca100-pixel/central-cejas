const fs = require("fs");
const path = require("path");

function registrarServidorPdfViewer(app) {
  app.get("/api/servidor/visualizar-pdf", (req, res) => {
    try {
      const caminho = String(req.query.path || "")
        .replace(/\\/g, "/")
        .replace(/^\/+/, "");

      if (!caminho || !caminho.toLowerCase().endsWith(".pdf")) {
        return res.status(400).send("Arquivo PDF inválido.");
      }

      const base = path.resolve(__dirname, "..", "uploads", "servidor");
      const arquivo = path.resolve(base, caminho);

      if (!arquivo.startsWith(base)) {
        return res.status(403).send("Acesso negado.");
      }

      if (!fs.existsSync(arquivo)) {
        return res.status(404).send("PDF não encontrado.");
      }

      res.setHeader("Content-Type", "application/pdf");
      res.setHeader("Content-Disposition", `inline; filename="${path.basename(arquivo)}"`);
      res.sendFile(arquivo);
    } catch (error) {
      res.status(500).send(error.message);
    }
  });

  console.log("✅ Visualizador PDF do servidor carregado.");
}

module.exports = {
  registrarServidorPdfViewer
};
