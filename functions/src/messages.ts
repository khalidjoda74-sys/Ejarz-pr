import {getFirestore} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {createUserNotification} from "./notifications";

const db = getFirestore();

const safeString = (value: unknown, fallback = ""): string => {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
};

const stringList = (value: unknown): string[] => {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => safeString(item))
    .filter((item) => item.length > 0);
};

const objectValue = (value: unknown): Record<string, unknown> => {
  return value !== null && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
};

const messageSnippet = (value: string): string => {
  const cleaned = value.replace(/\s+/g, " ").trim();
  if (!cleaned) return "وصلتك رسالة جديدة.";
  return cleaned.length > 120 ? `${cleaned.slice(0, 117)}...` : cleaned;
};

export const notifyNewConversationMessage = onDocumentCreated(
  {
    region: "us-central1",
    document: "conversations/{conversationId}/messages/{messageId}",
  },
  async (event): Promise<void> => {
    const messageSnap = event.data;
    if (!messageSnap) return;

    const {conversationId, messageId} = event.params;
    const message = messageSnap.data() ?? {};
    const senderId = safeString(message.senderId);
    const text = safeString(message.text);

    if (!senderId || !text) return;

    const conversationSnap = await db
      .collection("conversations")
      .doc(conversationId)
      .get();

    if (!conversationSnap.exists) return;

    const conversation = conversationSnap.data() ?? {};
    const participantIds = stringList(conversation.participantIds);
    if (!participantIds.includes(senderId)) return;

    const receiverIds = participantIds.filter((uid) => uid !== senderId);
    if (receiverIds.length === 0) return;

    const councilId = safeString(conversation.councilId);
    const contextType = safeString(
      conversation.contextType,
      councilId ? "opportunity" : "direct",
    );
    const direct = contextType === "direct";
    const councilTitle = safeString(conversation.councilTitle, "فرصة");
    const participantSnapshots = objectValue(conversation.participantSnapshots);
    const senderSnapshot = objectValue(participantSnapshots[senderId]);
    const senderName = safeString(
      senderSnapshot.displayName,
      "عضو Forsa Pro",
    );
    const targetRoute = `/conversation/${conversationId}`;
    const title = direct ?
      `رسالة جديدة من ${senderName}` :
      `رسالة جديدة عن: ${councilTitle}`;
    const body = messageSnippet(text);

    await Promise.all(
      receiverIds.map((uid) =>
        createUserNotification({
          uid,
          type: "message",
          title,
          body,
          targetRoute,
          councilId: direct || !councilId ? null : councilId,
          conversationId,
          messageId,
        }),
      ),
    );
  },
);
