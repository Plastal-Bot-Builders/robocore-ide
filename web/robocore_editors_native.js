// Bridge for the Windows app: robocore_editors.html runs in a WebView2 there instead of an iframe, so the
// app can't call window.rcEditor directly. It posts {call, args} messages; this runs them, and posts back
// {t: 'ready'} once the page has loaded and {t: 'cb', name, args} for every editor callback.
// lib/ui/editor/web_editors_native.dart adds this script to the page before it loads. In a browser
// (no window.chrome.webview) it does nothing.
(() => {
  const wv = window.chrome && window.chrome.webview;
  if (!wv) return;
  const send = (m) => wv.postMessage(m);
  const cb = (name) => (...args) => send({ t: 'cb', name, args });

  const calls = {
    'blocks.mount': (api, [options, json, tidy]) =>
      api.blocks.mount(options, json, tidy, cb('change'), cb('zoom'), cb('select'), cb('history')),
    'code.mount': (api, [options, explain]) =>
      api.code.mount(options, cb('change'), cb('cursor'), explain ? cb('explain') : null),
  };

  wv.addEventListener('message', async (e) => {
    const api = window.rcEditor;
    const { call, args = [] } = e.data || {};
    if (!api || !call) return;
    try {
      if (calls[call]) {
        await calls[call](api, args);
        send({ t: 'mounted' });
        return;
      }
      const [part, fn] = call.split('.');
      const r = api[part][fn](...args);
      if (fn === 'count') send({ t: 'count', value: r });
    } catch (err) {
      send({ t: 'error', message: String(err && err.stack || err) });
    }
  });

  window.addEventListener('load', () => {
    if (!window.rcEditor) return;
    window.rcEditor.setIdeKeys(cb('ideKey'));
    send({ t: 'ready' });
  });
})();
