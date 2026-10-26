// Jiza Download Manager browser integration (Manifest V3 service worker).
// Talks to JizaDM.exe through native messaging host "com.jiza.dm".
const HOST = "com.jiza.dm";

// Same rules as Jiza.Core DownloadPolicy (ported from the Jiza app's BrowserDownloadPolicy).
const EXTENSIONS = new Set(["mp4", "m4v", "mov", "mkv", "webm", "avi", "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "zip", "rar", "7z", "gz",
  "tar", "pdf", "epub", "dmg", "exe", "msi", "apk", "ipa", "iso", "torrent", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
  "bz2", "xz", "zst", "img", "bin", "wmv", "flv", "3gp", "msix", "appx", "jar", "deb", "rpm"]);
const DOWNLOAD_MIMES = new Set(["application/octet-stream", "application/x-bittorrent", "application/zip", "application/x-rar-compressed",
  "application/pdf", "application/x-7z-compressed", "application/x-msdownload", "application/x-msi",
  "application/vnd.android.package-archive", "application/x-iso9660-image", "application/gzip"]);
const STREAM_MIMES = new Set(["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "application/dash+xml"]);

let capture = true;
chrome.storage.local.get({ capture: true }).then(v => { capture = v.capture; });
chrome.storage.onChanged.addListener(changes => { if (changes.capture) capture = changes.capture.newValue; });

function send(message) {
  return new Promise(resolve => {
    chrome.runtime.sendNativeMessage(HOST, message, reply => {
      if (chrome.runtime.lastError) resolve({ ok: false, error: chrome.runtime.lastError.message });
      else resolve(reply || { ok: false, error: "No reply" });
    });
  });
}

async function cookiesFor(url) {
  try {
    const list = await chrome.cookies.getAll({ url });
    return list.map(c => `${c.name}=${c.value}`).join("; ");
  } catch { return ""; }
}

function extensionOf(url) {
  try {
    const path = new URL(url).pathname;
    const dot = path.lastIndexOf(".");
    return dot < 0 ? "" : path.slice(dot + 1).toLowerCase();
  } catch { return ""; }
}

function baseName(path) { return (path || "").split(/[\\/]/).pop(); }

async function sendLink(url, extra = {}) {
  const reply = await send({
    type: "link", url, cookies: await cookiesFor(url), userAgent: navigator.userAgent, ...extra,
  });
  flash(reply.ok);
  return reply;
}

function flash(ok) {
  chrome.action.setBadgeBackgroundColor({ color: ok ? "#315BEB" : "#D64545" });
  chrome.action.setBadgeText({ text: ok ? "✓" : "!" });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 2500);
}

// ---- Capture browser downloads -------------------------------------------------------------
const bypass = new Set();

function shouldCapture(item) {
  if (!capture || item.byExtensionId) return false;
  const url = item.finalUrl || item.url;
  if (!/^(https?|ftp):/i.test(url)) return false; // blob: and data: only exist inside the page
  const mime = (item.mime || "").toLowerCase().split(";")[0];
  const name = baseName(item.filename);
  const ext = extensionOf(url) || (name.includes(".") ? name.split(".").pop().toLowerCase() : "");
  return EXTENSIONS.has(ext) || mime.startsWith("video/") || mime.startsWith("audio/") || DOWNLOAD_MIMES.has(mime);
}

chrome.downloads.onCreated.addListener(async item => {
  const url = item.finalUrl || item.url;
  if (bypass.delete(url) || !shouldCapture(item)) return;
  try { await chrome.downloads.pause(item.id); } catch { }
  const reply = await send({
    type: "download",
    url,
    referrer: item.referrer || "",
    cookies: await cookiesFor(url),
    userAgent: navigator.userAgent,
    fileName: baseName(item.filename) || undefined,
    mime: item.mime || undefined,
    fileSize: item.totalBytes > 0 ? item.totalBytes : (item.fileSize > 0 ? item.fileSize : undefined),
  });
  if (reply.ok) {
    try { await chrome.downloads.cancel(item.id); await chrome.downloads.erase({ id: item.id }); } catch { }
    flash(true);
  } else {
    // Jiza isn't installed or didn't answer: let the browser finish the download itself.
    try { await chrome.downloads.resume(item.id); } catch { }
    flash(false);
  }
});

// ---- Context menus ---------------------------------------------------------------------------
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "jiza-link", title: "Download link with Jiza", contexts: ["link"] });
    chrome.contextMenus.create({ id: "jiza-media", title: "Download this video/audio with Jiza", contexts: ["video", "audio"] });
    chrome.contextMenus.create({ id: "jiza-image", title: "Download image with Jiza", contexts: ["image"] });
    chrome.contextMenus.create({ id: "jiza-page-video", title: "Download video from this page with Jiza", contexts: ["page"] });
    chrome.contextMenus.create({ id: "jiza-all", title: "Download all links on this page with Jiza", contexts: ["page"] });
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const pageUrl = info.pageUrl || tab?.url;
  switch (info.menuItemId) {
    case "jiza-link":
      return sendLink(info.linkUrl, { referrer: pageUrl });
    case "jiza-image":
      return sendLink(info.srcUrl, { referrer: pageUrl });
    case "jiza-media":
      // A blob: source only exists inside the page; hand the page to Jiza's video extractor instead.
      return sendLink(/^https?:/i.test(info.srcUrl || "") ? info.srcUrl : pageUrl, { referrer: pageUrl, title: tab?.title });
    case "jiza-page-video":
      return sendLink(pageUrl, { type: "media", title: tab?.title });
    case "jiza-all": {
      const links = await chrome.tabs.sendMessage(tab.id, { type: "collect-links" }).catch(() => []);
      if (!links || links.length === 0) return flash(false);
      const cookies = await cookiesFor(pageUrl);
      const reply = await send({ type: "batch", pageUrl, cookies, items: links.map(l => ({ url: l.url, fileName: l.name || undefined })) });
      return flash(reply.ok);
    }
  }
});

// ---- Media detection (for the floating button and popup) ------------------------------------
async function mediaFor(tabId) {
  const key = "media-" + tabId;
  return (await chrome.storage.session.get({ [key]: [] }))[key];
}

async function addMedia(tabId, entry) {
  const key = "media-" + tabId;
  const list = await mediaFor(tabId);
  if (list.some(m => m.url === entry.url)) return;
  list.push(entry);
  await chrome.storage.session.set({ [key]: list.slice(-30) });
  chrome.action.setBadgeBackgroundColor({ color: "#315BEB", tabId });
  chrome.action.setBadgeText({ text: String(list.length), tabId });
  chrome.tabs.sendMessage(tabId, { type: "media-found", count: list.length }).catch(() => { });
}

chrome.webRequest.onHeadersReceived.addListener(details => {
  if (details.tabId < 0) return;
  const header = name => (details.responseHeaders || []).find(h => h.name.toLowerCase() === name)?.value || "";
  const mime = header("content-type").toLowerCase().split(";")[0].trim();
  const size = parseInt(header("content-length") || "0", 10);
  const ext = extensionOf(details.url);
  let host = "";
  try { host = new URL(details.url).hostname; } catch { return; }
  // Video sites stream in small ranged chunks; the page URL (sent to yt-dlp) is the useful handle there.
  if (host.endsWith("googlevideo.com") || ext === "ts" || ext === "m4s" || mime === "video/mp2t" || mime === "video/iso.segment") return;
  let kind = null;
  if (STREAM_MIMES.has(mime) || ext === "m3u8" || ext === "mpd") kind = "stream";
  else if ((mime.startsWith("video/") || mime.startsWith("audio/")) && (size === 0 || size > 300 * 1024)) kind = mime.startsWith("video/") ? "video" : "audio";
  if (kind) addMedia(details.tabId, { url: details.url, kind, mime, size });
}, { urls: ["<all_urls>"], types: ["media", "xmlhttprequest", "other"] }, ["responseHeaders"]);

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.status === "loading" && change.url) chrome.storage.session.remove("media-" + tabId);
});
chrome.tabs.onRemoved.addListener(tabId => chrome.storage.session.remove("media-" + tabId));

// ---- Messages from the content script and popup --------------------------------------------
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  const tabId = message.tabId ?? sender.tab?.id;
  (async () => {
    switch (message.type) {
      case "list-media":
        return respond(await mediaFor(tabId));
      case "send-media":
        return respond(await sendLink(message.url, { referrer: message.pageUrl, title: message.title }));
      case "send-page":
        return respond(await sendLink(message.pageUrl, { type: "media", title: message.title }));
      case "ping":
        return respond(await send({ type: "ping" }));
      case "show":
        return respond(await send({ type: "show" }));
      case "bypass-next":
        bypass.add(message.url);
        return respond({ ok: true });
      default:
        return respond({ ok: false });
    }
  })();
  return true;
});
