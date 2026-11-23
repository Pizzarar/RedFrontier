// heat (passive HUD): data { factions: [{id,label,level 0-100,tier}], lay_low: {active, seconds_left?} }. Future event fh:heat:changed.
FH_UI.register('heat', {
  open: function (el, data) { this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM;
    D.clear(el);
    const box = D.h('div', 'hud hud-heat');
    box.appendChild(D.h('h2', 'title small', 'Heat'));
    const body = D.h('div', 'body');
    FH_DOM.asList(data && data.factions).forEach(function (f) {
      const lvl = Math.max(0, Math.min(100, Number(f.level) || 0));
      const row = D.h('div', 'row');
      row.appendChild(D.h('span', 'grow', f.label || f.id));
      row.appendChild(D.h('span', 'tier', (f.tier || '') + ' ' + lvl));
      const bar = D.h('div', 'bar'); const fill = D.h('div', 'fill');
      fill.style.width = lvl + '%'; bar.appendChild(fill); row.appendChild(bar);
      body.appendChild(row);
    });
    const ll = data && data.lay_low;
    if (ll && ll.active) {
      const s = Number(ll.seconds_left);
      body.appendChild(D.h('div', 'note', 'Laying low' + (s > 0 ? ' (' + Math.floor(s / 60) + 'm ' + (s % 60) + 's left)' : '')));
    }
    box.appendChild(body); el.appendChild(box);
  },
  close: function (el) { FH_DOM.clear(el); },
});
