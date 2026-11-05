// Visar påminnelserna från servern, också när appen är stängd.
self.addEventListener('push', (event) => {
  const { title, body } = event.data.json();
  event.waitUntil(self.registration.showNotification(title, { body, icon: 'icon-180.png' }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const [open] = await self.clients.matchAll({ type: 'window' });
    return open ? open.focus() : self.clients.openWindow('./');
  })());
});
