export default {
  async fetch(request, env) {
    const backendUrl = env.BACKEND_URL;

    if (!backendUrl) {
      return new Response("BACKEND_URL is not configured", { status: 500 });
    }

    const incomingUrl = new URL(request.url);
    const targetUrl = new URL(backendUrl);
    targetUrl.pathname = incomingUrl.pathname;
    targetUrl.search = incomingUrl.search;

    const requestHeaders = new Headers(request.headers);
    requestHeaders.set("Host", targetUrl.host);

    const backendRequest = new Request(targetUrl.toString(), {
      method: request.method,
      headers: requestHeaders,
      body: request.body,
      redirect: "manual"
    });

    const response = await fetch(backendRequest);
    const responseHeaders = new Headers(response.headers);

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: responseHeaders
    });
  }
};
