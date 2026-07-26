import {
  DocumentReference,
  FieldValue,
  getFirestore,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {createUserNotification} from "./notifications";
import {assertAllowedContent} from "./moderation";

const db = getFirestore();

const cleanText = (value: unknown, fieldName: string): string => {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${fieldName} غير صالح.`);
  }

  const text = value.trim();
  if (text.length < 2 || text.length > 500) {
    throw new HttpsError(
      "invalid-argument",
      `${fieldName} يجب أن يكون بين 2 و 500 حرف.`,
    );
  }

  return text;
};

const optionalString = (value: unknown): string | null => {
  if (typeof value !== "string") return null;
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

const safeString = (value: unknown, fallback = ""): string => {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
};

export const addComment = onCall({region: "us-central1"}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول للتعليق.");
  }

  const councilId = optionalString(request.data?.councilId);
  if (!councilId) {
    throw new HttpsError("invalid-argument", "معرف الفرصة غير صالح.");
  }

  const text = cleanText(request.data?.text, "نص التعليق");
  assertAllowedContent(text);
  const parentId = optionalString(request.data?.parentId);
  const councilRef = db.collection("councils").doc(councilId);
  const commentsRef = db.collection("comments");
  const commentRef = commentsRef.doc();
  const userRef = db.collection("users").doc(uid);
  const publicProfileRef = db.collection("publicProfiles").doc(uid);

  const notificationContext = await db.runTransaction(async (transaction) => {
    const [councilSnap, userSnap, publicProfileSnap] = await Promise.all([
      transaction.get(councilRef),
      transaction.get(userRef),
      transaction.get(publicProfileRef),
    ]);

    if (!councilSnap.exists) {
      throw new HttpsError("not-found", "الفرصة غير موجودة.");
    }

    const council = councilSnap.data() ?? {};
    if (!commentableStatuses.has(safeString(council.status, "active"))) {
      throw new HttpsError("failed-precondition", "لا يمكن التعليق على هذه الفرصة.");
    }

    if (council.allowComments === false) {
      throw new HttpsError("failed-precondition", "التعليقات غير مفعلة لهذه الفرصة.");
    }

    let parentRef: DocumentReference | null = null;
    let parentAuthorId: string | null = null;
    if (parentId) {
      parentRef = commentsRef.doc(parentId);
      const parentSnap = await transaction.get(parentRef);
      if (!parentSnap.exists) {
        throw new HttpsError("not-found", "التعليق الأصلي غير موجود.");
      }

      const parent = parentSnap.data() ?? {};
      if (parent.status !== "visible") {
        throw new HttpsError("failed-precondition", "لا يمكن الرد على هذا التعليق.");
      }

      if (parent.parentId != null) {
        throw new HttpsError("failed-precondition", "الردود متاحة لمستوى واحد فقط.");
      }

      parentAuthorId =
        typeof parent.authorId === "string" ? parent.authorId : null;
    }

    if (!userSnap.exists || safeString(userSnap.data()?.status, "active") !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "الحساب غير متاح لإضافة تعليق.",
      );
    }
    const publicProfile = publicProfileSnap.exists
      ? publicProfileSnap.data() ?? {}
      : {};
    if (
      !publicProfileSnap.exists ||
      publicProfile.uid !== uid ||
      publicProfile.isVisible !== true ||
      publicProfile.demo === true
    ) {
      throw new HttpsError(
        "failed-precondition",
        "أكمل هويتك العامة داخل التطبيق قبل إضافة تعليق.",
      );
    }
    const displayName = safeString(
      publicProfile.displayName,
      "عضو فرصة برو",
    );
    const publicPhotoUrl =
      typeof publicProfile.publicPhotoUrl === "string" &&
      publicProfile.publicPhotoUrl.trim()
        ? publicProfile.publicPhotoUrl.trim()
        : null;
    const avatarEmoji =
      typeof publicProfile.avatarEmoji === "string" &&
      publicProfile.avatarEmoji.trim()
        ? publicProfile.avatarEmoji.trim()
        : "business:person_growth";

    transaction.set(commentRef, {
      councilId,
      councilTitle: safeString(council.title, "فرصة"),
      authorId: uid,
      userId: uid,
      authorSnapshot: {
        displayName,
        ...(publicPhotoUrl ? {photoUrl: publicPhotoUrl} : {}),
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
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    transaction.update(councilRef, {
      commentsCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (parentRef) {
      transaction.update(parentRef, {
        repliesCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    transaction.set(
      userRef,
      {
        commentsCount: FieldValue.increment(1),
        lastActiveAt: FieldValue.serverTimestamp(),
        stats: {
          commentsCount: FieldValue.increment(1),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

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
    if (
      notificationContext.parentAuthorId &&
      notificationContext.parentAuthorId !== uid
    ) {
      await createUserNotification({
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
      await createUserNotification({
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
  } catch (error) {
    console.error("Comment notification failed", error);
  }

  return {
    commentId: notificationContext.commentId,
    parentId: notificationContext.parentId,
  };
});

export const toggleConvincingVote = onCall(
  {region: "us-central1"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول.");
    }

    const councilId = optionalString(request.data?.councilId);
    const commentId = optionalString(request.data?.commentId);
    if (!councilId || !commentId) {
      throw new HttpsError("invalid-argument", "بيانات التعليق غير صالحة.");
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
        throw new HttpsError("not-found", "الفرصة غير موجودة.");
      }

      if (!commentSnap.exists) {
        throw new HttpsError("not-found", "التعليق غير موجود.");
      }

      const comment = commentSnap.data() ?? {};
      if (comment.status !== "visible") {
        throw new HttpsError("failed-precondition", "التعليق غير متاح.");
      }

      const authorId =
        typeof comment.authorId === "string" && comment.authorId.trim()
          ? comment.authorId.trim()
          : typeof comment.userId === "string" && comment.userId.trim()
            ? comment.userId.trim()
            : "";
      if (authorId === uid) {
        throw new HttpsError(
          "failed-precondition",
          "لا يمكن تقييم تعليقك الشخصي.",
        );
      }

      const current =
        typeof comment.convincingCount === "number" ? comment.convincingCount : 0;

      if (voteSnap.exists) {
        transaction.delete(voteRef);
        transaction.update(commentRef, {
          convincingVotesCount: Math.max(0, current - 1),
          convincingCount: Math.max(0, current - 1),
          updatedAt: FieldValue.serverTimestamp(),
        });

        return {
          selected: false,
          convincingCount: Math.max(0, current - 1),
        };
      }

      transaction.set(voteRef, {
        uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.update(commentRef, {
        convincingVotesCount: current + 1,
        convincingCount: current + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        selected: true,
        convincingCount: current + 1,
      };
    });
  },
);
