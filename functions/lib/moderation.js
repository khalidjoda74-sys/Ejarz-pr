"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.assertAllowedContent = void 0;
const https_1 = require("firebase-functions/v2/https");
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
const normalize = (value) => value
    .toLowerCase()
    .replace(/[\u064B-\u065F\u0670\u0640]/g, "")
    .replace(/[^\u0600-\u06FFa-z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
const assertAllowedContent = (...values) => {
    for (const value of values) {
        const text = normalize(value);
        if (blockedTerms.some((term) => text.includes(term))) {
            throw new https_1.HttpsError("invalid-argument", "يتضمن النص محتوى غير مسموح. عدّل النص ثم حاول مرة أخرى.");
        }
    }
};
exports.assertAllowedContent = assertAllowedContent;
//# sourceMappingURL=moderation.js.map