// Shared helper for passive HUD widgets (buffs, bags): renders rows, counts `remaining` down once a second from the
// moment a push arrived (numbers change, nothing animates), and hides the widget when there are no rows.
window.FH_HUD = (function () {
  function fmt(sec) {
    if (typeof sec !== 'number' || !isFinite(sec)) return '--';
    sec = Math.max(0, Math.floor(sec));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    const pad = function (n) { return (n < 10 ? '0' : '') + n; };
    return h > 0 ? h + ':' + pad(m) + ':' + pad(s) : m + ':' + pad(s);
  }
  // build(row) -> { text: string } parts via cells(row): array of [className, text]; the 'time' cell is live.
  function make(title, cls, cells) {
    let rows = [], at = 0, timer = null, host = null;
    function draw() {
      if (!host) return;
      const dt = (Date.now() - at) / 1000;
      host.hidden = rows.length === 0;
      const list = host.querySelector('.hud-rows');
      list.textContent = '';
      rows.forEach(function (r) {
        const li = document.createElement('li');
        const left = typeof r.remaining === 'number' ? r.remaining - dt : null;
        cells(r, left, fmt).forEach(function (c) {
          const sp = document.createElement('span');
          sp.className = c[0];
          sp.textContent = c[1];
          li.appendChild(sp);
        });
        list.appendChild(li);
      });
    }
    return {
      open: function (el, data) {
        if (!host) {
          el.innerHTML = '<div class="hud ' + cls + '"><h2 class="hud-title"></h2><ul class="hud-rows"></ul></div>';
          host = el.firstChild;
          host.querySelector('.hud-title').textContent = title;
        }
        rows = (data && Array.isArray(data.rows)) ? data.rows : [];
        at = Date.now();
        draw();
        if (!timer) timer = setInterval(draw, 1000);
      },
      close: function (el) {
        if (timer) { clearInterval(timer); timer = null; }
        rows = []; host = null; el.innerHTML = '';
      },
    };
  }
  return { fmt: fmt, make: make };
})();
