const admin = require("firebase-admin");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const {
  adminHasPermission,
  notificationId,
  retryDelayMinutes,
  isDraftSubmissionTransition,
  rejectionNotificationContent,
} = require("./notification_policy");

admin.initializeApp();

const db = admin.firestore();
function normalizeSaudiMobile(value) {
  let digits = String(value || "").replace(/\D/g, "");
  if (digits.startsWith("00966")) {
    digits = digits.slice(5);
  } else if (digits.startsWith("966")) {
    digits = digits.slice(3);
  }
  if (digits.startsWith("05")) {
    digits = digits.slice(1);
  }
  if (!/^5\d{8}$/.test(digits)) {
    throw new HttpsError("invalid-argument", "رقم الجوال غير صحيح");
  }
  return `+966${digits}`;
}

function normalizeCallablePhone(request) {
  return normalizeSaudiMobile(
    request.data?.phoneE164 ||
      request.data?.phone ||
      request.auth?.token?.phone_number ||
      "",
  );
}

function assertSignedIn(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول أولًا");
  }
  return request.auth.uid;
}

function assertVerifiedPhoneMatches(request, phone) {
  const tokenPhone = request.auth?.token?.phone_number;
  if (!tokenPhone) return;
  if (normalizeSaudiMobile(tokenPhone) !== phone) {
    throw new HttpsError("permission-denied", "رقم الجوال لا يطابق جلسة التحقق");
  }
}

function isBlockedStatus(status) {
  return status === "blocked" || status === "suspended";
}

async function authUserForPhone(phone) {
  try {
    return await admin.auth().getUserByPhoneNumber(phone);
  } catch (error) {
    if (error?.code === "auth/user-not-found") return null;
    logger.error("Failed to read Firebase Auth user by phone", error);
    throw new HttpsError("internal", "تعذر التحقق من رقم الجوال الآن");
  }
}

async function phoneProfileState(phone) {
  const authUser = await authUserForPhone(phone);
  let profileSnap = null;
  if (authUser) {
    const snap = await db.collection("users").doc(authUser.uid).get();
    if (snap.exists) profileSnap = snap;
  }
  if (!profileSnap) {
    const byPhone = await db
      .collection("users")
      .where("phone", "==", phone)
      .limit(1)
      .get();
    if (!byPhone.empty) profileSnap = byPhone.docs[0];
  }
  const profile = profileSnap?.exists ? profileSnap.data() || {} : null;
  return {
    phone,
    authUid: authUser?.uid || "",
    uid: profileSnap?.id || authUser?.uid || "",
    registered: Boolean(profileSnap?.exists),
    status: profile?.status || "active",
    blocked: isBlockedStatus(profile?.status),
  };
}

function cleanProfileName(value) {
  const name = String(value || "").trim();
  if (name.length < 3) {
    throw new HttpsError("invalid-argument", "أدخل الاسم الكامل");
  }
  return name;
}

function cleanProfileEmail(value) {
  const email = String(value || "").trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "أدخل بريدًا إلكترونيًا صحيحًا");
  }
  return email;
}

exports.checkPhoneRegistration = onCall(async (request) => {
  const phone = normalizeCallablePhone(request);
  return phoneProfileState(phone);
});

exports.finalizePhoneRegistration = onCall(async (request) => {
  const uid = assertSignedIn(request);
  const phone = normalizeCallablePhone(request);
  assertVerifiedPhoneMatches(request, phone);

  const name = cleanProfileName(request.data?.name);
  const email = cleanProfileEmail(request.data?.email);
  const authUser = await authUserForPhone(phone);
  if (authUser && authUser.uid !== uid) {
    throw new HttpsError("already-exists", "الرقم موجود من قبل، استخدم تسجيل الدخول");
  }

  const users = db.collection("users");
  const [profileSnap, byPhone] = await Promise.all([
    users.doc(uid).get(),
    users.where("phone", "==", phone).limit(1).get(),
  ]);
  if (profileSnap.exists || !byPhone.empty) {
    throw new HttpsError("already-exists", "الرقم موجود من قبل، استخدم تسجيل الدخول");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  await users.doc(uid).set({
    uid,
    phone,
    name,
    email,
    role: "customer",
    status: "active",
    notesFromAdmin: "",
    notificationPrefs: { inApp: true, push: true },
    stats: { contractsCount: 0, completedContractsCount: 0 },
    createdAt: now,
    lastLoginAt: now,
    updatedAt: now,
  });
  return { uid, phone, name, email, status: "active" };
});

exports.finalizePhoneLogin = onCall(async (request) => {
  const uid = assertSignedIn(request);
  const phone = normalizeCallablePhone(request);
  assertVerifiedPhoneMatches(request, phone);

  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    const byPhone = await db
      .collection("users")
      .where("phone", "==", phone)
      .limit(1)
      .get();
    if (!byPhone.empty) {
      throw new HttpsError(
        "failed-precondition",
        "الرقم مرتبط بحساب يحتاج مراجعة الدعم",
      );
    }
    throw new HttpsError("not-found", "الرقم غير مسجل، أنشئ حسابًا جديدًا أولًا");
  }

  const profile = snap.data() || {};
  if (isBlockedStatus(profile.status)) {
    throw new HttpsError("permission-denied", "هذا الحساب موقوف، تواصل مع الدعم");
  }

  await ref.set(
    {
      phone,
      lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return {
    uid,
    phone,
    name: profile.name || "",
    email: profile.email || "",
    status: profile.status || "active",
  };
});

const USER_OWNED_COLLECTIONS = [
  "contracts",
  "properties",
  "notifications",
  "supportTickets",
  "payments",
  "invoices",
];

function chunks(values, size = 30) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

async function ownedDocumentRefs(collectionName, uid) {
  const snapshots = await Promise.all([
    db.collection(collectionName).where("uid", "==", uid).get(),
    db.collection(collectionName).where("userId", "==", uid).get(),
  ]);
  const refs = new Map();
  for (const snapshot of snapshots) {
    for (const document of snapshot.docs) {
      refs.set(document.ref.path, document.ref);
    }
  }
  return [...refs.values()];
}

async function refsMatchingValues(collectionName, field, values) {
  const uniqueValues = [...new Set(values.filter(Boolean))];
  if (uniqueValues.length === 0) return [];
  const refs = new Map();
  for (const group of chunks(uniqueValues)) {
    const snapshot = await db
      .collection(collectionName)
      .where(field, "in", group)
      .get();
    for (const document of snapshot.docs) {
      refs.set(document.ref.path, document.ref);
    }
  }
  return [...refs.values()];
}

async function deleteDocumentTrees(refs) {
  for (const group of chunks(refs, 5)) {
    await Promise.all(group.map((ref) => db.recursiveDelete(ref)));
  }
}

async function deleteStoragePrefix(bucket, prefix) {
  await bucket.deleteFiles({ prefix, force: true });
}

/**
 * Permanently deletes the signed-in customer's account and associated data.
 *
 * Authentication is deleted last so a partial infrastructure failure can be
 * retried by the same verified customer session without support intervention.
 */
exports.deleteOwnAccount = onCall(
  { timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    const uid = assertSignedIn(request);
    if (request.data?.confirmation !== "DELETE_ACCOUNT") {
      throw new HttpsError(
        "invalid-argument",
        "يلزم تأكيد حذف الحساب والبيانات المرتبطة به",
      );
    }

    const adminUser = await db.collection("adminUsers").doc(uid).get();
    if (adminUser.exists) {
      throw new HttpsError(
        "failed-precondition",
        "لا يمكن حذف حسابات الإدارة من تطبيق العملاء",
      );
    }

    try {
      const ownedEntries = await Promise.all(
        USER_OWNED_COLLECTIONS.map(async (collectionName) => [
          collectionName,
          await ownedDocumentRefs(collectionName, uid),
        ]),
      );
      const owned = Object.fromEntries(ownedEntries);
      const contractIds = owned.contracts.map((ref) => ref.id);
      const propertyIds = owned.properties.map((ref) => ref.id);
      const ticketIds = owned.supportTickets.map((ref) => ref.id);
      const paymentIds = owned.payments.map((ref) => ref.id);
      const invoiceIds = owned.invoices.map((ref) => ref.id);

      const bucket = admin.storage().bucket();
      await Promise.all([
        deleteStoragePrefix(bucket, `users/${uid}/`),
        ...contractIds.map((contractId) =>
          deleteStoragePrefix(bucket, `contracts/${contractId}/`),
        ),
      ]);

      const indirectRefs = new Map();
      const indirectMatches = await Promise.all([
        refsMatchingValues("adminNotifications", "entityId", [
          ...contractIds,
          ...ticketIds,
          ...paymentIds,
          ...invoiceIds,
        ]),
        refsMatchingValues(
          "adminNotifications",
          "actionPayload.contractId",
          contractIds,
        ),
        refsMatchingValues(
          "adminNotifications",
          "actionPayload.ticketId",
          ticketIds,
        ),
        refsMatchingValues(
          "adminNotifications",
          "actionPayload.paymentId",
          paymentIds,
        ),
        refsMatchingValues("auditLogs", "entityId", [
          uid,
          ...contractIds,
          ...propertyIds,
          ...ticketIds,
          ...paymentIds,
          ...invoiceIds,
        ]),
        refsMatchingValues("auditLogs", "targetId", [uid]),
      ]);
      for (const refs of indirectMatches) {
        for (const ref of refs) indirectRefs.set(ref.path, ref);
      }

      await deleteDocumentTrees([
        ...Object.values(owned).flat(),
        ...indirectRefs.values(),
      ]);
      await db.recursiveDelete(db.collection("users").doc(uid));
      await admin.auth().deleteUser(uid);

      logger.info("Customer account deletion completed", {
        deletedDocumentRoots: Object.values(owned)
          .reduce((total, refs) => total + refs.length, 0),
        deletedContractStorageRoots: contractIds.length,
      });
      return { deleted: true };
    } catch (error) {
      logger.error("Customer account deletion failed", {
        code: error?.code || "unknown",
      });
      throw new HttpsError(
        "internal",
        "تعذر إكمال حذف الحساب الآن. لم يُغلق الحساب ويمكن إعادة المحاولة.",
      );
    }
  },
);

function channelsForType(type) {
  return {
    inApp: true,
    push: type !== "draftSaved",
  };
}

function notificationPayload({
  uid,
  contractId = "",
  title,
  body,
  type,
  priority = "normal",
  eventKey,
  entityType = "contract",
  entityId = contractId,
  actionType = "contractDetails",
  actionPayload,
}) {
  return {
    uid,
    userId: uid,
    contractId,
    title,
    body,
    type,
    eventKey,
    audience: "customer",
    entityType,
    entityId,
    read: false,
    actionType,
    actionPayload: actionPayload || { contractId },
    channels: channelsForType(type),
    priority,
    delivery: {
      pushStatus: "pending",
      attempts: 0,
      error: "",
      lastAttemptAt: null,
      nextAttemptAt: null,
      lockedAt: null,
    },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    readAt: null,
    sentAt: null,
  };
}

exports.createContractSubmittedNotification = onDocumentCreated(
  "contracts/{contractId}",
  async (event) => {
    const data = event.data && event.data.data();
    if (!data || data.status === "draft") return;
    const uid = cleanText(data.uid || data.userId);
    if (!uid) return;
    const contractId = event.params.contractId;
    const requestNumber = contractNumber(data, contractId);
    if (data.status === "rejected") {
      const rejection = rejectionNotificationContent(
        requestNumber,
        data.rejectionReason || data.customerVisibleNote,
      );
      await createCustomerNotification({
        eventKey: `contract.created.rejected:${event.id}`,
        uid,
        contractId,
        title: rejection.title,
        body: rejection.body,
        type: "rejected",
        priority: "high",
      });
      return;
    }
    await Promise.all([
      createCustomerNotification({
        eventKey: `contract.created:${event.id}`,
        uid,
        contractId,
        title: "تم استلام طلب العقد",
        body: `استلمنا طلبك رقم ${requestNumber} بنجاح. أكمل سداد الرسوم لبدء المعالجة.`,
        type: "contractSubmitted",
        priority: "high",
      }),
      data.isDemo === true
        ? Promise.resolve(false)
        : createAdminNotifications({
          eventKey: `admin.contract.created:${event.id}`,
          permission: "contracts.read",
          contract: { id: contractId, ...data },
          title: "طلب عقد جديد",
          body: `أرسل ${customerName(data)} الطلب رقم ${requestNumber}. افتح الطلب لمراجعته.`,
          type: "contractSubmitted",
          priority: "high",
          actionType: "contractDetails",
          actionPayload: { contractId },
          preferAssigned: false,
        }),
    ]);
  },
);

exports.dispatchNotification = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    if (!event.data) return;
    await deliverNotification(event.data.ref);
  },
);

async function sendPush(uid, notification) {
  const tokensSnap = await db
    .collection("users")
    .doc(uid)
    .collection("fcmTokens")
    .where("active", "==", true)
    .get();
  const tokenDocs = tokensSnap.docs.filter((doc) => cleanText(doc.data().token));
  const tokens = tokenDocs.map((doc) => doc.data().token);
  if (tokens.length === 0) return { status: "skipped", retryable: false };

  try {
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: notification.title || "تنبيه",
        body: notification.body || "",
      },
      data: {
        notificationId: notification.id || "",
        contractId: notification.contractId || "",
        ticketId: cleanText(notification.actionPayload?.ticketId),
        paymentId: cleanText(notification.actionPayload?.paymentId),
        actionType: notification.actionType || "",
        type: notification.type || "general",
      },
      android: {
        priority: notification.priority === "high" ? "high" : "normal",
        notification: {
          channelId: "contracts_high_importance",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });
    const invalidCodes = new Set([
      "messaging/invalid-registration-token",
      "messaging/registration-token-not-registered",
    ]);
    const invalidWrites = [];
    let transientFailures = 0;
    response.responses.forEach((item, index) => {
      if (item.success) return;
      const code = item.error?.code || "";
      if (invalidCodes.has(code)) {
        invalidWrites.push(tokenDocs[index].ref.set({
          active: false,
          disabledReason: code,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }));
      } else {
        transientFailures += 1;
      }
    });
    await Promise.all(invalidWrites);
    if (response.successCount > 0) {
      return {
        status: response.failureCount > 0 ? "partial" : "sent",
        retryable: false,
      };
    }
    return {
      status: "failed",
      retryable: transientFailures > 0,
      error: transientFailures > 0
        ? "تعذر تسليم الإشعار مؤقتًا إلى جميع الأجهزة."
        : "لا توجد رموز أجهزة صالحة للتسليم.",
    };
  } catch (error) {
    logger.error("Push delivery failed", error);
    return {
      status: "failed",
      retryable: true,
      error: cleanText(error?.message) || "تعذر إرسال الإشعار.",
    };
  }
}

function cleanText(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function clippedText(value, fallback = "", maxLength = 280) {
  const text = cleanText(value, fallback);
  return text.length <= maxLength ? text : `${text.slice(0, maxLength - 1)}…`;
}

function contractNumber(data, fallback) {
  return cleanText(data?.requestNumber || data?.orderNumber, fallback);
}

function customerName(data) {
  return cleanText(data?.customerName, "عميل");
}

function money(value) {
  const amount = Number(value || 0);
  return Number.isFinite(amount) ? amount.toLocaleString("ar-SA") : "0";
}

function shortId(value, prefix) {
  const raw = cleanText(value);
  return raw ? `${prefix}-${raw.slice(0, 8).toUpperCase()}` : prefix;
}

async function createCustomerNotification(input) {
  const uid = cleanText(input.uid);
  if (!uid) return false;
  const eventKey = cleanText(input.eventKey);
  const ref = db.collection("notifications").doc(notificationId(eventKey, uid));
  return db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return false;
    transaction.create(ref, notificationPayload({
      uid,
      contractId: cleanText(input.contractId),
      title: clippedText(input.title, "تنبيه", 100),
      body: clippedText(input.body, "لديك تحديث جديد.", 500),
      type: cleanText(input.type, "general"),
      priority: input.priority || "normal",
      eventKey,
      entityType: cleanText(input.entityType, input.contractId ? "contract" : "general"),
      entityId: cleanText(input.entityId, input.contractId),
      actionType: cleanText(input.actionType, input.contractId ? "contractDetails" : ""),
      actionPayload: input.actionPayload ||
        (input.contractId ? { contractId: input.contractId } : {}),
    }));
    return true;
  });
}

async function eligibleAdmins(permission) {
  const snapshot = await db.collection("adminUsers").where("active", "==", true).get();
  return snapshot.docs.filter((doc) => adminHasPermission(doc.data(), permission));
}

async function createAdminNotifications({
  eventKey,
  permission,
  contract,
  title,
  body,
  type,
  priority = "normal",
  actionType,
  actionPayload = {},
  preferAssigned = false,
}) {
  const admins = await eligibleAdmins(permission);
  if (admins.length === 0) return 0;
  let recipients = admins;
  if (preferAssigned && contract) {
    const assignedUid = cleanText(
      contract.assignedAdminUid || contract.adminAssignedTo,
    );
    const assigned = admins.find((doc) => doc.id === assignedUid);
    if (assigned) recipients = [assigned];
  }
  const batch = db.batch();
  for (const recipient of recipients) {
    const ref = db.collection("adminNotifications")
      .doc(notificationId(eventKey, recipient.id));
    batch.create(ref, {
      eventKey,
      audience: "admin",
      recipientUid: recipient.id,
      requiredPermission: permission,
      entityType: contract ? "contract" : type,
      entityId: cleanText(
        actionPayload.contractId || actionPayload.ticketId || actionPayload.paymentId,
      ),
      contractId: cleanText(actionPayload.contractId),
      title: clippedText(title, "تنبيه إداري", 100),
      body: clippedText(body, "يوجد حدث جديد يحتاج إلى المتابعة.", 500),
      type,
      priority,
      actionType,
      actionPayload,
      read: false,
      readAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  try {
    await batch.commit();
    return recipients.length;
  } catch (error) {
    if (error?.code === 6 || error?.code === "already-exists") return 0;
    throw error;
  }
}

function allRequirementsResolved(before, after) {
  const oldItems = Array.isArray(before?.missingRequirements)
    ? before.missingRequirements
    : [];
  const newItems = Array.isArray(after?.missingRequirements)
    ? after.missingRequirements
    : [];
  return oldItems.some((item) => item?.resolved !== true) &&
    newItems.length > 0 && newItems.every((item) => item?.resolved === true);
}

exports.notifyContractUpdated = onDocumentUpdated(
  "contracts/{contractId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    // Demo payment completion already writes one compatible customer
    // notification in the client batch. Keep other demo contract events
    // visible while avoiding a duplicate completion notification.
    if (after.isDemo === true &&
        after.isDemoPayment === true &&
        after.status === "authenticated" &&
        before.status !== after.status) return;
    const uid = cleanText(after.uid || after.userId);
    if (!uid) return;
    const contractId = event.params.contractId;
    const requestNumber = contractNumber(after, contractId);

    if (isDraftSubmissionTransition(before, after)) {
      await Promise.all([
        createCustomerNotification({
          eventKey: `contract.draft.submitted:${event.id}`,
          uid,
          contractId,
          title: "تم استلام طلب العقد",
          body: `استلمنا طلبك رقم ${requestNumber} بنجاح. أكمل سداد الرسوم لبدء المعالجة.`,
          type: "contractSubmitted",
          priority: "high",
        }),
        after.isDemo === true
          ? Promise.resolve(false)
          : createAdminNotifications({
            eventKey: `admin.contract.draft.submitted:${event.id}`,
            permission: "contracts.read",
            contract: { id: contractId, ...after },
            title: "طلب عقد جديد",
            body: `أرسل ${customerName(after)} الطلب رقم ${requestNumber}. افتح الطلب لمراجعته.`,
            type: "contractSubmitted",
            priority: "high",
            actionType: "contractDetails",
            actionPayload: { contractId },
            preferAssigned: false,
          }),
      ]);
      return;
    }

    if (allRequirementsResolved(before, after)) {
      if (cleanText(after.notificationContext).startsWith("missingResponseAccepted:")) {
        return;
      }
      await createCustomerNotification({
        eventKey: `contract.missing.accepted:${event.id}`,
        uid,
        contractId,
        title: "تم اعتماد البيانات المستكملة",
        body: `اعتمد الفريق البيانات المرسلة للطلب رقم ${requestNumber} واستؤنفت معالجة الطلب.`,
        type: "missingResponseAccepted",
        priority: "normal",
      });
      return;
    }

    const finalPdfAdded = !cleanText(before.finalPdfUrl) && cleanText(after.finalPdfUrl);
    const statusChanged = before.status !== after.status;
    if (!statusChanged && !finalPdfAdded) return;
    const status = cleanText(after.status);
    if (status === "draft") return;

    let message;
    if (status === "authenticated" && cleanText(after.finalPdfUrl)) {
      message = {
        title: "تم إصدار العقد النهائي",
        body: `اكتمل الطلب رقم ${requestNumber} وأصبح العقد النهائي جاهزًا للعرض والتحميل.`,
        type: "finalContractReady",
        priority: "high",
      };
    } else if (status === "awaitingPayment") {
      message = {
        title: "طلبك جاهز للدفع",
        body: `الطلب رقم ${requestNumber} جاهز للدفع. المبلغ المستحق ${money(after.totalPayable || after.totalFees || 398)} ر.س.`,
        type: "paymentRequired",
        priority: "high",
      };
    } else if (status === "processing") {
      message = {
        title: "بدأت معالجة طلبك",
        body: `يعمل فريقنا الآن على مراجعة الطلب رقم ${requestNumber} وإكمال إجراءاته.`,
        type: "processing",
        priority: "normal",
      };
    } else if (status === "missingData") {
      const note = clippedText(
        after.customerVisibleNote,
        "يوجد نقص مطلوب لاستكمال معالجة الطلب",
        260,
      );
      message = {
        title: "مطلوب استكمال بيانات",
        body: `يلزم استكمال بيانات الطلب رقم ${requestNumber}: ${note}. افتح الطلب لإرسال المطلوب.`,
        type: "missingRequirement",
        priority: "high",
      };
    } else if (status === "rejected") {
      const rejection = rejectionNotificationContent(
        requestNumber,
        after.rejectionReason || after.customerVisibleNote,
      );
      message = {
        title: rejection.title,
        body: rejection.body,
        type: "rejected",
        priority: "high",
      };
    }
    if (!message) return;
    await createCustomerNotification({
      eventKey: `contract.status.${status}:${event.id}`,
      uid,
      contractId,
      ...message,
    });
  },
);

async function contractForId(contractId) {
  if (!contractId) return null;
  const snapshot = await db.collection("contracts").doc(contractId).get();
  return snapshot.exists ? { id: snapshot.id, ...snapshot.data() } : null;
}

async function handlePaymentEvent(event, beforeData) {
  const payment = event.data?.after ? event.data.after.data() : event.data?.data();
  if (!payment) return;
  const previousStatus = beforeData?.status;
  const status = cleanText(payment.status);
  if (!status || status === "pending" || previousStatus === status) return;
  const uid = cleanText(payment.uid || payment.userId);
  const paymentId = event.params.paymentId;
  const contractId = cleanText(payment.contractId);
  const contract = await contractForId(contractId);
  const requestNumber = contractNumber(contract || {}, contractId || "-");
  const amount = money(payment.amount);
  const actionPayload = { paymentId, contractId };
  const templates = {
    paid: {
      customerTitle: "تم استلام الدفعة",
      customerBody: `تم استلام مبلغ ${amount} ر.س للطلب رقم ${requestNumber} بنجاح، وبدأت معالجة الطلب.`,
      adminTitle: "تم سداد دفعة",
      adminBody: `تم سداد ${amount} ر.س للطلب رقم ${requestNumber} بواسطة ${cleanText(payment.method, "وسيلة الدفع المحددة")}.`,
      priority: "high",
    },
    failed: {
      customerTitle: "تعذر إتمام الدفع",
      customerBody: `لم تكتمل دفعة الطلب رقم ${requestNumber}. حاول مرة أخرى أو استخدم وسيلة دفع أخرى.`,
      adminTitle: "فشلت عملية دفع",
      adminBody: `تعذر سداد ${amount} ر.س للطلب رقم ${requestNumber}.`,
      priority: "high",
    },
    cancelled: {
      customerTitle: "أُلغيت عملية الدفع",
      customerBody: `أُلغيت عملية الدفع الخاصة بالطلب رقم ${requestNumber} ولم يتم خصم المبلغ.`,
      adminTitle: "أُلغيت عملية دفع",
      adminBody: `أُلغيت دفعة الطلب رقم ${requestNumber} بقيمة ${amount} ر.س.`,
      priority: "normal",
    },
    refunded: {
      customerTitle: "تم استرداد المبلغ",
      customerBody: `تم تسجيل استرداد مبلغ ${amount} ر.س للطلب رقم ${requestNumber}، وستظهر العملية وفق مدة المعالجة البنكية.`,
      adminTitle: "تم استرداد دفعة",
      adminBody: `تم تسجيل استرداد ${amount} ر.س للطلب رقم ${requestNumber}.`,
      priority: "high",
    },
  };
  const template = templates[status];
  if (!template) return;
  const writes = [
    createAdminNotifications({
      eventKey: `admin.payment.${status}:${event.id}`,
      permission: "payments.read",
      title: template.adminTitle,
      body: template.adminBody,
      type: `payment.${status}`,
      priority: template.priority,
      actionType: "paymentDetails",
      actionPayload,
    }),
  ];
  // The demo flow writes its completion notification in the same client batch
  // for compatibility with already released clients. Other payment outcomes are
  // server-owned.
  if (!(payment.isDemo === true && status === "paid") && uid) {
    writes.push(createCustomerNotification({
      eventKey: `payment.${status}:${event.id}`,
      uid,
      contractId,
      entityType: "payment",
      entityId: paymentId,
      actionType: "payments",
      actionPayload,
      title: template.customerTitle,
      body: template.customerBody,
      type: `payment.${status}`,
      priority: template.priority,
    }));
  }
  await Promise.all(writes);
}

exports.notifyPaymentCreated = onDocumentCreated(
  "payments/{paymentId}",
  async (event) => handlePaymentEvent(event),
);

exports.notifyPaymentUpdated = onDocumentUpdated(
  "payments/{paymentId}",
  async (event) => handlePaymentEvent(event, event.data?.before.data()),
);

exports.notifyMissingResponseCreated = onDocumentCreated(
  "contracts/{contractId}/missingResponses/{responseId}",
  async (event) => {
    const response = event.data?.data();
    if (!response) return;
    const contractId = event.params.contractId;
    const contract = await contractForId(contractId);
    if (!contract) return;
    const uid = cleanText(response.uid || response.userId || contract.uid || contract.userId);
    const requestNumber = contractNumber(contract, contractId);
    const requirementTitle = cleanText(
      response.missingRequirementTitle,
      "المتطلبات المطلوبة",
    );
    await Promise.all([
      createCustomerNotification({
        eventKey: `missing.response.created:${event.id}`,
        uid,
        contractId,
        title: "تم إرسال الاستكمال",
        body: `استلمنا ردك على متطلبات الطلب رقم ${requestNumber} وسيتم مراجعته من الفريق.`,
        type: "missingResponseSubmitted",
        priority: "normal",
      }),
      createAdminNotifications({
        eventKey: `admin.missing.response.created:${event.id}`,
        permission: "contracts.read",
        contract,
        title: "وصل استكمال من العميل",
        body: `أرسل ${customerName(contract)} استكمالًا للطلب رقم ${requestNumber} بشأن ${requirementTitle}.`,
        type: "missingResponseSubmitted",
        priority: "high",
        actionType: "contractDetails",
        actionPayload: { contractId },
        preferAssigned: true,
      }),
    ]);
  },
);

exports.notifyMissingResponseReviewed = onDocumentUpdated(
  "contracts/{contractId}/missingResponses/{responseId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    if (after.status !== "accepted" && after.status !== "returned") return;
    const contractId = event.params.contractId;
    const contract = await contractForId(contractId);
    if (!contract) return;
    const uid = cleanText(after.uid || after.userId || contract.uid || contract.userId);
    const requestNumber = contractNumber(contract, contractId);
    const accepted = after.status === "accepted";
    const reason = clippedText(
      after.reviewNote || after.returnReason,
      "يرجى مراجعة البيانات المرسلة واستكمال المطلوب",
      260,
    );
    await createCustomerNotification({
      eventKey: `missing.response.${after.status}:${event.id}`,
      uid,
      contractId,
      title: accepted ? "تم اعتماد البيانات المستكملة" : "مطلوب تعديل الاستكمال",
      body: accepted
        ? contract.status === "processing"
          ? `اعتمد الفريق البيانات المرسلة للطلب رقم ${requestNumber} واستؤنفت معالجة الطلب.`
          : `اعتمد الفريق البيانات المرسلة للطلب رقم ${requestNumber}، وما زالت هناك متطلبات أخرى يلزم استكمالها.`
        : `تحتاج البيانات المرسلة للطلب رقم ${requestNumber} إلى تعديل: ${reason}.`,
      type: accepted ? "missingResponseAccepted" : "missingResponseReturned",
      priority: accepted ? "normal" : "high",
    });
  },
);

exports.notifySupportTicketCreated = onDocumentCreated(
  "supportTickets/{ticketId}",
  async (event) => {
    const ticket = event.data?.data();
    if (!ticket) return;
    const uid = cleanText(ticket.uid || ticket.userId);
    const ticketId = event.params.ticketId;
    const ticketNumber = cleanText(ticket.ticketNumber, shortId(ticketId, "SUP"));
    const actionPayload = {
      ticketId,
      contractId: cleanText(ticket.contractId),
    };
    await Promise.all([
      createCustomerNotification({
        eventKey: `support.created:${event.id}`,
        uid,
        contractId: cleanText(ticket.contractId),
        entityType: "supportTicket",
        entityId: ticketId,
        actionType: "supportTicket",
        actionPayload,
        title: "تم استلام طلب الدعم",
        body: `تم فتح التذكرة رقم ${ticketNumber} وسيرد عليك فريق الدعم في أقرب وقت.`,
        type: "supportTicketCreated",
        priority: ticket.priority === "high" ? "high" : "normal",
      }),
      createAdminNotifications({
        eventKey: `admin.support.created:${event.id}`,
        permission: "support.read",
        title: "تذكرة دعم جديدة",
        body: `فتح ${customerName(ticket)} التذكرة رقم ${ticketNumber}: ${clippedText(ticket.subject, "طلب دعم", 180)}.`,
        type: "supportTicketCreated",
        priority: ticket.priority === "high" ? "high" : "normal",
        actionType: "supportTicket",
        actionPayload,
      }),
    ]);
  },
);

exports.notifySupportTicketUpdated = onDocumentUpdated(
  "supportTickets/{ticketId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const uid = cleanText(after.uid || after.userId);
    if (!uid) return;
    const ticketId = event.params.ticketId;
    const ticketNumber = cleanText(after.ticketNumber, shortId(ticketId, "SUP"));
    const actionPayload = {
      ticketId,
      contractId: cleanText(after.contractId),
    };
    const oldReplyIds = new Set((before.replies || []).map((reply) => reply?.id));
    const newReplies = (after.replies || []).filter((reply) =>
      reply && !oldReplyIds.has(reply.id) && reply.visibility !== "admin",
    );
    if (newReplies.length > 0) {
      const reply = newReplies[newReplies.length - 1];
      await createCustomerNotification({
        eventKey: `support.reply.created:${event.id}`,
        uid,
        contractId: cleanText(after.contractId),
        entityType: "supportTicket",
        entityId: ticketId,
        actionType: "supportTicket",
        actionPayload,
        title: "رد جديد من فريق الدعم",
        body: clippedText(reply.message, "وصلك رد جديد من فريق الدعم.", 420),
        type: "supportReply",
        priority: "normal",
      });
      return;
    }
    if (before.status === after.status) return;
    const templates = {
      open: {
        title: "أُعيد فتح طلب الدعم",
        body: `أُعيد فتح التذكرة رقم ${ticketNumber} ويعمل الفريق على متابعتها.`,
        type: "supportReopened",
      },
      resolved: {
        title: "تم حل طلب الدعم",
        body: `تم حل التذكرة رقم ${ticketNumber}. يمكنك فتح طلب جديد إذا احتجت إلى مساعدة إضافية.`,
        type: "supportResolved",
      },
      closed: {
        title: "تم إغلاق طلب الدعم",
        body: `تم إغلاق التذكرة رقم ${ticketNumber} بعد اكتمال المتابعة.`,
        type: "supportClosed",
      },
    };
    const template = templates[after.status];
    if (!template) return;
    await createCustomerNotification({
      eventKey: `support.status.${after.status}:${event.id}`,
      uid,
      contractId: cleanText(after.contractId),
      entityType: "supportTicket",
      entityId: ticketId,
      actionType: "supportTicket",
      actionPayload,
      title: template.title,
      body: template.body,
      type: template.type,
      priority: "normal",
    });
  },
);

exports.notifyUserStatusUpdated = onDocumentUpdated(
  "users/{uid}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    const blocked = isBlockedStatus(after.status);
    const restored = isBlockedStatus(before.status) && after.status === "active";
    if (!blocked && !restored) return;
    const uid = event.params.uid;
    const reason = clippedText(
      after.blockReason,
      "تم إيقاف الحساب وفق إجراءات حماية الخدمة.",
      260,
    );
    await createCustomerNotification({
      eventKey: `user.status.${after.status}:${event.id}`,
      uid,
      entityType: "user",
      entityId: uid,
      actionType: "profile",
      actionPayload: { uid },
      title: blocked ? "تم إيقاف الحساب مؤقتًا" : "تمت إعادة تفعيل الحساب",
      body: blocked
        ? `${reason} تواصل مع الدعم إذا كنت تحتاج إلى المساعدة.`
        : "يمكنك الآن تسجيل الدخول واستخدام جميع خدمات عقود برو.",
      type: blocked ? "accountBlocked" : "accountRestored",
      priority: "high",
    });
  },
);

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

async function claimDelivery(ref) {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;
    const data = snapshot.data() || {};
    if (data.sentAt) return null;
    const delivery = data.delivery || {};
    const attempts = Number(delivery.attempts || 0);
    if (attempts >= 5) return null;
    const lockedAt = timestampMillis(delivery.lockedAt);
    if (delivery.pushStatus === "sending" && Date.now() - lockedAt < 120000) {
      return null;
    }
    const nextAttemptAt = timestampMillis(delivery.nextAttemptAt);
    if (nextAttemptAt && nextAttemptAt > Date.now()) return null;
    transaction.set(ref, {
      delivery: {
        ...delivery,
        pushStatus: "sending",
        attempts: attempts + 1,
        lockedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
        error: "",
      },
    }, { merge: true });
    return { id: snapshot.id, ...data, attempt: attempts + 1 };
  });
}

async function deliverNotification(ref) {
  const notification = await claimDelivery(ref);
  if (!notification) return;
  const uid = cleanText(notification.uid || notification.userId);
  if (!uid) {
    await ref.set({
      delivery: {
        ...notification.delivery,
        pushStatus: "failed",
        attempts: 5,
        error: "الإشعار لا يحتوي UID صالحًا.",
        nextAttemptAt: null,
        lockedAt: null,
      },
    }, { merge: true });
    return;
  }
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.data() || {};
  const prefs = user.notificationPrefs || {};
  const channels = notification.channels || {};
  let result;
  if (channels.push === false || prefs.push === false) {
    result = { status: "skipped", retryable: false };
  } else {
    result = await sendPush(uid, notification);
  }
  const completed = ["sent", "partial", "skipped"].includes(result.status);
  const retryable = result.retryable === true && notification.attempt < 5;
  const retryMinutes = retryDelayMinutes(notification.attempt);
  await ref.set({
    sentAt: completed ? admin.firestore.FieldValue.serverTimestamp() : null,
    delivery: {
      ...notification.delivery,
      pushStatus: result.status,
      attempts: retryable ? notification.attempt :
        (completed ? notification.attempt : 5),
      error: cleanText(result.error),
      lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
      nextAttemptAt: retryable
        ? admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + retryMinutes * 60 * 1000),
        )
        : null,
      lockedAt: null,
    },
  }, { merge: true });
}

exports.retryFailedNotifications = onSchedule("every 5 minutes", async () => {
  const snapshot = await db.collection("notifications")
    .where("delivery.pushStatus", "in", ["pending", "failed"])
    .limit(100)
    .get();
  const now = Date.now();
  const candidates = snapshot.docs.filter((doc) => {
    const delivery = doc.data().delivery || {};
    return Number(delivery.attempts || 0) < 5 &&
      (!delivery.nextAttemptAt || timestampMillis(delivery.nextAttemptAt) <= now);
  });
  await Promise.all(candidates.map((doc) => deliverNotification(doc.ref)));
  logger.info(`Notification retry checked ${snapshot.size}; processed ${candidates.length}.`);
});
