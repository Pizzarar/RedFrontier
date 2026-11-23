// station: data { title, options: [{id,label,inputs:[{item,qty}],outputs:[{item,qty}],time_seconds,can_craft}] }.
// Actions: craft { id } (only offered when can_craft), close {}.
FH_UI.register('station', {
  open: function (el, data) { this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', data.title || 'Station'));
    const body = D.h('div', 'body');
    const opts = D.asList(data.options);
    if (!opts.length) body.appendChild(D.h('p', 'note', 'Nothing to make here.'));
    opts.forEach(function (o) {
      const row = D.h('div', 'row card' + (o.can_craft ? '' : ' disabled'));
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', o.label));
      info.appendChild(D.h('div', '', 'Needs: ' + D.list(o.inputs)));
      info.appendChild(D.h('div', '', 'Makes: ' + D.list(o.outputs) + '  |  ' + o.time_seconds + 's'));
      row.appendChild(info);
      const b = D.btn(o.can_craft ? 'Craft' : 'Missing items', function () {
        if (o.can_craft) FH_UI.action('station', 'craft', { id: String(o.id) });
      });
      b.disabled = !o.can_craft;
      row.appendChild(b);
      body.appendChild(row);
    });
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('station'); }));
    el.appendChild(p);
  },
  close: function (el) { FH_DOM.clear(el); },
});
