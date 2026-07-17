import { collection, getDocs, limit, orderBy, query } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { Property } from '@/types/property';
import { Contract } from '@/types/contract';
import { getDocument, listCollection } from './baseService';

export async function listProperties(count = 120) {
  const snap = await getDocs(query(collection(db, 'properties'), orderBy('createdAt', 'desc'), limit(count)));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }) as Property);
}

export async function getProperty(propertyId: string) {
  return getDocument<Property>('properties', propertyId);
}

export async function listPropertyContracts(propertyId: string) {
  const all = await listCollection<Contract>('contracts', [limit(120)]);
  return all.filter((contract) => {
    const property = contract.property as Record<string, unknown> | undefined;
    return property?.id === propertyId || property?.propertyId === propertyId || contract.propertyId === propertyId;
  });
}
