const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

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

function channelsForType(type) {
  return {
    inApp: true,
    push: type !== "draftSaved",
  };
}

function notificationPayload({
  uid,
  contractId,
  title,
  body,
  type,
  priority = "normal",
}) {
  return {
    uid,
    contractId,
    title,
    body,
    type,
    read: false,
    actionType: "contractDetails",
    actionPayload: { contractId },
    channels: channelsForType(type),
    priority,
    delivery: {
      pushStatus: "pending",
      error: "",
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
    if (!data) return;
    const uid = data.uid;
    if (!uid) return;

    const status = data.status || "awaitingPayment";
    const type =
      status === "draft"
        ? "draftSaved"
        : status === "awaitingPayment"
          ? "awaitingPayment"
          : "processing";
    const title =
      status === "draft"
        ? "تم حفظ المسودة"
        : status === "awaitingPayment"
          ? "تم إنشاء طلب العقد"
          : "طلبك قيد المعالجة";
    const body =
      status === "draft"
        ? `تم حفظ مسودة ${data.title || "العقد"} ويمكنك إكمالها لاحقًا.`
        : status === "awaitingPayment"
          ? `تم إنشاء طلب ${data.title || "العقد"}. ادفع الرسوم للمتابعة إلى قيد المعالجة.`
          : `طلب ${data.title || "العقد"} قيد المعالجة لدى الفريق.`;

    await db.collection("notifications").add(
      notificationPayload({
        uid,
        contractId: event.params.contractId,
        title,
        body,
        type,
        priority: status === "draft" ? "low" : "high",
      }),
    );
  },
);

exports.dispatchNotification = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    const snapshot = event.data;
    const notification = snapshot && snapshot.data();
    if (!notification) return;
    if (notification.sentAt) return;
    notification.id = event.params.notificationId;

    const notificationRef = snapshot.ref;
    const uid = notification.uid;
    if (!uid) return;

    const userSnap = await db.collection("users").doc(uid).get();
    const user = userSnap.data() || {};
    const prefs = user.notificationPrefs || {};
    const channels = notification.channels || {};
    const delivery = {};

    if (channels.push !== false && prefs.push !== false) {
      delivery.pushStatus = await sendPush(uid, notification);
    } else {
      delivery.pushStatus = "skipped";
    }

    await notificationRef.set(
      {
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        delivery: {
          ...notification.delivery,
          ...delivery,
          error: "",
        },
      },
      { merge: true },
    );
  },
);

async function sendPush(uid, notification) {
  const tokensSnap = await db
    .collection("users")
    .doc(uid)
    .collection("fcmTokens")
    .where("active", "==", true)
    .get();
  const tokens = tokensSnap.docs
    .map((doc) => doc.data().token)
    .filter((token) => typeof token === "string" && token.length > 0);
  if (tokens.length === 0) return "skipped";

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
    return response.failureCount > 0 ? "partial" : "sent";
  } catch (error) {
    logger.error("Push delivery failed", error);
    return "failed";
  }
}
