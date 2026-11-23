// Safe DOM helpers for screens: text only via textContent, never innerHTML with data.
window.FH_DOM = {
  h: function (tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = String(text);
    return e;
  },
  asList: function (x) { return Array.isArray(x) ? x : []; }, // empty Lua {} arrives as JSON {}
  clear: function (el) { while (el.firstChild) el.removeChild(el.firstChild); },
  btn: function (label, onclick, cls) {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'btn ' + (cls || ''); b.textContent = label; b.onclick = onclick;
    return b;
  },
  list: function (rows) { // [{item, qty}] -> "2x meat, 1x carrot"
    return (Array.isArray(rows) ? rows : []).map(function (r) { return r.qty + '× ' + r.item; }).join(', ') || '-';
  },
  // Document-level Enter handler; returns a remover. Ignores Enter on a focused button (it clicks itself).
  onEnter: function (fn) {
    function k(ev) { if (ev.key === 'Enter' && !(ev.target && ev.target.tagName === 'BUTTON')) { ev.preventDefault(); fn(); } }
    document.addEventListener('keydown', k);
    return function () { document.removeEventListener('keydown', k); };
  },
  qty: function (max) { // numeric input, read back through clampQty
    const i = document.createElement('input');
    i.type = 'number'; i.className = 'qty'; i.min = '1'; i.max = String(max); i.value = '1';
    return i;
  },
  clampQty: function (input, max) {
    let n = parseInt(input.value, 10);
    if (!(n >= 1)) n = 1;
    if (n > max) n = max;
    return n;
  },
};
