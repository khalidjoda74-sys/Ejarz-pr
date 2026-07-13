import {HttpsError} from "firebase-functions/v2/https";

const blockedTerms = [
  "احتيال مضمون",
  "ارسل الرقم السري",
  "تحويل خارج التطبيق",
  "خطاب كراهية",
  "تهديد بالقتل",
  "محتوى اباحي",
  "ترويج مخدرات",
  "انتحال شخصية",
];

const normalize = (value: string): string => value
  .toLowerCase()
  .replace(/[\u064B-\u065F\u0670\u0640]/g, "")
  .replace(/[^\u0600-\u06FFa-z0-9 ]/g, " ")
  .replace(/\s+/g, " ")
  .trim();

export const assertAllowedContent = (...values: string[]): void => {
  for (const value of values) {
    const text = normalize(value);
    if (blockedTerms.some((term) => text.includes(term))) {
      throw new HttpsError(
        "invalid-argument",
        "يتضمن النص محتوى غير مسموح. عدّل النص ثم حاول مرة أخرى.",
      );
    }
  }
};