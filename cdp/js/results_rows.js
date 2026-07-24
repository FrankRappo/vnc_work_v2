(() => {
  const out = ["URL " + location.href];
  const rows = document.querySelectorAll("table tr");
  let n = 0;
  for (const r of rows) {
    const t = (r.innerText || "").replace(/\s*\n\s*/g, " | ").replace(/\s{2,}/g, " ").trim();
    if (!t || t.length < 4) continue;
    const a = r.querySelector('a[href*="FileHandler.ashx"]');
    if (!a && !/Название/.test(t)) continue;
    out.push((a ? a.getAttribute("href").replace(/^.*guid=/, "guid=").slice(0, 50) : "HEADER") + "  ::  " + t.slice(0, 200));
    if (++n > 4000) break;
  }
  out.push("ROWS " + n);
  return out.join("\n");
})()
