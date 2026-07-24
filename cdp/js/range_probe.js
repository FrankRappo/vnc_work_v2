(async () => {
  const u = "/_layouts/15/atol.templates/Handlers/FileHandler.ashx?guid=29fa8fa5-c121-46ec-a10d-29144d83938e&webUrl=";
  const t0 = performance.now();
  try {
    const r = await fetch(u, {credentials:"include", headers:{Range:"bytes=-65536"}});
    const cr = r.headers.get("content-range");
    const cl = r.headers.get("content-length");
    let n = -1;
    if (r.status === 206) { const b = await r.arrayBuffer(); n = b.byteLength; }
    else { try { await r.body.cancel(); } catch(e){} }
    return "STATUS " + r.status + " CR " + cr + " CL " + cl + " GOT " + n + " MS " + Math.round(performance.now()-t0);
  } catch (e) { return "ERR " + e + " MS " + Math.round(performance.now()-t0); }
})()
