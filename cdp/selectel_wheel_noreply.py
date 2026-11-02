#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Скролл малого дропдауна: wheel fire-and-forget (без ожидания ответа) + проверка vpc."""
import json, sys, time, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import edge_cdp as E

PORT = int(os.environ.get("EDGE_CDP_PORT", "9222"))

def http_json(path):
    import urllib.request
    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (PORT, path), timeout=10) as r:
        return json.loads(r.read().decode())

tabs = [t for t in http_json("/json/list") if t.get("type") == "page" and "selectel" in t.get("url", "")]
c = E.CDP(tabs[0]["webSocketDebuggerUrl"])
c.call("Runtime.enable")

CHECK = (
    "(function(){"
    "const dd=[...document.querySelectorAll('[class*=ant-select-dropdown]')].find(d=>d.offsetParent!==null);"
    "if(!dd)return JSON.stringify({st:'NO_DD'});"
    "const rr=dd.getBoundingClientRect();"
    "const all=[...dd.querySelectorAll('*')].filter(e=>e.offsetParent!==null);"
    "const vpcEl=all.find(e=>(e.innerText||'').trim()==='vpc');"
    "if(vpcEl){const node=vpcEl.closest('.ant-select-tree-treenode')||vpcEl;const r=node.getBoundingClientRect();"
    "if(r.y<=820&&r.bottom>=60)return JSON.stringify({st:'VPC_VISIBLE',x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});"
    "return JSON.stringify({st:'VPC_BELOW'});"
    "return JSON.stringify({st:'VPC_OUT',vt:Math.round(r.top)});}"
    "return JSON.stringify({st:'SCROLLING',ddTop:Math.round(rr.top),ddBot:Math.round(rr.bottom)});"
    "})()"
)

def fire_wheel(cx, cy, delta):
    """Отправить mouseWheel, НЕ ждать ответа (событие без response)."""
    c.ws.send(json.dumps({"id": c.n + 1000, "method": "Input.dispatchMouseEvent",
                          "params": {"type": "mouseWheel", "x": cx, "y": cy, "deltaX": 0, "deltaY": delta}}))

for step in range(1, 16):
    val, err = c.evaluate(CHECK)
    if err:
        print("evalerr:", err[:80], flush=True)
        time.sleep(0.5)
        continue
    d = json.loads(val)
    print("step", step, ":", val[:130], flush=True)
    if d.get("st") == "VPC_VISIBLE":
        print("=== click", d["x"], d["y"], "===", flush=True)
        for typ in ("mousePressed", "mouseReleased"):
            c.call("Input.dispatchMouseEvent", {"type": typ, "x": d["x"], "y": d["y"], "button": "left", "clickCount": 1, "buttons": 1})
        time.sleep(1.5)
        role, rerr = c.evaluate("(function(){const i=document.body.innerText;const m=i.match(/Роль\\n([^\\n]+)/);return m?m[1]:'NO_ROLE';})()")
        print("ROLE_NOW:", role, flush=True)
        if role == "vpc":
            print("=== SUCCESS ===", flush=True)
            c.evaluate("""(function(){
const set=(el,v)=>{const s=Object.getOwnPropertyDescriptor(el.__proto__,'value').set;s.call(el,v);el.dispatchEvent(new Event('input',{bubbles:true}));};
const inputs=[...document.querySelectorAll('input')].filter(i=>i.offsetParent!==null);
inputs.forEach((i,idx)=>{if(idx===0)set(i,'btdialer-api');if(i.type==='password')set(i,'BtDial2026_SelectelApi!');});
const texts=inputs.filter(i=>i.type==='text');
if(texts[1])set(texts[1],'API для BT Dialer — миграция 11.2026');
})()""")
            print("FIELDS_FILLED", flush=True)
        break
    cx = 760
    cy = 767
    fire_wheel(cx, cy, 300)
    time.sleep(0.4)
