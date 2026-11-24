// tradepost: data { label, region, goods: [{item,label,price,shortage,saturation}], supplies: [{item,label,price}],
// max_sell, max_buy, notice?, notice_kind? }.
// Goods show "In demand here" when shortage >= 0.15, "Market is flooded" when saturation > 0.3 (same text as the old
// ox_lib menu). notice is a lane message (trade result or refusal) shown inline; an update without goods/supplies keeps
// the lists. Actions: sell { item, amount }, buy { item, amount } (amount clamped 1..max client-side), close {}.
FH_UI.register('tradepost', {
  open: function (el, data) { this.last = null; this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    if (data.goods === undefined && data.supplies === undefined) { // notice-only update (e.g. walked out of range)
      if (this.last) data = Object.assign({}, this.last, { notice: data.notice, notice_kind: data.notice_kind });
    } else { // Lua empty tables arrive as {}: coerce so stale rows never survive
      data = Object.assign({}, data, { goods: D.asList(data.goods), supplies: D.asList(data.supplies) });
      this.last = data;
    }
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', data.label || 'Trade Post'));
    if (data.notice) p.appendChild(D.h('p', 'note ' + (data.notice_kind === 'ok' ? 'ok' : 'err'), String(data.notice)));
    const body = D.h('div', 'body');
    function section(name, rows, verb, action, max) {
      body.appendChild(D.h('h2', 'sub', name));
      rows = D.asList(rows);
      if (!rows.length) body.appendChild(D.h('p', 'note', 'Nothing.'));
      rows.forEach(function (r) {
        const row = D.h('div', 'row card');
        const info = D.h('div', 'grow');
        info.appendChild(D.h('strong', '', r.label));
        if (r.shortage >= 0.15) info.appendChild(D.h('div', '', 'In demand here'));
        else if (r.saturation > 0.3) info.appendChild(D.h('div', '', 'Market is flooded'));
        info.appendChild(D.h('div', '', '$' + r.price + ' each'));
        row.appendChild(info);
        const q = D.qty(max);
        row.appendChild(q);
        const b = D.btn(verb, function () {
          FH_UI.action('tradepost', action, { item: String(r.item), amount: D.clampQty(q, max) });
        });
        row.appendChild(b);
        body.appendChild(row);
      });
    }
    section('Your goods', data.goods, 'Sell', 'sell', data.max_sell || 1);
    section('For sale', data.supplies, 'Buy', 'buy', data.max_buy || 1);
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('tradepost'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; FH_DOM.clear(el); },
});
