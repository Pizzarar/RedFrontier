// insurance (dialog): data { title, fee, delay_minutes, target_chest, note? }. Actions: confirm {}, cancel {}; Esc -> close.
(function () {
  let stopEnter = null;
  FH_UI.register('insurance', {
    open: function (el, data) {
      const D = FH_DOM; data = data || {};
      D.clear(el);
      const p = D.h('div', 'panel');
      p.appendChild(D.h('h1', 'title', data.title || 'Insurance'));
      const body = D.h('div', 'body');
      body.appendChild(D.h('p', '', 'Fee: $' + data.fee));
      body.appendChild(D.h('p', '', 'Delivered ' + data.delay_minutes + ' minutes after death'));
      body.appendChild(D.h('p', '', 'To: ' + data.target_chest));
      if (data.note) body.appendChild(D.h('p', 'note', data.note));
      p.appendChild(body);
      const confirm = D.btn('Confirm (Enter)', function () { FH_UI.action('insurance', 'confirm', {}); });
      const cancel = D.btn('Cancel', function () { FH_UI.action('insurance', 'cancel', {}); FH_UI.close('insurance'); });
      p.appendChild(confirm); p.appendChild(cancel);
      el.appendChild(p);
      if (stopEnter) stopEnter();
      stopEnter = D.onEnter(function () { FH_UI.action('insurance', 'confirm', {}); });
      confirm.focus();
    },
    update: function (el, data) { this.open(el, data); },
    close: function (el) { if (stopEnter) { stopEnter(); stopEnter = null; } FH_DOM.clear(el); },
  });
})();
