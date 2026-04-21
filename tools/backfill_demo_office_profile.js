process.env.GOOGLE_CLOUD_PROJECT = 'darvoo';
process.env.GCLOUD_PROJECT = 'darvoo';
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'darvoo' });

const admin = require('C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\node_modules\\firebase-admin');
const sa = require('C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    projectId: sa.project_id,
  });
}

const db = admin.firestore();
const INVALID_DEMO_LOGO_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7ZkWQAAAAASUVORK5CYII=';
const VALID_DEMO_LOGO_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY/j///9/AAn7A/0FQ0XKAAAAAElFTkSuQmCC';

function pick(data, keys) {
  for (const key of keys) {
    const value = data[key];
    if (value != null && String(value).trim() !== '') return String(value).trim();
  }
  return '';
}

async function main() {
  const snap = await db.collection('users')
    .where('isDemo', '==', true)
    .where('role', '==', 'office')
    .get();

  let updated = 0;

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const existingProfile = data.office_profile && typeof data.office_profile === 'object'
      ? { ...data.office_profile }
      : {};

    const nextProfile = {
      ...existingProfile,
      office_name: pick(existingProfile, ['office_name']) || pick(data, ['name', 'office_name']),
      work_type: pick(existingProfile, ['work_type']) || pick(data, ['work_type']),
      address: pick(existingProfile, ['address']) || pick(data, ['address', 'office_address', 'officeAddress']),
      office_address: pick(existingProfile, ['office_address']) || pick(data, ['office_address', 'address', 'officeAddress']),
      commercial_no: pick(existingProfile, ['commercial_no']) || pick(data, ['commercial_no', 'commercialNo']),
      mobile: pick(existingProfile, ['mobile']) || pick(data, ['mobile']),
      phone: pick(existingProfile, ['phone']) || pick(data, ['phone']),
      office_phone: pick(existingProfile, ['office_phone']) || pick(data, ['office_phone', 'phone']),
      tax_no: pick(existingProfile, ['tax_no']) || pick(data, ['tax_no', 'taxNo', 'vat_no', 'vatNo']),
      logo_base64: (() => {
        const current = pick(existingProfile, ['logo_base64']) || pick(data, ['logo_base64', 'logoBase64']);
        if (!current || current === INVALID_DEMO_LOGO_BASE64) {
          return VALID_DEMO_LOGO_BASE64;
        }
        return current;
      })(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };

    await doc.ref.set({
      duration: 'demo3d',
      office_profile: nextProfile,
    }, { merge: true });
    updated += 1;
    console.log(`backfilled demo office profile uid=${doc.id}`);
  }

  console.log(`done updated=${updated}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
