"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.toggleConvincingVote = exports.addComment = void 0;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const notifications_1 = require("./notifications");
const moderation_1 = require("./moderation");
const db = (0, firestore_1.getFirestore)();
const cleanText = (value, fieldName) => {
    if (typeof value !== "string") {
        throw new https_1.HttpsError("invalid-argument", `${fieldName} غير صالح.`);
    }
    const text = value.trim();
    if (text.length < 2 || text.length > 500) {
        throw new https_1.HttpsError("invalid-argument", `${fieldName} يجب أن يكون بين 2 و 500 حرف.`);
    }
    return text;
};
const optionalString = (value) => {
    if (typeof value !== "string")
        return null;
    const text = value.trim();
    return text.length > 0 ? text : null;
};
const commentableStatuses = new Set([
    "active",
    "endingSoon",
    "votingClosed",
    "closed",
    "ended",
]);
const safeString = (value, fallback = "") => {
    return typeof value === "string" && value.trim() ? value.trim() : fallback;
};
exports.addComment = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "يجب تسجيل الدخول للتعليق.");
    }
    const councilId = optionalString(request.data?.councilId);
    if (!councilId) {
        throw new https_1.HttpsError("invalid-argument", "معرف الفرصة غير صالح.");
    }
    const text = cleanText(request.data?.text, "نص التعليق");
    (0, moderation_1.assertAllowedContent)(text);
    const parentId = optionalString(request.data?.parentId);
    const councilRef = db.collection("councils").doc(councilId);
    const commentsRef = db.collection("comments");
    const commentRef = commentsRef.doc();
    const userRef = db.collection("users").doc(uid);
    const notificationContext = await db.runTransaction(async (transaction) => {
        const [councilSnap, userSnap] = await Promise.all([
            transaction.get(councilRef),
            transaction.get(userRef),
        ]);
        if (!councilSnap.exists) {
            throw new https_1.HttpsError("not-found", "الفرصة غير موجودة.");
        }
        const council = councilSnap.data() ?? {};
        if (!commentableStatuses.has(safeString(council.status, "active"))) {
            throw new https_1.HttpsError("failed-precondition", "لا يمكن التعليق على هذه الفرصة.");
        }
        if (council.allowComments === false) {
            throw new https_1.HttpsError("failed-precondition", "التعليقات غير مفعلة لهذه الفرصة.");
        }
        let parentRef = null;
        let parentAuthorId = null;
        if (parentId) {
            parentRef = commentsRef.doc(parentId);
            const parentSnap = await transaction.get(parentRef);
            if (!parentSnap.exists) {
                throw new https_1.HttpsError("not-found", "التعليق الأصلي غير موجود.");
            }
            const parent = parentSnap.data() ?? {};
            if (parent.status !== "visible") {
                throw new https_1.HttpsError("failed-precondition", "لا يمكن الرد على هذا التعليق.");
            }
            if (parent.parentId != null) {
                throw new https_1.HttpsError("failed-precondition", "الردود متاحة لمستوى واحد فقط.");
            }
            parentAuthorId =
                typeof parent.authorId === "string" ? parent.authorId : null;
        }
        const user = userSnap.exists ? userSnap.data() ?? {} : {};
        const displayName = typeof user.displayName === "string" && user.displayName.trim()
            ? user.displayName.trim()
            : request.auth?.token.name ?? "عضو فرصتي";
        const photoUrl = typeof user.photoUrl === "string" && user.photoUrl.trim()
            ? user.photoUrl.trim()
            : request.auth?.token.picture ?? null;
        const avatarEmoji = typeof user.avatarEmoji === "string" && user.avatarEmoji.trim()
            ? user.avatarEmoji.trim()
            : "👤";
        transaction.set(commentRef, {
            councilId,
            councilTitle: safeString(council.title, "فرصة"),
            authorId: uid,
            userId: uid,
            authorSnapshot: {
                displayName,
                photoUrl,
                avatarEmoji,
            },
            userNickname: displayName,
            userAvatar: avatarEmoji,
            text,
            parentId,
            status: "visible",
            likesCount: 0,
            convincingVotesCount: 0,
            convincingCount: 0,
            repliesCount: 0,
            reportsCount: 0,
            isBestComment: false,
            isBest: false,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        transaction.update(councilRef, {
            commentsCount: firestore_1.FieldValue.increment(1),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        if (parentRef) {
            transaction.update(parentRef, {
                repliesCount: firestore_1.FieldValue.increment(1),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        transaction.set(userRef, {
            commentsCount: firestore_1.FieldValue.increment(1),
            lastActiveAt: firestore_1.FieldValue.serverTimestamp(),
            stats: {
                commentsCount: firestore_1.FieldValue.increment(1),
            },
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        return {
            commentId: commentRef.id,
            parentId,
            parentAuthorId,
            ownerId: typeof council.ownerId === "string" && council.ownerId.trim()
                ? council.ownerId.trim()
                : typeof council.createdBy === "string" && council.createdBy.trim()
                    ? council.createdBy.trim()
                    : null,
            councilTitle: safeString(council.title, "فرصة"),
        };
    });
    const targetRoute = `/council/${councilId}`;
    const shortTitle = notificationContext.councilTitle;
    try {
        if (notificationContext.parentAuthorId &&
            notificationContext.parentAuthorId !== uid) {
            await (0, notifications_1.createUserNotification)({
                uid: notificationContext.parentAuthorId,
                type: "reply",
                title: "رد جديد على تعليقك",
                body: `وصلك رد على تعليقك في فرصة: ${shortTitle}`,
                targetRoute,
                councilId,
                commentId: notificationContext.commentId,
            });
        }
        if (notificationContext.ownerId && notificationContext.ownerId !== uid) {
            await (0, notifications_1.createUserNotification)({
                uid: notificationContext.ownerId,
                type: "owner_activity",
                title: "نشاط جديد في فرصتك",
                body: parentId
                    ? `تمت إضافة رد في فرصة: ${shortTitle}`
                    : `تمت إضافة تعليق جديد في فرصة: ${shortTitle}`,
                targetRoute,
                councilId,
                commentId: notificationContext.commentId,
            });
        }
    }
    catch (error) {
        console.error("Comment notification failed", error);
    }
    return {
        commentId: notificationContext.commentId,
        parentId: notificationContext.parentId,
    };
});
exports.toggleConvincingVote = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "يجب تسجيل الدخول.");
    }
    const councilId = optionalString(request.data?.councilId);
    const commentId = optionalString(request.data?.commentId);
    if (!councilId || !commentId) {
        throw new https_1.HttpsError("invalid-argument", "بيانات التعليق غير صالحة.");
    }
    const councilRef = db.collection("councils").doc(councilId);
    const commentRef = db.collection("comments").doc(commentId);
    const voteRef = commentRef.collection("convincingVotes").doc(uid);
    return db.runTransaction(async (transaction) => {
        const [councilSnap, commentSnap, voteSnap] = await Promise.all([
            transaction.get(councilRef),
            transaction.get(commentRef),
            transaction.get(voteRef),
        ]);
        if (!councilSnap.exists) {
            throw new https_1.HttpsError("not-found", "الفرصة غير موجودة.");
        }
        if (!commentSnap.exists) {
            throw new https_1.HttpsError("not-found", "التعليق غير موجود.");
        }
        const comment = commentSnap.data() ?? {};
        if (comment.status !== "visible") {
            throw new https_1.HttpsError("failed-precondition", "التعليق غير متاح.");
        }
        const authorId = typeof comment.authorId === "string" && comment.authorId.trim()
            ? comment.authorId.trim()
            : typeof comment.userId === "string" && comment.userId.trim()
                ? comment.userId.trim()
                : "";
        if (authorId === uid) {
            throw new https_1.HttpsError("failed-precondition", "لا يمكن تقييم تعليقك الشخصي.");
        }
        const current = typeof comment.convincingCount === "number" ? comment.convincingCount : 0;
        if (voteSnap.exists) {
            transaction.delete(voteRef);
            transaction.update(commentRef, {
                convincingVotesCount: Math.max(0, current - 1),
                convincingCount: Math.max(0, current - 1),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            return {
                selected: false,
                convincingCount: Math.max(0, current - 1),
            };
        }
        transaction.set(voteRef, {
            uid,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        transaction.update(commentRef, {
            convincingVotesCount: current + 1,
            convincingCount: current + 1,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        return {
            selected: true,
            convincingCount: current + 1,
        };
    });
});
//# sourceMappingURL=comments.js.map