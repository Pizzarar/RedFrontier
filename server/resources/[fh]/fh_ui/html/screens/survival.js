// Survival needs (passive HUD, idea-854). data: { level: 0..3, rows: [{ id, label }] }. A "Sluggish N/3" header
// is shown when level > 0, then one short label per missing need ("Hungry", "Thirsty", "Tired", "Dirty", "Cold").
// The widget hides when level is 0 and nothing is missing. No actions, never takes focus.
(function () {
  FH_UI.register('survival', {
    open: function (el, data) { this.update(el, data); },
    update: function (el, data) {
      const D = FH_DOM;
      D.clear(el);
      const level = Math.max(0, Math.min(3, Math.floor(Number(data && data.level) || 0)));
      const rows = (data && Array.isArray(data.rows)) ? data.rows : [];
      const show = level > 0 || rows.length > 0;
      const box = D.h('div', 'hud hud-survival');
      box.hidden = !show;
      if (level > 0) box.appendChild(D.h('h2', 'hud-title', 'Sluggish ' + level + '/3'));
      if (rows.length > 0) {
        const list = D.h('ul', 'hud-rows');
        rows.forEach(function (r) {
          const li = D.h('li');
          li.appendChild(D.h('span', 'hud-name', (r && r.label) || (r && r.id) || '?'));
          list.appendChild(li);
        });
        box.appendChild(list);
      }
      el.appendChild(box);
    },
    close: function (el) { FH_DOM.clear(el); },
  });
})();
