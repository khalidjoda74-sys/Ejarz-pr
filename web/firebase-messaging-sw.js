importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAUjs8uZvCoj2FnbLGGDBpdnhM3URXYSDg',
  authDomain: 'majalisna-discussions-20260629.firebaseapp.com',
  projectId: 'majalisna-discussions-20260629',
  storageBucket: 'majalisna-discussions-20260629.firebasestorage.app',
  messagingSenderId: '163358763366',
  appId: '1:163358763366:web:f8e565cc5504a3ca7580a7',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || payload.data?.title || 'Forsa Pro';
  const options = {
    body: payload.notification?.body || payload.data?.body || '',
    icon: '/icons/Icon-192.png',
    data: payload.data || {},
  };

  self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const targetRoute = data.targetRoute || '/main';
  const url = `/#${targetRoute}`;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.navigate(url);
          return client.focus();
        }
      }

      if (clients.openWindow) {
        return clients.openWindow(url);
      }

      return undefined;
    }),
  );
});
