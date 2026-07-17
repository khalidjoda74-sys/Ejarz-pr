import { getDownloadURL, ref, uploadBytesResumable } from 'firebase/storage';
import { storage } from '@/lib/firebase';

export async function uploadFinalPdf(contractId: string, file: File, onProgress?: (progress: number) => void) {
  if (file.type !== 'application/pdf' && !file.name.toLowerCase().endsWith('.pdf')) {
    throw new Error('الملف يجب أن يكون PDF');
  }
  const safeName = file.name.replace(/[^\w.\-\u0600-\u06FF]+/g, '_');
  const path = `contracts/${contractId}/final/${Date.now()}_${safeName}`;
  const fileRef = ref(storage, path);
  const task = uploadBytesResumable(fileRef, file, { contentType: 'application/pdf' });
  return new Promise<{ url: string; path: string; name: string }>((resolve, reject) => {
    task.on('state_changed',
      (snapshot) => {
        const progress = Math.round((snapshot.bytesTransferred / snapshot.totalBytes) * 100);
        onProgress?.(progress);
      },
      reject,
      async () => {
        const url = await getDownloadURL(task.snapshot.ref);
        resolve({ url, path, name: file.name });
      },
    );
  });
}
