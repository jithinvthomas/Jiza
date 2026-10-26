// Serves release files from the R2 bucket bound as FILES, at /download/<name>.
// Supports HEAD and Range requests so download managers can resume and use many connections.
const RELEASES = {
  "JizaDM.exe": { key: "JizaDM-1.0.1.exe", type: "application/vnd.microsoft.portable-executable" },
};

export async function onRequest({ request, env, params }) {
  const release = RELEASES[params.file];
  if (!release) return new Response("Not found", { status: 404 });
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }

  // If the R2 binding is ever missing, answer plainly instead of throwing.
  if (!env.FILES) return new Response("Downloads are being set up. Please try again shortly.", { status: 503, headers: { "Retry-After": "300" } });
  const head = await env.FILES.head(release.key);
  if (!head) return new Response("This release is not available right now.", { status: 503 });
  const size = head.size;
  const headers = new Headers({
    "Content-Type": release.type,
    "Content-Disposition": `attachment; filename="${params.file}"`,
    "Accept-Ranges": "bytes",
    ETag: head.httpEtag,
    "Last-Modified": head.uploaded.toUTCString(),
    "Cache-Control": "public, max-age=3600",
    "X-Content-Type-Options": "nosniff",
  });

  // Single byte range: "bytes=start-end", "bytes=start-" or "bytes=-suffix".
  const match = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get("Range") || "");
  const ifRange = request.headers.get("If-Range");
  if (match && (!ifRange || ifRange === head.httpEtag) && (match[1] || match[2])) {
    let start, end;
    if (match[1] === "") { start = Math.max(0, size - Number(match[2])); end = size - 1; }
    else { start = Number(match[1]); end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1; }
    if (start >= size || start > end) {
      return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${size}` } });
    }
    headers.set("Content-Range", `bytes ${start}-${end}/${size}`);
    headers.set("Content-Length", String(end - start + 1));
    if (request.method === "HEAD") return new Response(null, { status: 206, headers });
    const part = await env.FILES.get(release.key, { range: { offset: start, length: end - start + 1 } });
    return new Response(part.body, { status: 206, headers });
  }

  headers.set("Content-Length", String(size));
  if (request.method === "HEAD") return new Response(null, { status: 200, headers });
  const object = await env.FILES.get(release.key);
  return new Response(object.body, { status: 200, headers });
}
