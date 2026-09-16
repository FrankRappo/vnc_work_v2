(() => {
  const seen = new Set(); const out = [];
  out.push("URL " + location.href);
  out.push("TITLE " + document.title.replace(/\s+/g," ").trim());
  for (const a of document.querySelectorAll("a[href]")) {
    const h = a.getAttribute("href") || "";
    if (/^(javascript:|#)/i.test(h)) continue;
    const t = (a.textContent || "").replace(/\s+/g," ").trim();
    const k = t + "|" + h;
    if (seen.has(k)) continue; seen.add(k);
    out.push(t.slice(0,90) + "  ->  " + h.slice(0,200));
  }
  return out.join("\n");
})()
