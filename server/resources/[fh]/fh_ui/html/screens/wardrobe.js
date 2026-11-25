// wardrobe: data { owned: [{id,label,kind,source}], worn?: {outfit,items}, saved: {[slot]: {label,outfit,items,valid}},
// fitted, maxItems, maxSaved, notice?, notice_kind? } (shaped like fh_tailor getWardrobe). Pick one owned outfit and up to
// maxItems single items (client-side cap; the server decides), then Wear it or Save it to a slot. Saved slots 1..maxSaved
// show their look; Wear applies a saved slot. `saved` may arrive as an array or as an object keyed by slot (sparse Lua table).
// Actions: equip { outfit_id, item_ids }, save { slot, label?, outfit_id, item_ids }, wear { slot }, close {}.
// A notice-only update keeps the lists. No autofocus, Enter does nothing.
FH_UI.register('wardrobe', {
  last: null, outfit: null, items: [], label: '',
  open: function (el, data) {
    this.last = null; this.outfit = null; this.items = []; this.label = '';
    this.update(el, data);
  },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    if (data.owned === undefined) {
      if (this.last) data = Object.assign({}, this.last, { notice: data.notice, notice_kind: data.notice_kind });
    } else {
      data = Object.assign({}, data, { owned: D.asList(data.owned) });
      if (!this.last) { // first data: start the selection from the worn look
        const w = data.worn || {};
        this.outfit = w.outfit || null; this.items = D.asList(w.items).slice();
      }
      this.last = data;
    }
    const ids = {}; D.asList(data.owned).forEach(function (o) { ids[o.id] = true; });
    if (this.outfit && !ids[this.outfit]) this.outfit = null;
    this.items = this.items.filter(function (i) { return ids[i]; });
    this.render(el, data);
  },
  slotOf: function (saved, n) { // saved can be an array (slots 1..k, no gaps) or an object keyed by slot
    if (Array.isArray(saved)) return saved[n - 1] || null;
    return (saved && (saved[n] || saved[String(n)])) || null;
  },
  render: function (el, data) {
    const D = FH_DOM, self = this;
    const owned = D.asList(data.owned);
    const labelOf = {}; owned.forEach(function (o) { labelOf[o.id] = o.label || o.id; });
    const nameOf = function (id) { return labelOf[id] || String(id); };
    const maxItems = Number(data.maxItems) || 0, maxSaved = Number(data.maxSaved) || 0;
    function lookText(outfit, items) {
      const parts = [outfit ? nameOf(outfit) : 'No outfit'];
      D.asList(items).forEach(function (i) { parts.push(nameOf(i)); });
      return parts.join(' + ');
    }
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', 'Wardrobe'));
    if (data.notice) p.appendChild(D.h('p', 'note ' + (data.notice_kind === 'ok' ? 'ok' : 'err'), String(data.notice)));
    const body = D.h('div', 'body');
    const w = data.worn;
    body.appendChild(D.h('p', 'note', 'Wearing: ' + (w ? lookText(w.outfit, w.items) : 'nothing chosen yet')));

    body.appendChild(D.h('h2', 'sub', 'Outfits'));
    const outfits = owned.filter(function (o) { return o.kind === 'outfit'; });
    if (!outfits.length) body.appendChild(D.h('p', 'note', 'You own no outfits.'));
    outfits.forEach(function (o) {
      const row = D.h('div', 'row card');
      const on = self.outfit === o.id;
      row.appendChild(D.h('strong', 'grow', (on ? '● ' : '○ ') + (o.label || o.id)));
      row.appendChild(D.btn(on ? 'Selected' : 'Select', function () { self.outfit = o.id; self.render(el, data); }));
      body.appendChild(row);
    });

    body.appendChild(D.h('h2', 'sub', 'Items (up to ' + maxItems + ')'));
    const items = owned.filter(function (o) { return o.kind === 'item'; });
    if (!items.length) body.appendChild(D.h('p', 'note', 'You own no single items.'));
    items.forEach(function (o) {
      const row = D.h('div', 'row card');
      const on = self.items.indexOf(o.id) >= 0;
      row.appendChild(D.h('strong', 'grow', (on ? '☑ ' : '☐ ') + (o.label || o.id)));
      const b = D.btn(on ? 'Remove' : 'Add', function () {
        if (on) self.items = self.items.filter(function (i) { return i !== o.id; });
        else if (self.items.length < maxItems) self.items.push(o.id);
        self.render(el, data);
      });
      if (!on && self.items.length >= maxItems) b.disabled = true;
      row.appendChild(b);
      body.appendChild(row);
    });

    const picked = D.h('div', 'row card');
    picked.appendChild(D.h('div', 'grow', 'Selected look: ' + lookText(this.outfit, this.items)));
    const wear = D.btn('Wear', function () {
      FH_UI.action('wardrobe', 'equip', { outfit_id: String(self.outfit), item_ids: self.items.slice() });
    });
    if (!this.outfit) wear.disabled = true;
    picked.appendChild(wear);
    body.appendChild(picked);

    body.appendChild(D.h('h2', 'sub', 'Saved outfits'));
    const name = document.createElement('input');
    name.type = 'text'; name.maxLength = 32; name.placeholder = 'Name (optional)'; name.value = this.label;
    name.oninput = function () { self.label = name.value; };
    body.appendChild(name);
    for (let n = 1; n <= maxSaved; n++) {
      const s = this.slotOf(data.saved, n);
      const row = D.h('div', 'row card');
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', 'Slot ' + n + (s && s.label ? ': ' + s.label : '')));
      if (!s) info.appendChild(D.h('div', 'note muted', 'Empty'));
      else {
        info.appendChild(D.h('div', '', lookText(s.outfit, s.items)));
        if (s.valid === false) info.appendChild(D.h('div', 'note err', 'Some pieces are no longer owned'));
      }
      row.appendChild(info);
      const wb = D.btn('Wear', (function (slot) { return function () { FH_UI.action('wardrobe', 'wear', { slot: slot }); }; })(n));
      if (!s || s.valid === false) wb.disabled = true;
      row.appendChild(wb);
      const sb = D.btn('Save here', (function (slot) { return function () {
        const pl = { slot: slot, outfit_id: String(self.outfit), item_ids: self.items.slice() };
        const t = (self.label || '').trim();
        if (t) pl.label = t;
        FH_UI.action('wardrobe', 'save', pl);
      }; })(n));
      if (!this.outfit) sb.disabled = true;
      row.appendChild(sb);
      body.appendChild(row);
    }
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('wardrobe'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; this.outfit = null; this.items = []; this.label = ''; FH_DOM.clear(el); },
});
