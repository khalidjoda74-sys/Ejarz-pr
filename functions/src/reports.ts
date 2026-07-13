import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

const db = getFirestore();
const targetTypes = ["council", "comment", "user"] as const;

const cleanString = (
  value: unknown,
  fieldName: string,
  min = 1,
  max = 500,
): string => {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${fieldName} غير صالح.`);
  }

  const text = value.trim();
  if (text.length < min || text.length > max) {
    throw new HttpsError("invalid-argument", `${fieldName} غير صالح.`);
  }

  return text;
};

const optionalDetails = (value: unknown): string | null => {
  if (value == null) return null;
  return cleanString(value, "تفاصيل البلاغ", 0, 500);
};

const safeString = (value: unknown): string => {
  return typeof value === "string" && value.trim() ? value.trim() : "";
};

export const createReport = onCall({region: "us-central1"}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول لإرسال بلاغ.");
  }

  const targetType = cleanString(request.data?.targetType, "نوع البلاغ", 1, 30);
  if (!targetTypes.includes(targetType as (typeof targetTypes)[number])) {
    throw new HttpsError("invalid-argument", "نوع البلاغ غير مدعوم.");
  }

  const targetPath = cleanString(request.data?.targetPath, "مسار البلاغ", 3, 300);
  const reason = cleanString(request.data?.reason, "سبب البلاغ", 2, 80);
  const details = optionalDetails(request.data?.details);
  const targetId = targetPath.split("/").filter(Boolean).pop() ?? targetPath;
  const councilId =
    typeof request.data?.councilId === "string"
      ? request.data.councilId.trim()
      : null;
  const commentId =
    typeof request.data?.commentId === "string"
      ? request.data.commentId.trim()
      : null;
  const reportRef = db.collection("reports").doc();
  let targetOwnerId: string | null = null;

  if (targetType === "comment" && commentId) {
    const commentSnap = await db.collection("comments").doc(commentId).get();
    if (commentSnap.exists) {
      const comment = commentSnap.data() ?? {};
      targetOwnerId = safeString(comment.authorId) || safeString(comment.userId) || null;
    }
  } else if (targetType === "council" && councilId) {
    const councilSnap = await db.collection("councils").doc(councilId).get();
    if (councilSnap.exists) {
      const council = councilSnap.data() ?? {};
      targetOwnerId = safeString(council.ownerId) || safeString(council.createdBy) || null;
    }
  } else if (targetType === "user") {
    targetOwnerId = targetId;
  }

  if (targetOwnerId === uid) {
    throw new HttpsError("failed-precondition", "لا يمكن إرسال بلاغ على محتواك الشخصي.");
  }

  await reportRef.set({
    reporterId: uid,
    reportedBy: uid,
    targetType,
    targetId,
    targetPath,
    reason,
    description: details ?? "",
    details,
    councilId,
    commentId,
    status: "new",
    priority: "medium",
    targetOwnerId,
    actionTaken: null,
    reviewedBy: null,
    reviewedAt: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    reportId: reportRef.id,
  };
});
