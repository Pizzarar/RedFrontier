// trapper: data { title?, rows = { { container, slot, item, label, stars, legendary, price } }, notice?, notice_kind? }.
// rows are the sellable pelts the server computed (saddlebag + a nearby wagon); an update without `rows` only changes
// the inline notice (e.g. walked out of range). Actions: sell { container, slot, item }, close {}. No autofocus, Enter
// does nothing, Sell only by click; the owning lane revalidates position, container, item and price.
FH_UI.register('trapper', {
  last: null,
  open: function (el, data) { this.last = null; this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    if (data.rows === undefined && this.last) { // notice-only update (e.g. walked out of range)
      data = Object.assign({}, this.last, { notice: data.notice, notice_kind: data.notice_kind });
    } else { // Lua empty tables arrive as {}: coerce so stale rows never survive
      data = Object.assign({}, data, { rows: D.asList(data.rows) });
      this.last = data;
    }
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', data.title || 'Trapper'));
    if (data.notice) p.appendChild(D.h('p', 'note ' + (data.notice_kind === 'ok' ? 'ok' : 'err'), String(data.notice)));
    const body = D.h('div', 'body');
    const rows = D.asList(data.rows);
    if (!rows.length) body.appendChild(D.h('p', 'note', 'You have no pelts to sell here.'));
    rows.forEach(function (r) {
      const row = D.h('div', 'row card');
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', r.label));
      if (r.legendary) info.appendChild(D.h('span', 'rare', ' Legendary'));
      info.appendChild(D.h('div', '', stars(r.stars) + '  |  $' + r.price + ', from your ' + r.container));
      row.appendChild(info);
      row.appendChild(D.btn('Sell', function () {
        FH_UI.action('trapper', 'sell', { container: String(r.container), slot: r.slot, item: String(r.item) });
      }));
      body.appendChild(row);
    });
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('trapper'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; FH_DOM.clear(el); },
});

function stars(n) { return (typeof n === 'number' && n >= 1) ? '*'.repeat(n) : ''; }
