// jobs board: data { title?, region?, jobs: [{id,kind,title,region_id,payout,risk}] }, kind = contract|bounty|hunt,
// risk = tier (low|medium|high). Rows come from the @quests lane. Actions: accept { id }, close {} (Esc / Close button).
FH_UI.register('jobs', {
  open: function (el, data) { this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', (data.title || 'Jobs Board') + (data.region ? ' - ' + data.region : '')));
    const body = D.h('div', 'body');
    const rows = D.asList(data.jobs);
    if (!rows.length) body.appendChild(D.h('p', 'note', 'No jobs posted.'));
    rows.forEach(function (j) {
      const row = D.h('div', 'row card');
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', j.title));
      info.appendChild(D.h('div', '', String(j.kind).toUpperCase() + '  |  ' + (j.region_id || '')));
      info.appendChild(D.h('div', '', '$' + j.payout + '  |  risk: ' + j.risk));
      row.appendChild(info);
      row.appendChild(D.btn('Accept', function () { FH_UI.action('jobs', 'accept', { id: String(j.id) }); }));
      body.appendChild(row);
    });
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('jobs'); }));
    el.appendChild(p);
  },
  close: function (el) { FH_DOM.clear(el); },
});
