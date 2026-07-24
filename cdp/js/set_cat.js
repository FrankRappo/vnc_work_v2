/* ASCII-only source: Cyrillic via \uXXXX escapes so no encoding can mangle the file in transit.
   The postback is DEFERRED via setTimeout so Runtime.evaluate returns BEFORE the page reload
   destroys the JS execution context (otherwise the CDP call yields EVAL=NULL). */
(() => {
  const sel = document.querySelector('select[id$="FileArchiveFilter_drdCategory"]');
  if (!sel) return "NO_SELECT";
  const want = "Контрольно";  /* "Контрольно" */
  let hit = null;
  for (const o of sel.options) if ((o.text || "").indexOf(want) === 0) hit = o;
  if (!hit) return "NO_OPTION";
  sel.value = hit.value;
  const nm = sel.name;
  setTimeout(() => { try { __doPostBack(nm, ""); } catch (e) { sel.dispatchEvent(new Event("change", {bubbles:true})); } }, 300);
  return "SCHEDULED " + nm + " => " + hit.text;
})()
