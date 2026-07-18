"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ensureDemoOpportunity = void 0;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const db = (0, firestore_1.getFirestore)();
const demoCouncilId = "demo_laundry_public";
const demoOwnerId = "forsa_demo_editorial";
const categoryName = "فرص للتقبيل";
const demoTitle = "مغسلة ملابس للتقبيل بكامل التجهيزات";
const demoDescription = "فرصة تقبيل لمغسلة ملابس قائمة وجاهزة للتشغيل في موقع تجاري نشط داخل حي سكني. " +
    "تشمل غسالات ومجففات ومكابس كوي وطاولات فرز وتغليف ونظام استقبال وفواتير مع ديكورات مكتملة. " +
    "يوجد عملاء متكررون وقابلية لتوسيع خدمة الاستلام والتوصيل، ومناسبة لمن يبحث عن مشروع خدمي جاهز بدل البدء من الصفر. " +
    "يفضل قبل الاتفاق مراجعة عقد الإيجار وفواتير آخر ستة أشهر وحالة المعدات وتكاليف العمالة.";
const laundryImages = [
    "https://images.unsplash.com/photo-1582735689369-4fe89db7114c?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1677785078383-af0ac5cd0422?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1755657722450-26f64fbcddbd?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1532916697008-5bc24f95592a?auto=format&fit=crop&w=1200&q=80",
];
const demoComments = [
    ["مستشار تشغيل", "business:briefcase", "الفرصة تبدو جيدة إذا كانت المعدات تعمل يوميًا بدون أعطال متكررة. قبل الاتفاق اطلب تقرير صيانة مختصر وفواتير الكهرباء والمياه لآخر ستة أشهر.", 41],
    ["مهتم بالشراء", "business:handshake", "هل مبلغ التقبيل المطلوب يشمل جميع المعدات والديكور وقنوات التواصل، أم يوجد مبلغ منفصل للمخزون أو نقل العمالة؟", 36],
    ["خبير مشاريع", "business:experience", "الأهم هنا ليس شكل المحل فقط، بل متوسط الدخل الشهري بعد خصم الإيجار والرواتب والمنظفات. الأرقام التشغيلية ستحدد عدالة السعر.", 34],
    ["محلل مالي", "business:funding", "أنصح بفصل قيمة المعدات المستعملة عن الشهرة التجارية. إذا كان صافي الربح ثابتًا يمكن حساب مدة استرداد رأس المال بشكل أوضح.", 30],
    ["صاحب مغسلة سابق", "business:transfer", "انتبه لحالة الغسالات والمجففات وقت الضغط، لأن الأعطال في هذا النشاط قد تلتهم الربح بسرعة إذا لم تكن الصيانة منتظمة.", 28],
    ["رائد أعمال", "business:person_growth", "وجود قاعدة عملاء وخدمة توصيل يجعل الفرصة واعدة، خصوصًا لو كان بالإمكان تحويل العملاء إلى اشتراكات شهرية للعائلات.", 25],
    ["مستثمر خدمات", "business:growth", "هل يوجد عقد إيجار طويل أو قابل للتجديد؟ مدة الإيجار أهم نقطة بعد المعدات، لأن نقل المغسلة قد يفقدها جزءًا كبيرًا من قيمتها.", 23],
    ["مهتم من الرياض", "business:storefront", "ممكن توضيح الحي والشارع بشكل تقريبي؟ أريد معرفة هل الموقع يخدم عائلات كثيرة أم يعتمد على حركة عابرة فقط.", 21],
    ["مشغل محلي", "business:storefront", "يفضل زيارة المغسلة في وقت الذروة ومراقبة عدد الطلبات الفعلية، لا تعتمد فقط على كشف المبيعات المكتوب.", 19],
    ["باحث عن فرصة", "business:search", "هل السعر قابل للتفاوض بعد المعاينة؟ وهل يوجد سبب واضح للتقبيل مثل التفرغ أو الانتقال؟", 17],
    ["مستشار قانوني", "business:verified", "قبل العربون تأكد من إمكانية نقل السجل والبلدية والعقد، وأنه لا توجد التزامات أو شكاوى قائمة على النشاط.", 15],
    ["خبير تسويق", "business:marketing", "لو الحسابات الحالية نشطة في خرائط جوجل والواتساب فهذا يرفع قيمة الفرصة، لأن اكتساب العملاء في المغاسل يحتاج وقت.", 14],
    ["مشتري جاد", "business:funding", "أحتاج معرفة متوسط المبيعات اليومية وعدد العمال الحاليين وهل الرواتب مدفوعة بانتظام خلال آخر شهرين.", 12],
    ["مشرف تشغيل", "business:briefcase", "هل يوجد نظام باركود أو فواتير يوضح كل طلب؟ وجود نظام مضبوط يقلل ضياع الملابس ويرفع ثقة العملاء.", 11],
    ["عضو مهتم", "business:idea", "ما هي ساعات العمل الحالية؟ وهل توجد إمكانية لإضافة خدمة تنظيف السجاد أو المفروشات لزيادة الدخل؟", 9],
];
const demoReplies = [
    [0, "مستثمر مهتم", "business:funding", "هل يمكن معرفة عمر المعدات وهل يوجد ضمان أو صيانة حديثة قبل التقبيل؟"],
    [0, "مشغل خدمات", "business:briefcase", "مهم جدًا فحص المجففات وقت الضغط، لأنها أكثر جزء يؤثر على سرعة التسليم."],
    [0, "باحث عن فرصة", "business:search", "هل يشمل التقبيل حسابات التواصل وقاعدة العملاء الحالية؟"],
    [1, "محاسب مشاريع", "business:verified", "الأفضل طلب كشف المبيعات والمصاريف لآخر ستة أشهر قبل تحديد السعر العادل."],
    [1, "مهتم من جدة", "business:storefront", "إذا الموقع داخل حي سكني نشط فخدمة الاشتراكات الشهرية قد ترفع الدخل."],
    [2, "صاحب نشاط سابق", "business:experience", "لا تنسوا مراجعة عقد الإيجار وإمكانية نقل الرخصة قبل دفع العربون."],
];
const seedDemoComments = async (councilId) => {
    const refs = demoComments.map((_, index) => db.collection("comments").doc(`${councilId}_seed_${index + 1}`));
    const replyRefs = demoReplies.map((_, index) => db.collection("comments").doc(`${councilId}_reply_${index + 1}`));
    const snapshots = await db.getAll(...refs, ...replyRefs);
    const commentSnapshots = snapshots.slice(0, refs.length);
    const replySnapshots = snapshots.slice(refs.length);
    const repliesCountByParent = demoReplies.reduce((counts, [parentIndex]) => {
        counts[parentIndex] = (counts[parentIndex] ?? 0) + 1;
        return counts;
    }, {});
    const batch = db.batch();
    let created = 0;
    demoComments.forEach(([name, avatar, text, convincingCount], index) => {
        const ref = refs[index];
        const baseData = {
            councilId,
            councilTitle: demoTitle,
            authorId: `demo_expert_${index + 1}`,
            userId: `demo_expert_${index + 1}`,
            authorSnapshot: { displayName: name, avatarEmoji: avatar },
            userNickname: name,
            userAvatar: avatar,
            text,
            parentId: null,
            status: "visible",
            convincingVotesCount: convincingCount,
            convincingCount,
            repliesCount: repliesCountByParent[index] ?? 0,
            reportsCount: 0,
            isBestComment: false,
            isBest: false,
            isSeedContent: true,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        };
        if (commentSnapshots[index].exists) {
            batch.set(ref, baseData, { merge: true });
            return;
        }
        created += 1;
        batch.set(ref, {
            ...baseData,
            createdAt: firestore_1.Timestamp.fromDate(new Date(Date.now() - (index + 1) * 17 * 60 * 1000)),
        });
    });
    demoReplies.forEach(([parentIndex, name, avatar, text], index) => {
        const ref = replyRefs[index];
        const parentId = `${councilId}_seed_${parentIndex + 1}`;
        const baseData = {
            councilId,
            councilTitle: demoTitle,
            authorId: `demo_reply_${index + 1}`,
            userId: `demo_reply_${index + 1}`,
            authorSnapshot: { displayName: name, avatarEmoji: avatar },
            userNickname: name,
            userAvatar: avatar,
            text,
            parentId,
            status: "visible",
            convincingVotesCount: 0,
            convincingCount: 0,
            repliesCount: 0,
            reportsCount: 0,
            isBestComment: false,
            isBest: false,
            isSeedContent: true,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        };
        if (replySnapshots[index].exists) {
            batch.set(ref, baseData, { merge: true });
            return;
        }
        created += 1;
        batch.set(ref, {
            ...baseData,
            createdAt: firestore_1.Timestamp.fromDate(new Date(Date.now() - (index + 4) * 11 * 60 * 1000)),
        });
    });
    await batch.commit();
    return created;
};
exports.ensureDemoOpportunity = (0, https_1.onCall)({ region: "us-central1" }, async () => {
    const councilRef = db.collection("councils").doc(demoCouncilId);
    const existing = await councilRef.get();
    const baseCouncilData = {
        title: demoTitle,
        description: demoDescription,
        categoryId: categoryName,
        categoryName,
        category: categoryName,
        city: "الرياض",
        countryCode: "SA",
        countryName: "المملكة العربية السعودية",
        createdBy: demoOwnerId,
        createdByName: "Forsa Pro",
        ownerId: demoOwnerId,
        ownerSnapshot: {
            displayName: "Forsa Pro",
            photoUrl: null,
            avatarEmoji: "business:verified",
        },
        visibility: "public",
        shareCode: demoCouncilId,
        status: "active",
        type: "public",
        allowComments: true,
        allowReplies: true,
        isCouncilOfDay: true,
        isPinned: true,
        pinnedUntil: null,
        sponsorId: null,
        bestCommentId: null,
        coverImageUrl: laundryImages[0],
        coverThumbnailUrl: laundryImages[0],
        coverMediumUrl: laundryImages[0],
        imageUrls: laundryImages,
        thumbnailUrls: laundryImages,
        mediumImageUrls: laundryImages,
        imagesCount: laundryImages.length,
        options: ["support", "against", "neutral"],
        voteOptions: [
            { id: "support", label: "فرصة واعدة", color: "#0F4A35" },
            { id: "against", label: "مخاطر عالية", color: "#D94F4F" },
            { id: "neutral", label: "أحتاج تفاصيل", color: "#D9A441" },
        ],
        voteCounts: { support: 222, against: 59, neutral: 45 },
        percentages: { support: 68, against: 18, neutral: 14 },
        participantsCount: 326,
        commentsCount: demoComments.length + demoReplies.length,
        votesCount: 326,
        viewsCount: 2410,
        sharesCount: 86,
        reportsCount: 0,
        isDemoSeedOpportunity: true,
        isSeedContent: true,
        visibilityUpdatedAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
        await councilRef.set({
            ...baseCouncilData,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    else {
        await councilRef.set(baseCouncilData, { merge: true });
    }
    await seedDemoComments(demoCouncilId);
    return { councilId: demoCouncilId, created: !existing.exists };
});
//# sourceMappingURL=opportunities.js.map