// wagonyard: data { post: { id, label, region }, live?: { id, tier }, tiers: [{ key, label, price, owned, locked?, reason? }],
// notice?, notice_kind? } (shaped like fh_cargo FhCargoPost.menu).
// Shows each wagon tier with label, price, and locked ("Locked (needs ...)") / owned state. Unowned unlocked rows have
// Buy; owned rows have Call (disabled while a wagon is out); footer has Stow my wagon (disabled when no wagon is out)
// and Close. A notice-only update keeps the rows. Server decides post, region, price, ownership and live state: the
// client sends only { tier } for buy/call and {} for stow/close. No autofocus, Enter does nothing.
FH_UI.register('wagonyard', {
  last: null,
  open: function (el, data) { this.last = null; this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM; data = data || {};
    if (data.tiers === undefined) { // notice-only update (e.g. walked out of range)
      if (this.last) data = Object.assign({}, this.last, { notice: data.notice, notice_kind: data.notice_kind });
    } else { // Lua empty tables arrive as {}: coerce so stale rows never survive
      data = Object.assign({}, data, { tiers: D.asList(data.tiers) });
      this.last = data;
    }
    const post = data.post || {};
    const live = (data.live && typeof data.live === 'object' && data.live.tier) ? data.live : null;
    const tiers = D.asList(data.tiers);
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', post.label || 'Wagon Yard'));
    if (data.notice) p.appendChild(D.h('p', 'note ' + (data.notice_kind === 'ok' ? 'ok' : 'err'), String(data.notice)));
    const body = D.h('div', 'body');
    if (live) {
      let liveLabel = String(live.tier);
      tiers.forEach(function (t) { if (t.key === live.tier && t.label) liveLabel = String(t.label); });
      body.appendChild(D.h('p', 'note', 'Wagon out: ' + liveLabel));
    }
    if (!tiers.length) body.appendChild(D.h('p', 'note', 'No wagons available.'));
    tiers.forEach(function (t) {
      const owned = t.owned === true;
      const locked = !owned && t.locked === true;
      const row = D.h('div', locked ? 'row card disabled' : 'row card');
      const info = D.h('div', 'grow');
      info.appendChild(D.h('strong', '', t.label || t.key));
      info.appendChild(D.h('div', '', '$' + (Number(t.price) || 0)));
      if (owned) {
        const isOut = live && live.tier === t.key;
        info.appendChild(D.h('div', 'note ok', isOut ? 'Owned · Out' : 'Owned'));
      } else if (locked) {
        const need = (t.reason === 'tier_too_low' || !t.reason || t.reason === 'fh_locked')
          ? 'higher regional standing'
          : String(t.reason);
        info.appendChild(D.h('div', 'note muted', 'Locked (needs ' + need + ')'));
      }
      row.appendChild(info);
      if (owned) {
        const callBtn = D.btn('Call', function () { FH_UI.action('wagonyard', 'call', { tier: String(t.key) }); });
        if (live) callBtn.disabled = true;
        row.appendChild(callBtn);
      } else {
        const buyBtn = D.btn('Buy', function () { FH_UI.action('wagonyard', 'buy', { tier: String(t.key) }); });
        if (locked) buyBtn.disabled = true;
        row.appendChild(buyBtn);
      }
      body.appendChild(row);
    });
    p.appendChild(body);
    const stowBtn = D.btn('Stow my wagon', function () { FH_UI.action('wagonyard', 'stow', {}); });
    if (!live) stowBtn.disabled = true;
    p.appendChild(stowBtn);
    p.appendChild(D.btn('Close', function () { FH_UI.close('wagonyard'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; FH_DOM.clear(el); },
});
