/* select model "АТОЛ 25Ф" in the file-archive filter and submit the search (deferred postback) */
(() => {
  const m = document.querySelector('select[id$="FileArchiveFilter_drdModel"]');
  if (!m) return "NO_MODEL_SELECT";
  const want = "\u0410\u0422\u041e\u041b 25\u0424";
  let hit = null;
  for (const o of m.options) { if ((o.text || "").trim() === want) { hit = o; break; } }
  if (!hit) return "NO_OPTION";
  m.value = hit.value;
  const btn = document.querySelector('input[id$="FileArchiveFilter_btnSearch"]');
  if (!btn) return "NO_BUTTON";
  setTimeout(() => { btn.click(); }, 300);
  return "SEARCH_SCHEDULED model=" + hit.text;
})()
