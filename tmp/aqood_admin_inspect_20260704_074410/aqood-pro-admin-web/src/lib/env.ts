export const env = {
  firebase: {
    apiKey: import.meta.env.VITE_FIREBASE_API_KEY ?? '',
    authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN ?? '',
    projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID ?? 'ejarz-pro-20260624',
    storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET ?? '',
    messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID ?? '',
    appId: import.meta.env.VITE_FIREBASE_APP_ID ?? '',
  },
};

export function isFirebaseConfigured() {
  const cfg = env.firebase;
  return Boolean(cfg.apiKey && cfg.authDomain && cfg.projectId && cfg.storageBucket && cfg.appId);
}

export function missingFirebaseKeys() {
  return Object.entries(env.firebase)
    .filter(([, value]) => !value)
    .map(([key]) => key);
}
