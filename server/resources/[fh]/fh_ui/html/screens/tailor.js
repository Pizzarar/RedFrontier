// tailor: data { shop: {id,label,region_id,size}, tier, rows: [{id,label,kind,sex,price,min_tier,owned}], notice?, notice_kind? }
// (shaped like fh_tailor getStock). Each row shows label, kind, price, min tier. Owned rows say "Owned" and cannot be
// bought; rows above the player's tier are greyed with "Needs tier N" and cannot be bought. The server decides every buy
// (price, tier, owned, stock): the client only sends the entry id. A notice-only update keeps the rows.
// Actions: buy { entry_id }, close {}. No autofocus, Enter does nothing.
// Mirror preview (client-local, never sent to the server): Preview on an outfit row tries that outfit on you; Preview on an
// item row layers it over the last previewed outfit. Stop preview / Close / Esc put your own look back (fh_tailor reverts
// on every close path). A look the client cannot show comes back as a notice.
FH_UI.register('tailor', {
  last: null, pOutfit: null,
  open: function (el, data) { this.last = null; this.pOutfit = null; this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM, self = this; data = data || {};
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
      const row = D.h('div', locked ? 'row card disabled' : 'row card');
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', r.label || r.id));
      info.appendChild(D.h('div', '', (r.kind === 'outfit' ? 'Outfit' : 'Item') + ' · $' + r.price));
      if (r.owned) info.appendChild(D.h('div', 'note ok', 'Owned'));
      else if (locked) info.appendChild(D.h('div', 'note muted', 'Needs tier ' + r.min_tier));
      row.appendChild(info);
      const isOutfit = r.kind === 'outfit';
      const pv = D.btn('Preview', function () {
        if (isOutfit) { self.pOutfit = String(r.id); FH_UI.preview('tailor', { outfit: self.pOutfit, items: [] }); self.update(el, {}); } // re-render: item Preview buttons unlock
        else FH_UI.preview('tailor', { outfit: self.pOutfit, items: [String(r.id)] });
      });
      if (!isOutfit && !self.pOutfit) { pv.disabled = true; pv.title = 'Preview an outfit first'; }
      row.appendChild(pv);
      const b = D.btn(r.owned ? 'Owned' : 'Buy', function () { FH_UI.action('tailor', 'buy', { entry_id: String(r.id) }); });
      if (r.owned || locked) b.disabled = true;
      row.appendChild(b);
      body.appendChild(row);
    });
    p.appendChild(body);
    p.appendChild(D.btn('Stop preview', function () { self.pOutfit = null; FH_UI.previewEnd('tailor'); self.update(el, {}); }));
    p.appendChild(D.btn('Close', function () { FH_UI.close('tailor'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; this.pOutfit = null; FH_DOM.clear(el); },
});
