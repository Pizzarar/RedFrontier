// fence: data { title?, stock: [{id,label,price,qty,rare?}], sell: [{id,label,price,qty}] }.
// Actions: buy { id, qty }, sell { id, qty }, close {}. The owning lane revalidates price and stock.
FH_UI.register('fence', {
  open: function (el, data) { this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', data.title || 'Fence'));
    const body = D.h('div', 'body');
    function section(name, rows, verb, action, showRare) {
      body.appendChild(D.h('h2', 'sub', name));
      if (!rows || !rows.length) body.appendChild(D.h('p', 'note', 'Nothing.'));
      (rows || []).forEach(function (r) {
        const row = D.h('div', 'row card');
        const info = D.h('div', 'grow');
        info.appendChild(D.h('strong', '', r.label));
        if (showRare && r.rare) info.appendChild(D.h('span', 'rare', ' RARE'));
        info.appendChild(D.h('div', '', '$' + r.price + ' each  |  qty ' + r.qty));
        row.appendChild(info);
        const q = D.qty(r.qty);
        row.appendChild(q);
        const b = D.btn(verb, function () {
          FH_UI.action('fence', action, { id: String(r.id), qty: D.clampQty(q, r.qty) });
        });
        b.disabled = !(r.qty >= 1);
        row.appendChild(b);
        body.appendChild(row);
      });
    }
    section('For sale', data.stock, 'Buy', 'buy', true);
    section('Your goods', data.sell, 'Sell', 'sell', false);
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('fence'); }));
    el.appendChild(p);
    const first = p.querySelector('button:not([disabled])'); if (first) first.focus();
  },
  close: function (el) { FH_DOM.clear(el); },
});
