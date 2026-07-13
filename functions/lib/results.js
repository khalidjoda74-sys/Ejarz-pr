"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateCouncilResult = exports.scheduledCloseExpiredCouncils = void 0;
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const notifications_1 = require("./notifications");
const db = (0, firestore_1.getFirestore)();
const voteOptions = ["support", "against", "neutral"];
const isVoteOption = (value) => {
    return typeof value === "string" && voteOptions.includes(value);
};
const emptyVoteCounts = () => ({
    support: 0,
    against: 0,
    neutral: 0,
});
const toVoteCounts = (value) => {
    const counts = emptyVoteCounts();
    if (value == null || typeof value !== "object")
        return counts;
    const source = value;
    for (const option of voteOptions) {
        const raw = source[option];
        counts[option] = typeof raw === "number" && Number.isFinite(raw) ? raw : 0;
    }
    return counts;
};
const percentagesFor = (counts) => {
    const total = totalVotesFor(counts);
    if (total <= 0)
        return emptyVoteCounts();
    return {
        support: Math.round((counts.support / total) * 100),
        against: Math.round((counts.against / total) * 100),
        neutral: Math.round((counts.neutral / total) * 100),
    };
};
const totalVotesFor = (counts) => {
    return voteOptions.reduce((sum, option) => sum + counts[option], 0);
};
const highestOption = (counts) => {
    return voteOptions.reduce((best, option) => {
        return counts[option] > counts[best] ? option : best;
    }, "support");
};
const voteCopyForCategory = (categoryName) => {
    const category = typeof categoryName === "string" ? categoryName.trim() : "";
    if (category.includes("تقبيل")) {
        return {
            support: "تستحق المعاينة",
            against: "مخاطر عالية",
            neutral: "أحتاج أرقام",
            emptySummary: "انتهت الفرصة دون آراء كافية، لذلك لا توجد إشارة واضحة حتى الآن.",
            supportSummary: "أغلب الآراء ترى أن الفرصة تستحق المعاينة، مع أهمية مراجعة الأرقام قبل أي قرار.",
            againstSummary: "أغلب الآراء تشير إلى مخاطر عالية، لذلك تحتاج الفرصة تدقيقًا أكبر قبل المعاينة.",
            neutralSummary: "أغلب الآراء تحتاج أرقامًا أوضح مثل الدخل، الإيجار، التكاليف، وسبب التقبيل.",
        };
    }
    if (category.includes("مطلوبة") || category.includes("مطلوب")) {
        return {
            support: "لدي فرصة",
            against: "أعرف جهة",
            neutral: "أحتاج تفاصيل",
            emptySummary: "انتهت الفرصة دون آراء كافية، لذلك لا توجد إشارة واضحة حتى الآن.",
            supportSummary: "يوجد اهتمام مباشر من مشاركين لديهم فرص مناسبة، ويمكن لصاحب الطلب متابعة الردود والتعليقات.",
            againstSummary: "أغلب التفاعل جاء من مشاركين يعرفون جهات أو مصادر محتملة، وهذا مفيد للمتابعة والبحث.",
            neutralSummary: "أغلب الآراء تحتاج تفاصيل أكثر قبل تقديم فرصة مناسبة، مثل المدينة والميزانية ونوع النشاط.",
        };
    }
    if (category.includes("شراكة")) {
        return {
            support: "مهتم",
            against: "مخاطر عالية",
            neutral: "أحتاج تفاصيل",
            emptySummary: "انتهت الفرصة دون آراء كافية، لذلك لا توجد إشارة واضحة حتى الآن.",
            supportSummary: "هناك اهتمام واضح بالشراكة، لكن الأفضل توضيح الأدوار ونسبة المشاركة قبل الانتقال للاتفاق.",
            againstSummary: "أغلب الآراء ترى أن مخاطر الشراكة عالية، ويحتاج العرض إلى ضمانات وتفاصيل أوضح.",
            neutralSummary: "أغلب الآراء تحتاج تفاصيل أكثر عن رأس المال، التشغيل، الخبرة، والمسؤوليات.",
        };
    }
    return {
        support: "مفيدة",
        against: "أرى غير ذلك",
        neutral: "تجربة مشابهة",
        emptySummary: "انتهت الفرصة دون آراء كافية، لذلك لا توجد إشارة واضحة حتى الآن.",
        supportSummary: "أغلب المشاركين وجدوا التجربة مفيدة ويمكن الرجوع للتعليقات لفهم الدروس العملية.",
        againstSummary: "هناك رأي آخر أو اختلاف مع التجربة، لذلك قراءة التعليقات تساعد على فهم وجهات النظر.",
        neutralSummary: "أغلب المشاركين لديهم تجارب مشابهة أو مواقف قريبة، لذلك قراءة التعليقات مهمة لفهم الصورة كاملة.",
    };
};
const summaryFor = (counts, categoryName) => {
    const total = totalVotesFor(counts);
    const copy = voteCopyForCategory(categoryName);
    if (total <= 0)
        return copy.emptySummary;
    switch (highestOption(counts)) {
        case "support":
            return copy.supportSummary;
        case "against":
            return copy.againstSummary;
        case "neutral":
            return copy.neutralSummary;
    }
};
const safeString = (value, fallback = "") => {
    return typeof value === "string" && value.trim() ? value.trim() : fallback;
};
const commentSnapshot = (doc) => {
    const data = doc.data();
    return {
        id: doc.id,
        authorId: data.authorId ?? null,
        authorSnapshot: data.authorSnapshot ?? {},
        text: safeString(data.text),
        convincingCount: typeof data.convincingCount === "number" ? data.convincingCount : 0,
        repliesCount: typeof data.repliesCount === "number" ? data.repliesCount : 0,
        isBest: data.isBest === true,
        createdAt: data.createdAt ?? null,
    };
};
const writeCouncilResult = async (councilId, council) => {
    const counts = toVoteCounts(council.voteCounts);
    const percentages = percentagesFor(counts);
    const totalVotes = totalVotesFor(counts);
    const resultRef = db.collection("councilResults").doc(councilId);
    const resultSnap = await resultRef.get();
    const shouldNotify = !resultSnap.exists;
    const categoryName = safeString(council.categoryName, "عام");
    const summaryText = summaryFor(counts, categoryName);
    const commentsSnapshot = await db
        .collection("councils")
        .doc(councilId)
        .collection("comments")
        .where("status", "==", "visible")
        .orderBy("convincingCount", "desc")
        .orderBy("createdAt", "desc")
        .limit(3)
        .get();
    const bestComments = commentsSnapshot.docs.map(commentSnapshot);
    await resultRef.set({
        councilId,
        title: safeString(council.title, "فرصة بدون عنوان"),
        description: safeString(council.description),
        categoryName,
        totalVotes,
        voteCounts: counts,
        percentages,
        bestComments,
        summaryText,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        bestComments,
        shouldNotify,
        summaryText,
    };
};
const voteLabel = (categoryName, option) => {
    const copy = voteCopyForCategory(categoryName);
    switch (option) {
        case "support":
            return copy.support;
        case "against":
            return copy.against;
        case "neutral":
            return copy.neutral;
        default:
            return "غير محدد";
    }
};
const votersForCouncil = async (councilId) => {
    const votesSnapshot = await db
        .collection("councils")
        .doc(councilId)
        .collection("votes")
        .limit(500)
        .get();
    return votesSnapshot.docs
        .map((doc) => {
        const vote = doc.data();
        const uid = safeString(vote.uid, doc.id);
        return uid ? { uid, option: isVoteOption(vote.option) ? vote.option : null } : null;
    })
        .filter((item) => item != null);
};
const notifyCouncilResult = async (councilId, council, bestComments) => {
    const title = safeString(council.title, "فرصة");
    const categoryName = safeString(council.categoryName, "عام");
    const targetRoute = `/result/${councilId}`;
    const ownerId = safeString(council.ownerId, safeString(council.createdBy));
    const voters = await votersForCouncil(councilId);
    const notifications = [];
    if (ownerId) {
        notifications.push((0, notifications_1.createUserNotification)({
            uid: ownerId,
            type: "result_ready",
            title: "نتائج فرصتك جاهزة",
            body: `توفرت نتائج الرأي السريع في "${title}". يمكنك الآن مراجعة النتائج ومتابعة التعليقات.`,
            targetRoute,
            councilId,
        }));
    }
    for (const voter of voters) {
        if (voter.uid === ownerId)
            continue;
        notifications.push((0, notifications_1.createUserNotification)({
            uid: voter.uid,
            type: "result_ready",
            title: "نتائج فرصة شاركت فيها جاهزة",
            body: `توفرت نتائج الرأي السريع في "${title}". رأيك كان: ${voteLabel(categoryName, voter.option)}. شاهد النتائج الآن.`,
            targetRoute,
            councilId,
        }));
    }
    await Promise.all(notifications);
};
exports.scheduledCloseExpiredCouncils = (0, scheduler_1.onSchedule)({
    region: "us-central1",
    schedule: "every 5 minutes",
    timeZone: "Asia/Riyadh",
}, async () => {
    const snapshot = await db
        .collection("councils")
        .where("status", "==", "active")
        .where("closesAt", "<=", new Date())
        .limit(100)
        .get();
    if (snapshot.empty)
        return;
    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
        batch.update(doc.ref, {
            status: "votingClosed",
            closedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    await batch.commit();
});
exports.generateCouncilResult = (0, firestore_2.onDocumentUpdated)({
    region: "us-central1",
    document: "councils/{councilId}",
}, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const councilId = event.params.councilId;
    if (!after || after.status !== "votingClosed")
        return;
    if (before?.status === "votingClosed")
        return;
    const result = await writeCouncilResult(councilId, after);
    if (result.shouldNotify) {
        await notifyCouncilResult(councilId, after, result.bestComments);
    }
});
//# sourceMappingURL=results.js.map