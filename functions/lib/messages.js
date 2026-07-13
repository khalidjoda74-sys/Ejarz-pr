"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyNewConversationMessage = void 0;
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const notifications_1 = require("./notifications");
const db = (0, firestore_1.getFirestore)();
const safeString = (value, fallback = "") => {
    return typeof value === "string" && value.trim() ? value.trim() : fallback;
};
const stringList = (value) => {
    if (!Array.isArray(value))
        return [];
    return value
        .map((item) => safeString(item))
        .filter((item) => item.length > 0);
};
const messageSnippet = (value) => {
    const cleaned = value.replace(/\s+/g, " ").trim();
    if (!cleaned)
        return "وصلتك رسالة جديدة.";
    return cleaned.length > 120 ? `${cleaned.slice(0, 117)}...` : cleaned;
};
exports.notifyNewConversationMessage = (0, firestore_2.onDocumentCreated)({
    region: "us-central1",
    document: "conversations/{conversationId}/messages/{messageId}",
}, async (event) => {
    const messageSnap = event.data;
    if (!messageSnap)
        return;
    const { conversationId, messageId } = event.params;
    const message = messageSnap.data() ?? {};
    const senderId = safeString(message.senderId);
    const text = safeString(message.text);
    if (!senderId || !text)
        return;
    const conversationSnap = await db
        .collection("conversations")
        .doc(conversationId)
        .get();
    if (!conversationSnap.exists)
        return;
    const conversation = conversationSnap.data() ?? {};
    const participantIds = stringList(conversation.participantIds);
    if (!participantIds.includes(senderId))
        return;
    const receiverIds = participantIds.filter((uid) => uid !== senderId);
    if (receiverIds.length === 0)
        return;
    const councilId = safeString(conversation.councilId);
    const councilTitle = safeString(conversation.councilTitle, "فرصة");
    const targetRoute = `/conversation/${conversationId}`;
    const title = `رسالة جديدة عن: ${councilTitle}`;
    const body = messageSnippet(text);
    await Promise.all(receiverIds.map((uid) => (0, notifications_1.createUserNotification)({
        uid,
        type: "message",
        title,
        body,
        targetRoute,
        councilId,
        conversationId,
        messageId,
    })));
});
//# sourceMappingURL=messages.js.map