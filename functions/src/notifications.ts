import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";

const db = getFirestore();
const messaging = getMessaging();

type NotificationInput = {
  uid: string;
  type: string;
  title: string;
  body: string;
  targetRoute?: string | null;
  councilId?: string | null;
  commentId?: string | null;
  conversationId?: string | null;
  messageId?: string | null;
};

const cleanData = (
  input: NotificationInput,
  notificationId: string,
): Record<string, string> => {
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

export const createUserNotification = async (
  input: NotificationInput,
): Promise<string> => {
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
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await sendPushToUser(input, notificationRef.id);
  return notificationRef.id;
};

export const sendPushToUser = async (
  input: NotificationInput,
  notificationId: string,
): Promise<void> => {
  const tokensSnapshot = await db
    .collection("users")
    .doc(input.uid)
    .collection("fcmTokens")
    .where("enabled", "==", true)
    .limit(100)
    .get();

  const tokens = tokensSnapshot.docs
    .map((doc) => doc.data().token)
    .filter((token): token is string => typeof token === "string" && !!token);

  if (tokens.length === 0) return;

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

  await Promise.all(
    response.responses.map(async (item, index) => {
      const code = item.error?.code;
      if (!code || !invalidTokenCodes.has(code)) return;

      await tokensSnapshot.docs[index].ref.set(
        {
          enabled: false,
          disabledAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }),
  );
};