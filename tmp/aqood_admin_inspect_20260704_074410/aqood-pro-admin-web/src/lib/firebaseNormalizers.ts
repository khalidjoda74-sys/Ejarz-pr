export function withId<T extends Record<string, unknown>>(id: string, data: T): T & { id: string } {
  return { id, ...data };
}

export function compactObject<T extends Record<string, unknown>>(obj: T) {
  return Object.fromEntries(Object.entries(obj).filter(([, value]) => value !== undefined)) as Partial<T>;
}

export function searchMatch(record: Record<string, unknown>, query: string, keys: string[]) {
  if (!query.trim()) return true;
  const q = query.trim().toLowerCase();
  return keys.some((key) => String(record[key] ?? '').toLowerCase().includes(q));
}


export function cleanUndefined<T>(obj: T): T {
  if (Array.isArray(obj)) return obj.map((item) => cleanUndefined(item)) as T;
  if (obj && typeof obj === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
      if (value !== undefined) result[key] = cleanUndefined(value);
    }
    return result as T;
  }
  return obj;
}
