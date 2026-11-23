// fence: data { title?, notice?, stock: [{id,label,price,qty,category}], sell: [{id,label,price,qty}] }.
// category = common|rare|leads (leads qty is fixed at 1). buy qty = per-deal cap, sell qty = units held.
// notice (string) is a lane message (trade result or refusal) shown inline; an update without stock/sell keeps the lists.
// Actions: buy { id, qty }, sell { id, qty }, close {}. The owning lane revalidates price and stock.
FH_UI.register('fence', {
  open: function (el, data) { this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    if (!Array.isArray(data.stock) && !Array.isArray(data.sell)) { // notice-only update (e.g. walked out of range)
      if (this.last) data = Object.assign({}, this.last, { notice: data.notice });
    } else { this.last = data; }
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', data.title || 'Fence'));
    if (data.notice) p.appendChild(D.h('p', 'note notice', String(data.notice)));
    const body = D.h('div', 'body');
    function section(name, rows, verb, action, showRare) {
      body.appendChild(D.h('h2', 'sub', name));
      rows = D.asList(rows);
      if (!rows.length) body.appendChild(D.h('p', 'note', 'Nothing.'));
      rows.forEach(function (r) {
        const row = D.h('div', 'row card');
        const info = D.h('div', 'grow');
        info.appendChild(D.h('strong', '', r.label));
        if (showRare && r.category === 'rare') info.appendChild(D.h('span', 'rare', ' RARE'));
        info.appendChild(D.h('div', '', '$' + r.price + ' each  |  ' + (showRare ? r.category + ', max ' + r.qty : 'you hold ' + r.qty)));
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
  },
  close: function (el) { FH_DOM.clear(el); },
});
