// Passive buff HUD (corner). data: { rows: [{ id, label, magnitude?, remaining? }] }, remaining in seconds at push time.
(function () {
  const w = FH_HUD.make('Buffs', 'hud-buffs', function (r, left, fmt) {
    return [['hud-name', r.label || r.id], ['hud-time', left === null ? '--' : fmt(left)]];
  });
  FH_UI.register('buffs', { open: w.open, update: w.open, close: w.close });
})();
