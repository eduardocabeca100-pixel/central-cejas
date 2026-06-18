(function () {
  if (window.__CEJAS_CHAT_WIDGET__) return;
  window.__CEJAS_CHAT_WIDGET__ = true;

  function criarWidget() {
    if (document.querySelector("[data-cejas-chat-widget]")) return;

    const linkChat = document.querySelector('a[href="/chat.html"], a[href="chat.html"]');
    if (linkChat) return;

    const btn = document.createElement("a");
    btn.href = "/chat.html";
    btn.setAttribute("data-cejas-chat-widget", "true");
    btn.textContent = "Chat";
    btn.style.cssText = [
      "position:fixed",
      "right:18px",
      "bottom:18px",
      "z-index:9999",
      "padding:10px 14px",
      "border-radius:12px",
      "background:linear-gradient(135deg,#7b61ff,#ff61d2)",
      "color:#fff",
      "font:800 13px system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif",
      "text-decoration:none",
      "box-shadow:0 18px 50px rgba(0,0,0,.32)"
    ].join(";");

    document.body.appendChild(btn);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", criarWidget);
  } else {
    criarWidget();
  }
})();
