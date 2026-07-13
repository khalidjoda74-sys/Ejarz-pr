"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendPushToUser = exports.createUserNotification = void 0;
const firestore_1 = require("firebase-admin/firestore");
const messaging_1 = require("firebase-admin/messaging");
const db = (0, firestore_1.getFirestore)();
const messaging = (0, messaging_1.getMessaging)();
const cleanData = (input, notificationId) => {
    return {
        type: input.type,
        title: input.title,
        body: input.body,
        notificationId,
        ifTargetRoute: input.targetRoute ?? "",
        targetRoute: input.targetRoute ?? "",
        councilId: input.councilId ?? "",
        commentId: input.commentId ?? "",
        conversationId: input.conversationId ?? "",
        messageId: input.messageId ?? "",
    };
};
const invalidTokenCodes = new Set([
    "messaging/invalid-registration-token",
    "messaging/registration-token-not-registered",
]);
const createUserNotification = async (input) => {
    const notificationRef = db
        .collection("users")
        .doc(input.uid)
        .collection("notifications")
        .doc();
    await notificationRef.set({
        type: input.type,
        title: input.title,
        body: input.body,
        read: false,
        targetRoute: input.targetRoute ?? null,
        councilId: input.councilId ?? null,
        commentId: input.commentId ?? null,
        conversationId: input.conversationId ?? null,
        messageId: input.messageId ?? null,
        iconKey: input.type,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await (0, exports.sendPushToUser)(input, notificationRef.id);
    return notificationRef.id;
};
exports.createUserNotification = createUserNotification;
const sendPushToUser = async (input, notificationId) => {
    const tokensSnapshot = await db
        .collection("users")
        .doc(input.uid)
        .collection("fcmTokens")
        .where("enabled", "==", true)
        .limit(100)
        .get();
    const tokens = tokensSnapshot.docs
        .map((doc) => doc.data().token)
        .filter((token) => typeof token === "string" && !!token);
    if (tokens.length === 0)
        return;
    const response = await messaging.sendEachForMulticast({
        tokens,
        notification: {
            title: input.title,
            body: input.body,
        },
        data: cleanData(input, notificationId),
        android: {
            notification: {
                channelId: "majalisna_activity",
                sound: "default",
            },
        },
        apns: {
            payload: {
                aps: {
                    sound: "default",
                },
            },
        },
        webpush: {
            notification: {
                title: input.title,
                body: input.body,
                icon: "/icons/Icon-192.png",
            },
            fcmOptions: {
                link: input.targetRoute ? `/#${input.targetRoute}` : "/#/main",
            },
        },
    });
    await Promise.all(response.responses.map(async (item, index) => {
        const code = item.error?.code;
        if (!code || !invalidTokenCodes.has(code))
            return;
        await tokensSnapshot.docs[index].ref.set({
            enabled: false,
            disabledAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    }));
};
exports.sendPushToUser = sendPushToUser;
//# sourceMappingURL=notifications.js.map