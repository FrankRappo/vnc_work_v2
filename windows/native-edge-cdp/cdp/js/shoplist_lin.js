// shoplist_lin.js — pull "product link :: card text (with price)" rows out of a
// shop listing/search page.  Written for T198 (picking fingerprint scanners),
// but the shape is generic: RU shops render a card as a <a href=".../product/...">
// buried some levels below the node that actually carries the price, so we walk
// UP from the link until the subtree text contains a ₽/руб and use that.
//
// Usage: cdp_linux.py get <url> --js js/shoplist_lin.js
(function () {
  var out = [], seen = {};
  document.querySelectorAll('a[href]').forEach(function (a) {
    var h = a.getAttribute('href') || '';
    if (!/product|catalog\/product|\/shop\//.test(h)) return;
    var box = a;
    for (var i = 0; i < 5 && box.parentElement; i++) {
      if (/₽|руб/i.test(box.innerText || '')) break;
      box = box.parentElement;
    }
    var t = (box.innerText || '').replace(/\s+/g, ' ').trim();
    if (t.length < 10 || seen[h]) return;
    seen[h] = 1;
    out.push(h + ' :: ' + t.slice(0, 160));
  });
  return out.slice(0, 60).join('\n');
})()
