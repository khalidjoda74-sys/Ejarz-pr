import {
  QueryConstraint,
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  serverTimestamp,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';

export async function listCollection<T extends { id: string }>(path: string, constraints: QueryConstraint[] = []) {
  const ref = collection(db, path);
  const q = query(ref, ...constraints);
  const snap = await getDocs(q);
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Record<string, unknown>) }) as T);
}

export async function listRecent<T extends { id: string }>(path: string, count = 25, orderField = 'createdAt') {
  return listCollection<T>(path, [orderBy(orderField, 'desc'), limit(count)]);
}

export async function getDocument<T extends { id: string }>(path: string, id: string) {
  const snap = await getDoc(doc(db, path, id));
  if (!snap.exists()) return null;
  return { id: snap.id, ...(snap.data() as Record<string, unknown>) } as T;
}

export async function patchDocument(path: string, id: string, values: Record<string, unknown>) {
  await updateDoc(doc(db, path, id), {
    ...values,
    updatedAt: serverTimestamp(),
  });
}

export async function upsertDocument(path: string, id: string, values: Record<string, unknown>) {
  await setDoc(doc(db, path, id), {
    ...values,
    updatedAt: serverTimestamp(),
  }, { merge: true });
}
