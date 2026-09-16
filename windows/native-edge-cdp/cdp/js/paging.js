(() => {
  const out = [];
  for (const a of document.querySelectorAll('a[href*="Page$"], a[href*="__doPostBack"], .ms-paging, [id*="Pager"] a')) {
    const t = (a.textContent||"").replace(/\s+/g," ").trim();
    if (t) out.push("PAGE " + t + " :: " + (a.getAttribute("href")||"").slice(0,120));
  }
  const cnt = document.querySelectorAll('a[href*="FileHandler.ashx"]').length;
  out.push("FILELINKS " + cnt);
  return out.join("\n") || "NO_PAGING FILELINKS " + cnt;
})()
