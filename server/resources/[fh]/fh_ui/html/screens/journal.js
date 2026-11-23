// quest journal: data { entries: [{quest_id,kind,title,giver?,region_id?,status,step,steps_total,step_text,count,need,rewards,
// cooldown_until?,updated_at}], notice?, notice_kind? }. An update without `entries` only changes the inline notice.
// Actions: abandon { id } (two clicks: Abandon, then Confirm), close {}. No autofocus; Enter does nothing.
FH_UI.register('journal', {
  last: null,
  confirm: null, // quest_id awaiting the second click
  open: function (el, data) { this.last = null; this.confirm = null; this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM, self = this; data = data || {};
    if (data.entries === undefined && this.last) {
      data = Object.assign({}, this.last, { notice: data.notice, notice_kind: data.notice_kind });
    } else {
      this.last = data;
    }
    this.confirm = null;
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', 'Journal'));
    if (data.notice) p.appendChild(D.h('p', 'note ' + (data.notice_kind === 'ok' ? 'ok' : 'err'), data.notice));
    const body = D.h('div', 'body');
    const rows = D.asList(data.entries);
    if (!rows.length) body.appendChild(D.h('p', 'note', 'Nothing in your journal yet.'));
    rows.forEach(function (e) {
      const row = D.h('div', 'row card');
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', e.title));
      info.appendChild(D.h('div', '', journalStatus(e.status) + (e.giver ? '  |  ' + e.giver : '') + (e.region_id ? '  |  ' + e.region_id : '')));
      if (e.status === 'active') {
        if (e.step_text) info.appendChild(D.h('div', '', journalProgress(e) + e.step_text));
        info.appendChild(D.h('div', '', 'Reward: ' + journalRewards(e.rewards)));
      }
      row.appendChild(info);
      if (e.status === 'active') {
        const b = D.btn('Abandon', function () {
          if (self.confirm !== e.quest_id) {
            self.confirm = e.quest_id;
            b.textContent = 'Confirm abandon?';
            return;
          }
          self.confirm = null;
          FH_UI.action('journal', 'abandon', { id: String(e.quest_id) });
        });
        row.appendChild(b);
      }
      body.appendChild(row);
    });
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('journal'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; this.confirm = null; FH_DOM.clear(el); },
});

function journalStatus(s) {
  return { active: 'Active', done: 'Done', failed: 'Failed', abandoned: 'Abandoned' }[s] || String(s || '');
}

function journalProgress(e) {
  let t = '';
  if (typeof e.step === 'number' && typeof e.steps_total === 'number' && e.steps_total > 1) t += 'Step ' + e.step + '/' + e.steps_total + ': ';
  if (typeof e.count === 'number' && typeof e.need === 'number' && e.need > 1) t += '(' + e.count + '/' + e.need + ') ';
  return t;
}

function journalRewards(r) {
  r = r || {};
  const bits = [];
  if (typeof r.money === 'number') bits.push('$' + r.money);
  if (r.rep && typeof r.rep.delta === 'number') bits.push((r.rep.delta >= 0 ? '+' : '') + r.rep.delta + ' rep');
  FH_DOM.asList(r.items).forEach(function (i) { bits.push(i.amount + '× ' + i.name); });
  return bits.join(', ') || '-';
}
