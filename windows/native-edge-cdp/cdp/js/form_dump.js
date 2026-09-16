(() => {
  const out = ["URL " + location.href];
  for (const s of document.querySelectorAll("select")) {
    out.push("SELECT name=" + s.name + " id=" + s.id);
    for (const o of s.options) out.push("   opt value=" + o.value + " | " + (o.text||"").replace(/\s+/g," ").trim());
  }
  for (const i of document.querySelectorAll("input[type=text],input[type=submit],input[type=button],a.btn,button")) {
    out.push("CTRL " + (i.tagName) + " name=" + (i.name||"") + " id=" + (i.id||"") + " val=" + ((i.value||i.textContent||"").replace(/\s+/g," ").trim().slice(0,60)));
  }
  return out.join("\n");
})()
