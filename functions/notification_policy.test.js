const assert = require("node:assert/strict");
const test = require("node:test");
const {
  adminHasPermission,
  notificationId,
  retryDelayMinutes,
  isDraftSubmissionTransition,
  rejectionNotificationContent,
} = require("./notification_policy");

test("notification IDs are deterministic per event and recipient", () => {
  const first = notificationId("contract.created:event-1", "user-1");
  assert.equal(first, notificationId("contract.created:event-1", "user-1"));
  assert.notEqual(first, notificationId("contract.created:event-1", "user-2"));
  assert.notEqual(first, notificationId("contract.created:event-2", "user-1"));
  assert.match(first, /^[a-f0-9]{64}$/);
});

test("admin routing respects active state, roles, and explicit permissions", () => {
  assert.equal(adminHasPermission({ active: true, role: "owner" }, "payments.read"), true);
  assert.equal(adminHasPermission({ active: true, role: "reviewer" }, "contracts.read"), true);
  assert.equal(adminHasPermission({ active: true, role: "reviewer" }, "payments.read"), false);
  assert.equal(adminHasPermission({ active: true, role: "reviewer", permissions: ["payments.read"] }, "payments.read"), true);
  assert.equal(adminHasPermission({ active: false, role: "owner" }, "contracts.read"), false);
});

test("push retry schedule is bounded and increasing", () => {
  assert.deepEqual([1, 2, 3, 4, 5].map(retryDelayMinutes), [5, 15, 60, 180, 720]);
  assert.equal(retryDelayMinutes(99), 720);
});

test("only the final draft submission creates the contract event", () => {
  assert.equal(
    isDraftSubmissionTransition(
      { status: "draft" },
      { status: "awaitingPayment" },
    ),
    true,
  );
  assert.equal(
    isDraftSubmissionTransition({ status: "draft" }, { status: "draft" }),
    false,
  );
  assert.equal(
    isDraftSubmissionTransition(
      { status: "awaitingPayment" },
      { status: "processing" },
    ),
    false,
  );
});

test("rejection notification uses final wording and cleans punctuation", () => {
  assert.deepEqual(
    rejectionNotificationContent("REQ-101", "بيانات الملكية غير متطابقة."),
    {
      title: "تم رفض طلب العقد",
      body: "تم رفض الطلب رقم REQ-101 نهائيًا بسبب: بيانات الملكية غير متطابقة. لا يمكن تعديله أو إعادة إرساله. يمكنك تقديم طلب جديد أو التواصل مع الدعم الفني.",
    },
  );
  assert.equal(
    rejectionNotificationContent("REQ-101", "").body,
    "تم رفض هذا الطلب نهائيًا بعد مراجعته. لا يمكن تعديله أو إعادة إرساله. يمكنك تقديم طلب جديد أو التواصل مع الدعم الفني لمعرفة المزيد.",
  );
});
