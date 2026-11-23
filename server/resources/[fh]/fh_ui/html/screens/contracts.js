// contracts: data { title?, region?, contracts: [{id,cargo,origin,destination,pay,deadline_minutes,risk}] }.
// Actions: accept { id }, close {} (Esc / Close button).
FH_UI.register('contracts', {
  open: function (el, data) { this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', (data.title || 'Contract Board') + (data.region ? ' - ' + data.region : '')));
    const body = D.h('div', 'body');
    const rows = data.contracts || [];
    if (!rows.length) body.appendChild(D.h('p', 'note', 'No contracts posted.'));
    rows.forEach(function (c) {
      const row = D.h('div', 'row card');
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', c.cargo));
      info.appendChild(D.h('div', '', c.origin + ' → ' + c.destination));
      info.appendChild(D.h('div', '', '$' + c.pay + '  |  ' + c.deadline_minutes + ' min  |  risk: ' + c.risk));
      row.appendChild(info);
      row.appendChild(D.btn('Accept', function () { FH_UI.action('contracts', 'accept', { id: String(c.id) }); }));
      body.appendChild(row);
    });
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('contracts'); }));
    el.appendChild(p);
    const first = p.querySelector('button'); if (first) first.focus();
  },
  close: function (el) { FH_DOM.clear(el); },
});
