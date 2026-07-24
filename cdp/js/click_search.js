(() => {
  const btn = document.querySelector('input[id$="FileArchiveFilter_btnSearch"]');
  if (!btn) return "NO_BUTTON";
  setTimeout(() => btn.click(), 250);
  return "SEARCH_SCHEDULED";
})()
