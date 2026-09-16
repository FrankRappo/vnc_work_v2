(() => {
  const rb = document.querySelector('input[id$="FileArchiveFilter_btnReset"]');
  if (!rb) return "NO_RESET_BTN";
  setTimeout(() => rb.click(), 200);
  return "RESET_SCHEDULED";
})()
