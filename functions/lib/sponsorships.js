"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.scheduledSyncSponsorshipCampaigns = exports.recordSponsorshipEvent = exports.createSponsorshipInterest = void 0;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const db = (0, firestore_1.getFirestore)();
const placementScopes = ["categoryMajlis", "allMajalis"];
const adPlacements = [
    "council_sponsorship",
    "home_featured_council",
    "home_banner",
];
const eventTypes = ["impression", "click"];
const cleanString = (value, fieldName, min = 1, max = 500) => {
    if (typeof value !== "string") {
        throw new https_1.HttpsError("invalid-argument", `${fieldName} غير صالح.`);
    }
    const text = value.trim();
    if (text.length < min || text.length > max) {
        throw new https_1.HttpsError("invalid-argument", `${fieldName} غير صالح.`);
    }
    return text;
};
const optionalString = (value, fieldName, max = 500) => {
    if (value == null)
        return null;
    const text = cleanString(value, fieldName, 0, max);
    return text.length === 0 ? null : text;
};
const optionalPositiveNumber = (value, fieldName) => {
    if (value == null)
        return null;
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
        throw new https_1.HttpsError("invalid-argument", `${fieldName} غير صالح.`);
    }
    return Math.round(value);
};
const cleanExternalUri = (value, fieldName) => {
    const text = cleanString(value, fieldName, 3, 1000);
    if (!/^[a-z][a-z0-9+.-]*:/i.test(text)) {
        throw new https_1.HttpsError("invalid-argument", `${fieldName} يحتاج رابطًا واضحًا.`);
    }
    return text;
};
const cleanOptionalExternalUri = (value, fieldName) => {
    const text = optionalString(value, fieldName, 1000);
    if (text == null)
        return null;
    return cleanExternalUri(text, fieldName);
};
const cleanPlacementScope = (value) => {
    const scope = cleanString(value, "نوع إعلان الراعي", 1, 30);
    if (!placementScopes.includes(scope)) {
        throw new https_1.HttpsError("invalid-argument", "نوع إعلان الراعي غير مدعوم.");
    }
    return scope;
};
const cleanAdPlacement = (value) => {
    const fallback = "council_sponsorship";
    if (value == null)
        return fallback;
    const placement = cleanString(value, "نوع الإعلان", 1, 40);
    if (!adPlacements.includes(placement)) {
        throw new https_1.HttpsError("invalid-argument", "نوع الإعلان غير مدعوم.");
    }
    return placement;
};
const cleanEventType = (value) => {
    const type = cleanString(value, "نوع حدث الرعاية", 1, 20);
    if (!eventTypes.includes(type)) {
        throw new https_1.HttpsError("invalid-argument", "نوع حدث الرعاية غير مدعوم.");
    }
    return type;
};
const scopeFromCampaignData = (value) => {
    return value === "allMajalis" ? "allMajalis" : "categoryMajlis";
};
const categoryIdFor = (value) => {
    const id = value
        .trim()
        .replace(/\s+/g, "_")
        .replace(/[^\u0600-\u06FF\w_]/g, "")
        .toLowerCase();
    return id && id !== "الكل" ? id : "all";
};
const toDate = (value) => {
    if (value instanceof firestore_1.Timestamp)
        return value.toDate();
    if (value instanceof Date)
        return value;
    return null;
};
const adPlacementFromCampaignData = (value) => {
    return adPlacements.includes(value)
        ? value
        : "council_sponsorship";
};
const slotKeyFor = (placement, scope, categoryId) => {
    const scopeKey = scope === "allMajalis" ? "allMajalis:all" : `categoryMajlis:${categoryId}`;
    return `${placement}:${scopeKey}`;
};
exports.createSponsorshipInterest = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "يجب تسجيل الدخول لإرسال طلب إعلان راعي.");
    }
    const placementScope = cleanPlacementScope(request.data?.placementScope);
    const sponsorName = cleanString(request.data?.sponsorName, "اسم الراعي", 2, 80);
    const contactName = cleanString(request.data?.contactName, "اسم المسؤول", 2, 80);
    const contactPhone = cleanString(request.data?.contactPhone, "رقم التواصل", 5, 40);
    const targetUrl = cleanExternalUri(request.data?.targetUrl, "رابط الراعي");
    const logoUrl = cleanOptionalExternalUri(request.data?.logoUrl, "رابط الشعار");
    const durationLabel = cleanString(request.data?.durationLabel, "مدة الإعلان", 2, 40);
    const notes = optionalString(request.data?.notes, "ملاحظات الطلب", 700);
    const adPlacement = cleanAdPlacement(request.data?.placement ?? request.data?.adPlacement);
    const packageId = optionalString(request.data?.packageId, "معرف الباقة", 140);
    const packageLabel = optionalString(request.data?.packageLabel, "اسم الباقة", 80);
    const priceLabel = optionalString(request.data?.priceLabel, "سعر الباقة", 80);
    const durationHours = optionalPositiveNumber(request.data?.durationHours, "مدة الباقة بالساعات");
    const councilId = optionalString(request.data?.councilId, "معرف الفرصة", 140);
    const rawCategoryName = placementScope === "allMajalis"
        ? "كل الفرص"
        : cleanString(request.data?.categoryName, "اسم الفرصة", 1, 80);
    const categoryId = placementScope === "allMajalis"
        ? "all"
        : categoryIdFor(cleanString(request.data?.categoryId, "معرف الفرصة", 1, 80));
    const requestRef = db.collection("sponsorshipRequests").doc();
    await requestRef.set({
        requesterId: uid,
        sponsorName,
        contactName,
        contactPhone,
        targetUrl,
        logoUrl,
        placementScope,
        scope: placementScope,
        placement: adPlacement,
        adPlacement,
        categoryName: rawCategoryName,
        categoryId,
        durationLabel,
        durationHours,
        packageId,
        packageLabel,
        priceLabel,
        title: sponsorName,
        description: notes,
        imageUrl: logoUrl,
        councilId,
        notes,
        packageType: "sponsorAd",
        productType: adPlacement,
        status: "pending",
        reviewStatus: "pending",
        paymentStatus: "not_requested",
        source: "app_interest_form",
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    return { requestId: requestRef.id };
});
exports.recordSponsorshipEvent = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    const campaignId = cleanString(request.data?.campaignId, "معرف الحملة", 3, 140);
    const eventType = cleanEventType(request.data?.eventType);
    const campaignRef = db.collection("sponsorships").doc(campaignId);
    const campaignSnap = await campaignRef.get();
    if (!campaignSnap.exists) {
        throw new https_1.HttpsError("not-found", "حملة الرعاية غير موجودة.");
    }
    const data = campaignSnap.data() ?? {};
    if (data.status !== "active") {
        return { recorded: false };
    }
    await campaignRef.update({
        [eventType === "click" ? "clicks" : "impressions"]: firestore_1.FieldValue.increment(1),
        [eventType === "click" ? "clicksCount" : "impressionsCount"]: firestore_1.FieldValue.increment(1),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    return { recorded: true };
});
exports.scheduledSyncSponsorshipCampaigns = (0, scheduler_1.onSchedule)({
    region: "us-central1",
    schedule: "every 15 minutes",
    timeZone: "Asia/Riyadh",
}, async () => {
    const now = firestore_1.Timestamp.now();
    const nowDate = now.toDate();
    const activeSnapshot = await db
        .collection("sponsorships")
        .where("status", "==", "active")
        .limit(80)
        .get();
    await Promise.all(activeSnapshot.docs.map(async (doc) => {
        const endsAt = toDate(doc.data().endsAt);
        if (endsAt == null || endsAt > nowDate)
            return;
        await doc.ref.update({
            status: "ended",
            endedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }));
    const freshActiveSnapshot = await db
        .collection("sponsorships")
        .where("status", "==", "active")
        .limit(80)
        .get();
    const activeSlots = new Set();
    for (const doc of freshActiveSnapshot.docs) {
        const data = doc.data();
        const scope = scopeFromCampaignData(data.scope ?? data.placementScope);
        const placement = adPlacementFromCampaignData(data.placement ?? data.adPlacement);
        const categoryId = typeof data.categoryId === "string" && data.categoryId.trim()
            ? data.categoryId.trim()
            : "all";
        activeSlots.add(slotKeyFor(placement, scope, categoryId));
    }
    const waitingSnapshot = await db
        .collection("sponsorships")
        .where("status", "in", ["scheduled", "waitlisted"])
        .limit(100)
        .get();
    const candidates = waitingSnapshot.docs
        .filter((doc) => {
        const startsAt = toDate(doc.data().startsAt);
        return startsAt == null || startsAt <= nowDate;
    })
        .sort((a, b) => {
        const aStart = toDate(a.data().startsAt)?.getTime() ?? 0;
        const bStart = toDate(b.data().startsAt)?.getTime() ?? 0;
        return aStart - bStart;
    });
    for (const doc of candidates) {
        const data = doc.data();
        const scope = scopeFromCampaignData(data.scope ?? data.placementScope);
        const placement = adPlacementFromCampaignData(data.placement ?? data.adPlacement);
        const categoryId = typeof data.categoryId === "string" && data.categoryId.trim()
            ? data.categoryId.trim()
            : "all";
        const slotKey = slotKeyFor(placement, scope, categoryId);
        if (activeSlots.has(slotKey)) {
            if (data.status !== "waitlisted") {
                await doc.ref.update({
                    status: "waitlisted",
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                });
            }
            continue;
        }
        activeSlots.add(slotKey);
        await doc.ref.update({
            status: "active",
            activatedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
});
//# sourceMappingURL=sponsorships.js.map