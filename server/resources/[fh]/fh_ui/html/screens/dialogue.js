// giver dialogue: data { speaker, pages: [string], offer?: { quest_id, prompt, accept, decline }, notice?, notice_kind? }.
// One page at a time with Next; after the last page: the offer (accept/decline) or Goodbye when there is none.
// An update without `pages` only changes the inline notice; `offer: false` hides the offer. Actions: start { quest_id }
// (click only), close {} (decline/Goodbye/Esc). No autofocus; Enter does nothing.
FH_UI.register('dialogue', {
  last: null,
  page: 0,
  open: function (el, data) { this.last = null; this.page = 0; this.update(el, data); },
  update: function (el, data) {
    const D = FH_DOM, self = this; data = data || {};
    if (data.pages === undefined && this.last) {
      // notice-only update: keep the conversation, keep the page; offer=false drops the offer.
      const keep = Object.assign({}, this.last, { notice: data.notice, notice_kind: data.notice_kind });
      if (data.offer !== undefined) keep.offer = data.offer;
      this.last = keep;
      data = keep;
    } else {
      this.last = data; this.page = 0;
    }
    D.clear(el);
    const pages = D.asList(data.pages);
    if (this.page > pages.length) this.page = pages.length;
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', data.speaker || ''));
    if (data.notice) p.appendChild(D.h('p', 'note ' + (data.notice_kind === 'ok' ? 'ok' : 'err'), data.notice));
    const body = D.h('div', 'body');
    const atEnd = this.page >= pages.length - 1;
    if (pages.length) body.appendChild(D.h('p', '', pages[Math.min(this.page, pages.length - 1)]));
    const offer = data.offer && typeof data.offer === 'object' ? data.offer : null;
    if (pages.length && !atEnd) {
      body.appendChild(D.btn('Next', function () { self.page += 1; self.update(el, { notice: data.notice, notice_kind: data.notice_kind }); }));
    } else if (offer) {
      body.appendChild(D.h('p', '', offer.prompt || ''));
      const row = D.h('div', 'row');
      row.appendChild(D.btn(offer.accept || 'Accept', function () { FH_UI.action('dialogue', 'start', { quest_id: String(offer.quest_id) }); }));
      row.appendChild(D.btn(offer.decline || 'Decline', function () { FH_UI.close('dialogue'); }));
      body.appendChild(row);
    } else {
      body.appendChild(D.btn('Goodbye', function () { FH_UI.close('dialogue'); }));
    }
    p.appendChild(body);
    el.appendChild(p);
  },
  close: function (el) { this.last = null; this.page = 0; FH_DOM.clear(el); },
});
