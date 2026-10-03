/* Firebase web configuration is public; access is enforced by Firebase rules. */
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.stopImmediatePropagation();
  const payload = event.notification.data?.FCM_MSG?.data || {};
  const url = new URL('/', self.location.origin);
  url.searchParams.set('notifications', '1');
  for (const name of ['notificationId', 'contractId']) {
    if (typeof payload[name] === 'string' && /^[\w-]{1,160}$/.test(payload[name])) {
      url.searchParams.set(name, payload[name]);
    }
  }
  event.waitUntil(self.clients.openWindow(url.href));
});
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');
firebase.initializeApp({
  apiKey: 'AIzaSyD2kc2MfwJ7X3BRzpNf-BMwHvIBDmWHsdY',
  appId: '1:475770424762:web:a767f1b067c33af85ea183',
  messagingSenderId: '475770424762',
  projectId: 'ejarz-pro-20260624',
  authDomain: 'ejarz-pro-20260624.firebaseapp.com',
});
firebase.messaging();
