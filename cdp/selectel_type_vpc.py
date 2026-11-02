#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Клик по селекту роли → впечатать 'vpc' доверенными клавишами → клик по отфильтрованному узлу."""
import json, sys, time, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import edge_cdp as E

PORT = int(os.environ.get("EDGE_CDP_PORT", "9222"))

def http_json(path):
    import urllib.request
    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (PORT, path), timeout=10) as r:
        return json.loads(r.read().decode())

def page_ws():
    tabs = [t for t in http_json("/json/list") if t.get("type") == "page" and "selectel" in t.get("url", "")]
    return tabs[0]["webSocketDebuggerUrl"]

def type_text(c, text):
    for ch in text:
        c.call("Input.dispatchKeyEvent", {"type": "keyDown", "key": ch, "text": ch, "unmodifiedText": ch})
        c.call("Input.dispatchKeyEvent", {"type": "keyUp", "key": ch})
        time.sleep(0.06)

def main():
    c = E.CDP(page_ws())
    c.call("Runtime.enable")

    def ev(expr):
        val, err = c.evaluate(expr)
        if err:
            raise RuntimeError(err)
        return val

    # 1. закрыть залипшее
    ev("document.activeElement&&document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))")
    time.sleep(0.5)
    # 2. клик по селекту роли (свежие координаты)
    sxy = json.loads(ev("(function(){const sel=document.querySelector('div.ant-select-selector');sel.scrollIntoView({block:'center'});const r=sel.getBoundingClientRect();return JSON.stringify({x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});})()"))
    for ci in (1,):
        for typ in ("mousePressed", "mouseReleased"):
            c.call("Input.dispatchMouseEvent", {"type": typ, "x": sxy["x"], "y": sxy["y"], "button": "left", "clickCount": ci, "buttons": 1})
        time.sleep(0.12)
    time.sleep(1.5)
    # 3. впечатать vpc в поисковое поле (оно в фокусе после открытия)
    type_text(c, "vpc")
    time.sleep(1.5)
    # 4. найти отфильтрованный узел vpc
    st = ev("""(function(){
const dd=[...document.querySelectorAll('[class*=ant-select-dropdown]')].find(d=>d.offsetParent!==null);
if(!dd)return JSON.stringify({st:'NO_DD',text:(document.activeElement?document.activeElement.value:'?')});
const all=[...dd.querySelectorAll('*')].filter(e=>e.offsetParent!==null);
const vpcEl=all.find(e=>(e.innerText||'').trim()==='vpc');
if(!vpcEl)return JSON.stringify({st:'NO_VPC_AFTER_FILTER',ddText:(dd.innerText||'').replace(/\\n+/g,' | ').slice(0,120)});
let node=vpcEl.closest('.ant-select-tree-treenode')||vpcEl;
const r=node.getBoundingClientRect();
return JSON.stringify({st:'VPC',x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});
})()""")
    d = json.loads(st)
    print("после фильтра:", st, flush=True)
    if d["st"] != "VPC":
        return 1
    # 5. клик по узлу
    for typ in ("mousePressed", "mouseReleased"):
        c.call("Input.dispatchMouseEvent", {"type": typ, "x": d["x"], "y": d["y"], "button": "left", "clickCount": 1, "buttons": 1})
    time.sleep(1.5)
    role = ev("(function(){const i=document.body.innerText;const m=i.match(/Роль\\n([^\\n]+)/);return m?m[1]:'NO_ROLE_TEXT';})()")
    print("ROLE_NOW:", role, flush=True)
    if role == "vpc":
        print("=== SUCCESS: роль vpc выбрана ===", flush=True)
        # заполнить поля
        ev("""(function(){
const set=(el,v)=>{const s=Object.getOwnPropertyDescriptor(el.__proto__,'value').set;s.call(el,v);el.dispatchEvent(new Event('input',{bubbles:true}));};
const inputs=[...document.querySelectorAll('input')].filter(i=>i.offsetParent!==null);
inputs.forEach((i,idx)=>{if(idx===0)set(i,'btdialer-api');if(i.type==='password')set(i,'BtDial2026_SelectelApi!');});
const texts=inputs.filter(i=>i.type==='text');
if(texts[1])set(texts[1],'API для BT Dialer — миграция 11.2026');
})()""")
        return 0
    return 1

if __name__ == "__main__":
    sys.exit(main())
