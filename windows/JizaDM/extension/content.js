// Floating "Download with Jiza" button over videos, plus link collection for "Download all links".
(() => {
  if (window.top !== window || window.__jizaLoaded) return;
  window.__jizaLoaded = true;

  const FILE_EXT = /\.(mp4|m4v|mov|mkv|webm|avi|mp3|m4a|aac|wav|flac|ogg|opus|zip|rar|7z|gz|tar|bz2|xz|pdf|epub|exe|msi|dmg|apk|ipa|iso|torrent|docx?|xlsx?|pptx?)(\?|#|$)/i;

  chrome.runtime.onMessage.addListener((message, _sender, respond) => {
    if (message.type === "collect-links") respond(collectLinks());
  });

  function collectLinks() {
    const seen = new Set();
    const out = [];
    const add = (url, name) => {
      try {
        const absolute = new URL(url, location.href).href;
        if (!/^(https?|ftp):/i.test(absolute) || seen.has(absolute)) return;
        seen.add(absolute);
        out.push({ url: absolute, name });
      } catch { }
    };
    // Constant query, as in the Jiza app's findMedia(); page data is never executed.
    document.querySelectorAll("a[href]").forEach(a => { if (FILE_EXT.test(a.href) || a.hasAttribute("download")) add(a.href, a.getAttribute("download") || ""); });
    document.querySelectorAll("video[src], audio[src], video source[src], audio source[src]").forEach(e => add(e.src, ""));
    return out.slice(0, 500);
  }

  // ---- Floating button (Shadow DOM keeps page CSS out) ----
  const host = document.createElement("div");
  host.style.cssText = "position:fixed;z-index:2147483647;top:0;left:0;display:none;";
  const root = host.attachShadow({ mode: "closed" });
  root.innerHTML = `
    <style>
      .btn { font: 600 12px/1 "Segoe UI", system-ui, sans-serif; color: #fff; background: rgba(49,91,235,.92);
             border: 1px solid rgba(255,255,255,.35); border-radius: 8px; padding: 7px 10px; cursor: pointer;
             box-shadow: 0 6px 18px rgba(0,0,0,.35); backdrop-filter: blur(8px); display:flex; gap:6px; align-items:center; }
      .btn:hover { background: rgba(49,91,235,1); }
      .menu { margin-top: 6px; min-width: 260px; max-width: 420px; background: rgba(25,36,61,.97); border: 1px solid #2C3D66;
              border-radius: 10px; padding: 6px; box-shadow: 0 10px 30px rgba(0,0,0,.45); display: none; }
      .item { font: 13px/1.3 "Segoe UI", system-ui, sans-serif; color: #EEF2FF; padding: 8px 10px; border-radius: 6px; cursor: pointer;
              white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .item:hover { background: #213052; }
      .muted { color: #9AA8C7; font-size: 11px; }
    </style>
    <div class="btn" part="btn">&#8595; Download with Jiza</div>
    <div class="menu"></div>`;
  const button = root.querySelector(".btn");
  const menu = root.querySelector(".menu");
  document.documentElement.appendChild(host);

  let current = null;
  let hideTimer = 0;

  function place(video) {
    const r = video.getBoundingClientRect();
    if (r.width < 200 || r.height < 120) return;
    current = video;
    host.style.display = "block";
    host.style.top = Math.max(4, r.top + 10) + "px";
    host.style.left = Math.max(4, r.right - 190) + "px";
  }

  function hideSoon() {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => { if (menu.style.display !== "block") host.style.display = "none"; }, 1800);
  }

  document.addEventListener("mouseover", e => {
    const video = e.target.closest ? e.target.closest("video") : null;
    if (video) { clearTimeout(hideTimer); place(video); }
    else if (!host.contains(e.target)) hideSoon();
  }, true);
  host.addEventListener("mouseenter", () => clearTimeout(hideTimer));
  host.addEventListener("mouseleave", hideSoon);

  function item(label, detail, onClick) {
    const row = document.createElement("div");
    row.className = "item";
    row.textContent = label;
    if (detail) { const d = document.createElement("div"); d.className = "muted"; d.textContent = detail; row.appendChild(d); }
    row.addEventListener("click", () => { menu.style.display = "none"; host.style.display = "none"; onClick(); });
    menu.appendChild(row);
  }

  button.addEventListener("click", async () => {
    if (menu.style.display === "block") { menu.style.display = "none"; return; }
    menu.replaceChildren();
    item("Best quality from this page", "Jiza finds the real video (YouTube, Vimeo, X and 1000+ sites)", () =>
      chrome.runtime.sendMessage({ type: "send-page", pageUrl: location.href, title: document.title }));
    const src = current && (current.currentSrc || current.src);
    if (src && /^https?:/i.test(src)) item("This video file", src, () =>
      chrome.runtime.sendMessage({ type: "send-media", url: src, pageUrl: location.href, title: document.title }));
    const media = await chrome.runtime.sendMessage({ type: "list-media" }).catch(() => []) || [];
    for (const m of media.slice(-8).reverse()) {
      const size = m.size > 0 ? ` · ${(m.size / 1048576).toFixed(1)} MB` : "";
      item(m.kind === "stream" ? "Stream playlist" : m.kind === "audio" ? "Audio" : "Video", m.url.slice(0, 90) + size, () =>
        chrome.runtime.sendMessage({ type: "send-media", url: m.url, pageUrl: location.href, title: document.title }));
    }
    menu.style.display = "block";
  });
})();
