// jobs board: data { region_id, expires_at, expired?, notice?, notice_kind?, offers: [{id,job_type,title,text,rewards,accepted}] }.
// An update without `offers` only changes the inline notice. Actions: accept { id }, close {}. No autofocus; Enter does nothing.
FH_UI.register('jobs', {
  last: null,
  open: function (el, data) { this.last = null; this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    if (data.offers === undefined && this.last) {
      data = Object.assign({}, this.last, { notice: data.notice, notice_kind: data.notice_kind });
    } else {
      this.last = data;
    }
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', 'Jobs Board' + (data.region_id ? ' - ' + data.region_id : '')));
    if (data.notice) p.appendChild(D.h('p', 'note ' + (data.notice_kind === 'ok' ? 'ok' : 'err'), data.notice));
    const body = D.h('div', 'body');
    const rows = data.expired ? [] : D.asList(data.offers);
    if (data.expired) body.appendChild(D.h('p', 'note', 'The board is being restocked.'));
    else if (!rows.length) body.appendChild(D.h('p', 'note', 'No jobs posted.'));
    rows.forEach(function (o) {
      const row = D.h('div', 'row card');
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', o.title));
      if (o.text) info.appendChild(D.h('div', '', o.text));
      info.appendChild(D.h('div', '', 'Reward: ' + rewardText(o.rewards)));
      row.appendChild(info);
      if (o.accepted) row.appendChild(D.h('span', 'rare', 'Accepted'));
      else row.appendChild(D.btn('Accept', function () { FH_UI.action('jobs', 'accept', { id: String(o.id) }); }));
      body.appendChild(row);
    });
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('jobs'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; FH_DOM.clear(el); },
});

function rewardText(r) {
  r = r || {};
  const bits = [];
  if (typeof r.money === 'number') bits.push('$' + r.money);
  if (r.rep && typeof r.rep.delta === 'number') bits.push((r.rep.delta >= 0 ? '+' : '') + r.rep.delta + ' rep');
  FH_DOM.asList(r.items).forEach(function (i) { bits.push(i.amount + '× ' + i.name); });
  return bits.join(', ') || '-';
}
