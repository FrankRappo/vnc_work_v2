(() => {
  const out = [];
  const el = document.querySelector('[id$="FileArchiveFilter"]') || document.body;
  const host = document.querySelector("#ctl00_PlaceHolderMain") || document.body;
  let t = (host.innerText || "").replace(/\n{2,}/g, "\n").trim();
  if (t.length > 6000) t = t.slice(0, 6000) + "\n...TRUNC";
  out.push(t);
  return out.join("\n");
})()
