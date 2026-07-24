(async () => {
  const out = [];
  try {
    const r = await fetch("/_api/web/lists?$select=Title,BaseType,ItemCount,RootFolder/ServerRelativeUrl&$expand=RootFolder&$top=200",
                          {headers:{Accept:"application/json;odata=verbose"}, credentials:"include"});
    out.push("STATUS " + r.status);
    const t = await r.text();
    try {
      const j = JSON.parse(t);
      for (const l of j.d.results) {
        out.push(l.BaseType + " | " + l.ItemCount + " | " + l.Title + " | " + (l.RootFolder ? l.RootFolder.ServerRelativeUrl : ""));
      }
    } catch (e) { out.push("RAW " + t.slice(0, 1500)); }
  } catch (e) { out.push("ERR " + e); }
  return out.join("\n");
})()
