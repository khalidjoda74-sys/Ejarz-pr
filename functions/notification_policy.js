const crypto = require("crypto");

const ROLE_PERMISSIONS = Object.freeze({
  owner: ["*"],
  manager: [
    "contracts.read", "contracts.write", "users.read", "payments.read",
    "content.write", "support.read", "support.write", "notifications.read",
    "notifications.write", "reports.read", "audit.read",
  ],
  reviewer: [
    "contracts.read", "contracts.write", "users.read", "notifications.read",
    "notifications.write", "audit.read",
  ],
  support: [
    "contracts.read", "users.read", "support.read", "support.write",
    "notifications.read", "notifications.write",
  ],
  finance: [
    "contracts.read", "users.read", "payments.read", "payments.write",
    "reports.read", "audit.read",
  ],
});

function notificationId(eventKey, recipient) {
  return crypto
    .createHash("sha256")
    .update(`${String(eventKey)}:${String(recipient)}`)
    .digest("hex");
}

function adminHasPermission(data, permission) {
  if (!data || data.active === false) return false;
  if (data.role === "owner") return true;
  const explicit = Array.isArray(data.permissions) ? data.permissions : [];
  const inherited = ROLE_PERMISSIONS[data.role] || [];
  return explicit.includes(permission) || inherited.includes(permission) ||
    inherited.includes("*");
}

function retryDelayMinutes(attempt) {
  return [5, 15, 60, 180, 720][Number(attempt) - 1] || 720;
}

function isDraftSubmissionTransition(before, after) {
  return before?.status === "draft" && after?.status === "awaitingPayment";
}

function rejectionNotificationContent(requestNumber, rawReason) {
  const number = String(requestNumber || "").trim();
  const reason = String(rawReason || "")
    .trim()
    .slice(0, 260)
    .replace(/[.!؟،؛:]+$/u, "")
    .trim();
  return {
    title: "تم رفض طلب العقد",
    body: reason
      ? `تم رفض الطلب رقم ${number} نهائيًا بسبب: ${reason}. لا يمكن تعديله أو إعادة إرساله. يمكنك تقديم طلب جديد أو التواصل مع الدعم الفني.`
      : "تم رفض هذا الطلب نهائيًا بعد مراجعته. لا يمكن تعديله أو إعادة إرساله. يمكنك تقديم طلب جديد أو التواصل مع الدعم الفني لمعرفة المزيد.",
  };
}

module.exports = {
  ROLE_PERMISSIONS,
  adminHasPermission,
  notificationId,
  retryDelayMinutes,
  isDraftSubmissionTransition,
  rejectionNotificationContent,
};
