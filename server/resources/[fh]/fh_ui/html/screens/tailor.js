// tailor: data { shop: {id,label,region_id,size}, tier, rows: [{id,label,kind,sex,price,min_tier,owned}], notice?, notice_kind? }
// (shaped like fh_tailor getStock). Each row shows label, kind, price, min tier. Owned rows say "Owned" and cannot be
// bought; rows above the player's tier are greyed with "Needs tier N" and cannot be bought. The server decides every buy
// (price, tier, owned, stock): the client only sends the entry id. A notice-only update keeps the rows.
// Actions: buy { entry_id }, close {}. No autofocus, Enter does nothing.
FH_UI.register('tailor', {
  last: null,
  open: function (el, data) { this.last = null; this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    if (data.rows === undefined) { // notice-only update keeps the rows
      if (this.last) data = Object.assign({}, this.last, { notice: data.notice, notice_kind: data.notice_kind });
    } else { // Lua empty tables arrive as {}: coerce so stale rows never survive
      data = Object.assign({}, data, { rows: D.asList(data.rows) });
      this.last = data;
    }
    const shop = data.shop || {};
    const tier = Number(data.tier) || 0;
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', shop.label || 'Tailor'));
    p.appendChild(D.h('p', 'note muted', 'Your standing here: tier ' + tier));
    if (data.notice) p.appendChild(D.h('p', 'note ' + (data.notice_kind === 'ok' ? 'ok' : 'err'), String(data.notice)));
    const body = D.h('div', 'body');
    const rows = D.asList(data.rows);
    if (!rows.length) body.appendChild(D.h('p', 'note', 'Nothing for sale here.'));
    rows.forEach(function (r) {
      const locked = !r.owned && Number(r.min_tier) > tier;
      const row = D.h('div', 'row card');
      if (locked) row.style.opacity = '0.55';
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', r.label || r.id));
      info.appendChild(D.h('div', '', (r.kind === 'outfit' ? 'Outfit' : 'Item') + ' · $' + r.price));
      if (r.owned) info.appendChild(D.h('div', 'note ok', 'Owned'));
      else if (locked) info.appendChild(D.h('div', 'note muted', 'Needs tier ' + r.min_tier));
      row.appendChild(info);
      const b = D.btn(r.owned ? 'Owned' : 'Buy', function () { FH_UI.action('tailor', 'buy', { entry_id: String(r.id) }); });
      if (r.owned || locked) b.disabled = true;
      row.appendChild(b);
      body.appendChild(row);
    });
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('tailor'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; FH_DOM.clear(el); },
});
