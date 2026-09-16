(async () => {
  const u = "/_layouts/15/atol.templates/Handlers/FileHandler.ashx?guid=29fa8fa5-c121-46ec-a10d-29144d83938e&webUrl=";
  try {
    const r = await fetch(u, {credentials:"include", redirect:"follow"});
    const h = [];
    h.push("STATUS " + r.status);
    h.push("FINALURL " + r.url);
    r.headers.forEach((v,k) => h.push("H " + k + ": " + v));
    try { await r.body.cancel(); } catch(e) {}
    return h.join("\n");
  } catch (e) { return "ERR " + e; }
})()
