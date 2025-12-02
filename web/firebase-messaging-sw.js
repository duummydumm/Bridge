// Import and configure the Firebase SDK
// These scripts are made available when the app is served or deployed on Firebase Hosting
// Using compat SDK for service worker compatibility
importScripts('https://www.gstatic.com/firebasejs/11.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.1.0/firebase-messaging-compat.js');

// Initialize the Firebase app in the service worker by passing in
// your app's Firebase config object.
// https://firebase.google.com/docs/web/setup#config-object
firebase.initializeApp({
  apiKey: 'AIzaSyDJZXE43-__LaoKVmlaVqKhIFcTwd-HE_o',
  authDomain: 'bridge-72b26.firebaseapp.com',
  projectId: 'bridge-72b26',
  storageBucket: 'bridge-72b26.firebasestorage.app',
  messagingSenderId: '296102513753',
  appId: '1:296102513753:web:d36b005013ba4b2339f548',
  measurementId: 'G-LZ5WLPDM5E',
});

// Retrieve an instance of Firebase Messaging so that it can handle background
// messages.
const messaging = firebase.messaging();

// Optional: Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  // Customize notification here
  const notificationTitle = payload.notification?.title || 'New Notification';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

