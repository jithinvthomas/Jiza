const status = document.getElementById("status");
const capture = document.getElementById("capture");

chrome.storage.local.get({ capture: true }).then(v => { capture.checked = v.capture; });
capture.addEventListener("change", () => chrome.storage.local.set({ capture: capture.checked }));

chrome.runtime.sendMessage({ type: "ping" }).then(reply => {
  if (reply && reply.ok) {
    status.textContent = reply.running ? `Connected · Jiza ${reply.version || ""} is running` : `Connected · Jiza ${reply.version || ""} starts when needed`;
    status.className = "ok";
  } else {
    status.textContent = "Jiza isn't reachable. Open Jiza once, then Options > Browser > Repair connection.";
    status.className = "bad";
  }
});

document.getElementById("show").addEventListener("click", () => chrome.runtime.sendMessage({ type: "show" }).then(() => window.close()));

chrome.tabs.query({ active: true, currentWindow: true }).then(async ([tab]) => {
  if (!tab) return;
  document.getElementById("page").addEventListener("click", () =>
    chrome.runtime.sendMessage({ type: "send-page", pageUrl: tab.url, title: tab.title, tabId: tab.id }).then(() => window.close()));
  const media = await chrome.runtime.sendMessage({ type: "list-media", tabId: tab.id }) || [];
  if (media.length === 0) return;
  const list = document.getElementById("media");
  list.replaceChildren();
  for (const m of media.slice().reverse()) {
    const row = document.createElement("div");
    row.className = "media";
    const size = m.size > 0 ? ` (${(m.size / 1048576).toFixed(1)} MB)` : "";
    row.textContent = `${m.kind === "stream" ? "Stream" : m.kind === "audio" ? "Audio" : "Video"}${size}: ${m.url}`;
    row.title = m.url;
    row.addEventListener("click", () =>
      chrome.runtime.sendMessage({ type: "send-media", url: m.url, pageUrl: tab.url, title: tab.title, tabId: tab.id }).then(() => window.close()));
    list.appendChild(row);
  }
});
