// Passive own-drop-bag widget. data: { rows: [{ id, remaining?, dir?, dist? }] } (own bags only, filtered in Lua).
(function () {
  const w = FH_HUD.make('Dropped belongings', 'hud-bags', function (r, left, fmt) {
    const where = r.dir ? (r.dir === 'here' ? 'here' : r.dir + (typeof r.dist === 'number' ? ' ' + r.dist + 'm' : '')) : '';
    return [['hud-name', 'Bag' + (where ? ' (' + where + ')' : '')], ['hud-time', left === null ? '--' : fmt(left)]];
  });
  FH_UI.register('bags', { open: w.open, update: w.open, close: w.close });
})();
