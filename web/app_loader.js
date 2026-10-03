(() => {
  const panel = document.getElementById('app-loading');
  const message = document.getElementById('loading-message');
  const retry = document.getElementById('loading-retry');
  let complete = false;
  const showError = () => {
    if (complete) return;
    message.textContent = navigator.onLine
      ? 'يستغرق التحميل وقتًا أطول من المعتاد. تحقق من اتصالك ثم أعد المحاولة.'
      : 'لا يوجد اتصال بالإنترنت. اتصل بالشبكة ثم أعد المحاولة.';
    retry.hidden = false;
  };
  const timeout = setTimeout(showError, 25000);
  retry.addEventListener('click', () => location.reload());
  window.addEventListener('offline', showError);
  window.addEventListener('error', showError);
  window.addEventListener('aqdak-load-error', showError);
  window.addEventListener('flutter-first-frame', () => {
    complete = true;
    clearTimeout(timeout);
    panel.remove();
  }, {once: true});
  // Scope is separate from the app shell and does not cache user data.
  if ('serviceWorker' in navigator && window.isSecureContext) {
    navigator.serviceWorker.register('/firebase-messaging-sw.js', {
      scope: '/firebase-cloud-messaging-push-scope',
    }).catch(() => { /* Push is optional and must never block startup. */ });
  }
})();
