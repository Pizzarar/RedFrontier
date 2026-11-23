// U1 smoke screen: proves the router. Open with TriggerClientEvent('fh:ui:open', src, { screen = 'placeholder', data = { text = '...' } }).
FH_UI.register('placeholder', {
  open: function (el, data) {
    el.innerHTML = '<div class="panel"><h1 class="title">Frontier Homestead</h1><p class="body"></p>' +
      '<button type="button" class="btn ping">Ping</button> <button type="button" class="btn close">Close</button></div>';
    el.querySelector('.ping').onclick = function () { FH_UI.action('placeholder', 'ping', { t: 1 }); };
    el.querySelector('.close').onclick = function () { FH_UI.close('placeholder'); };
    this.update(el, data);
  },
  update: function (el, data) {
    const p = el.querySelector('.body');
    if (p) p.textContent = (data && data.text) || 'It works.';
  },
  close: function (el) { el.innerHTML = ''; },
});
