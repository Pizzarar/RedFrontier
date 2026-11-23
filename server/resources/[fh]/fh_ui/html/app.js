// fh_ui router. Screens register with FH_UI.register(name, { open(el, data), update(el, data), close(el) }) from
// html/screens/<name>.js (add a <script> tag in index.html). Each screen gets its own container element.
(function () {
  const screens = {};
  const root = document.getElementById('root');
  const resource = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'fh_ui';

  function post(name, body) {
    return fetch('https://' + resource + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    }).catch(function () {});
  }

  function el(name) {
    let e = document.getElementById('screen-' + name);
    if (!e) {
      e = document.createElement('section');
      e.id = 'screen-' + name;
      e.className = 'screen';
      root.appendChild(e);
    }
    return e;
  }

  function call(name, fn, data) {
    const s = screens[name];
    if (!s) { console.warn('fh_ui: no screen "' + name + '"'); return; }
    try { if (typeof s[fn] === 'function') s[fn](el(name), data); }
    catch (err) { console.error('fh_ui screen ' + name + '.' + fn, err); }
  }

  window.FH_UI = {
    register: function (name, impl) { screens[name] = impl; },
    // Server validates: action ^[a-z_]{1,32}$, payload table <= 2 KB, depth <= 4, rate limited.
    action: function (screen, action, payload) { return post('action', { screen: screen, action: action, payload: payload || {} }); },
    close: function (screen) { return post('close', { screen: screen }); },
  };

  window.addEventListener('message', function (ev) {
    const m = ev.data || {};
    if (!m.screen) return;
    if (!screens[m.screen]) { console.warn('fh_ui: no screen "' + m.screen + '"'); return; }
    if (m.type === 'open') { el(m.screen).hidden = false; call(m.screen, 'open', m.data); }
    else if (m.type === 'update') call(m.screen, 'update', m.data);
    else if (m.type === 'close') {
      call(m.screen, 'close');
      const e = document.getElementById('screen-' + m.screen);
      if (e) e.hidden = true;
    }
  });

  // Esc: ask the client to close interactive screens (it releases NUI focus).
  document.addEventListener('keydown', function (ev) {
    if (ev.key === 'Escape') post('close', {});
  });
})();
