// heat (passive HUD): data { factions: [{id,label,level 0-100,tier}], lay_low: {active, seconds_left?} }. fh_heat re-sends via fh:ui:update on fh:heat:changed and player load.
const HEAT_MAX_ROWS = 3; // fits the 26vh card; the HUD cannot scroll (pointer-events none)
// Pure: stable sort by level descending, split into shown rows and hidden count.
function heatTopRows(factions, max) {
  const rows = FH_DOM.asList(factions).map(function (f, i) { return { f: f, i: i, l: Number(f && f.level) || 0 }; });
  rows.sort(function (a, b) { return (b.l - a.l) || (a.i - b.i); });
  return { shown: rows.slice(0, max).map(function (r) { return r.f; }), hidden: Math.max(0, rows.length - max) };
}
FH_UI.register('heat', {
  open: function (el, data) { this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM;
    D.clear(el);
    const factions = D.asList(data && data.factions);
    const any = factions.some(function (f) { return (Number(f && f.level) || 0) > 0; });
    const box = D.h('div', 'hud hud-heat');
    box.hidden = !any; // hide when every faction level is 0 (or the list is empty); .hud is pointer-events none
    box.appendChild(D.h('h2', 'title small', 'Heat'));
    const body = D.h('div', 'body');
    const top = heatTopRows(factions, HEAT_MAX_ROWS);
    top.shown.forEach(function (f) {
      const lvl = Math.max(0, Math.min(100, Number(f.level) || 0));
      const row = D.h('div', 'row');
      row.appendChild(D.h('span', 'grow', f.label || f.id));
      row.appendChild(D.h('span', 'tier', (f.tier || '') + ' ' + lvl));
      const bar = D.h('div', 'bar'); const fill = D.h('div', 'fill');
      fill.style.width = lvl + '%'; bar.appendChild(fill); row.appendChild(bar);
      body.appendChild(row);
    });
    if (top.hidden > 0) body.appendChild(D.h('div', 'note muted', '+' + top.hidden + ' more'));
    const ll = data && data.lay_low;
    if (ll && ll.active) {
      const s = Number(ll.seconds_left);
      body.appendChild(D.h('div', 'note', 'Laying low' + (s > 0 ? ' (' + Math.floor(s / 60) + 'm ' + (s % 60) + 's left)' : '')));
    }
    box.appendChild(body); el.appendChild(box);
  },
  close: function (el) { FH_DOM.clear(el); },
});
