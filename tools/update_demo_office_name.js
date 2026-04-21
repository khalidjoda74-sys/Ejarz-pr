process.env.GOOGLE_CLOUD_PROJECT = 'darvoo';
process.env.GCLOUD_PROJECT = 'darvoo';
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'darvoo' });

const admin = require('C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\node_modules\\firebase-admin');
const sa = require('C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\serviceAccountKey.json');

const DEMO_OFFICE_NAME = 'مكتب درافيو للعقارات';

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    projectId: sa.project_id,
  });
}

const db = admin.firestore();

async function main() {
  const snap = await db.collection('users')
    .where('isDemo', '==', true)
    .where('role', '==', 'office')
    .get();

  let updated = 0;

  for (const doc of snap.docs) {
    const data = doc.data() || {};

    const officeProfile = data.office_profile && typeof data.office_profile === 'object'
      ? { ...data.office_profile }
      : {};

    officeProfile.office_name = DEMO_OFFICE_NAME;
    officeProfile.updated_at = admin.firestore.FieldValue.serverTimestamp();

    await doc.ref.set({
      duration: 'demo3d',
      name: DEMO_OFFICE_NAME,
      office_profile: officeProfile,
    }, { merge: true });

    updated += 1;
    console.log(`updated demo office uid=${doc.id}`);
  }

  console.log(`done updated=${updated}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
