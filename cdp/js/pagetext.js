(() => {
  let t = (document.body ? document.body.innerText : "").replace(/\n{2,}/g, "\n").trim();
  const inputs = Array.from(document.querySelectorAll("input")).map(i => "INPUT type=" + i.type + " name=" + (i.name||"") + " ph=" + (i.placeholder||"")).join("\n");
  const btns = Array.from(document.querySelectorAll("button,a")).map(b => (b.textContent||"").replace(/\s+/g," ").trim()).filter(Boolean).slice(0,60).join(" | ");
  return "URL " + location.href + "\nTITLE " + document.title + "\n--- TEXT ---\n" + t.slice(0,3000) + "\n--- INPUTS ---\n" + inputs + "\n--- CLICKABLE ---\n" + btns.slice(0,1500);
})()
