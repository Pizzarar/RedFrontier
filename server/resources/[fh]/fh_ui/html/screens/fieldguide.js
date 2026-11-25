// field guide (help pages, read-only): data { entries: [{id,title,lines:[string],controls:[string],wiki_path}], selected? }.
// Left list of entry titles; right pane shows the selected entry (default `selected`, else the first): lines as
// paragraphs, controls as a small key list, and a muted "Wiki: <wiki_path>" footer as plain text (not a link).
// Clicking a title switches the pane client-side (no round trip). Only action: close {}. No autofocus; Enter does nothing.
FH_UI.register('fieldguide', {
  last: null,
  selected: null, // id of the entry currently shown in the right pane
  open: function (el, data) { this.last = data || {}; this.selected = this.pick(this.last, null); this.render(el); },
  update: function (el, data) {
    data = data || {};
    if (data.entries === undefined) data = Object.assign({}, this.last, data); // selected-only update keeps entries
    this.last = data;
    this.selected = this.pick(data, this.selected);
    this.render(el);
  },
  pick: function (data, keep) {
    const ids = FH_DOM.asList(data && data.entries).map(function (e) { return e ? String(e.id) : ''; });
    if (data && data.selected != null && ids.indexOf(String(data.selected)) >= 0) return String(data.selected);
    if (keep != null && ids.indexOf(keep) >= 0) return keep;
    return ids[0] || null;
  },
  render: function (el) {
    const D = FH_DOM, self = this;
    const data = this.last || {};
    const entries = D.asList(data.entries);
    const sel = this.selected;
    D.clear(el);
    const p = D.h('div', 'panel wide');
    p.appendChild(D.h('h1', 'title', 'Field Guide'));
    if (!entries.length) {
      const body = D.h('div', 'body');
      body.appendChild(D.h('p', 'note', 'The field guide is empty.'));
      p.appendChild(body);
      p.appendChild(D.btn('Close', function () { FH_UI.close('fieldguide'); }));
      el.appendChild(p);
      return;
    }
    const body = D.h('div', 'body');
    body.style.display = 'flex'; body.style.gap = '14px'; body.style.alignItems = 'flex-start';
    const list = D.h('div', 'guide-list');
    list.style.flex = '0 0 240px'; list.style.borderRight = '2px solid var(--edge)'; list.style.paddingRight = '12px';
    entries.forEach(function (e) {
      const b = D.btn(e.title || String(e.id), function () { self.selected = String(e.id); self.render(el); });
      b.style.display = 'block'; b.style.width = '100%'; b.style.margin = '0 0 8px 0'; b.style.textAlign = 'left';
      if (String(e.id) === sel) { b.style.background = '#f6e6bd'; b.style.outline = '2px solid var(--sepia-a)'; }
      list.appendChild(b);
    });
    let entry = null;
    for (let i = 0; i < entries.length; i++) {
      if (String(entries[i] && entries[i].id) === sel) { entry = entries[i]; break; }
    }
    if (!entry) entry = entries[0];
    const pane = D.h('div', 'guide-pane');
    pane.style.flex = '1 1 auto'; pane.style.minWidth = '0';
    pane.appendChild(D.h('h2', 'sub', entry.title || String(entry.id)));
    D.asList(entry.lines).forEach(function (line) { pane.appendChild(D.h('p', '', line)); });
    const controls = D.asList(entry.controls);
    if (controls.length) {
      pane.appendChild(D.h('h3', 'sub', 'Controls'));
      const keys = D.h('div', 'keys');
      controls.forEach(function (c) {
        const k = D.h('span', 'key', c);
        k.style.display = 'inline-block'; k.style.margin = '0 6px 4px 0'; k.style.padding = '1px 8px';
        k.style.border = '1px solid var(--edge)'; k.style.background = '#fffaf0'; k.style.fontSize = '13px';
        keys.appendChild(k);
      });
      pane.appendChild(keys);
    }
    if (entry.wiki_path) pane.appendChild(D.h('p', 'note muted', 'Wiki: ' + entry.wiki_path));
    body.appendChild(list); body.appendChild(pane);
    p.appendChild(body);
    p.appendChild(D.btn('Close', function () { FH_UI.close('fieldguide'); }));
    el.appendChild(p);
  },
  close: function (el) { this.last = null; this.selected = null; FH_DOM.clear(el); },
});
