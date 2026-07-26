"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteMyAccount = void 0;
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const https_1 = require("firebase-functions/v2/https");
const db = (0, firestore_1.getFirestore)();
const stringValue = (value) => {
    return typeof value === "string" && value.trim() ? value.trim() : null;
};
const deleteCollection = async (path, batchSize = 300) => {
    while (true) {
        const snapshot = await db.collection(path).limit(batchSize).get();
        if (snapshot.empty)
            return;
        const writer = db.bulkWriter();
        snapshot.docs.forEach((doc) => writer.delete(doc.ref));
        await writer.close();
        if (snapshot.size < batchSize)
            return;
    }
};
const anonymizeOwnedCouncils = async (uid) => {
    const ids = [];
    while (true) {
        const snapshot = await db.collection("councils").where("ownerId", "==", uid).limit(300).get();
        if (snapshot.empty)
            return ids;
        const writer = db.bulkWriter();
        for (const doc of snapshot.docs) {
            ids.push(doc.id);
            writer.update(doc.ref, {
                ownerDeleted: true,
                ownerId: null,
                createdBy: null,
                createdByName: "مستخدم محذوف",
                "ownerSnapshot.displayName": "مستخدم محذوف",
                "ownerSnapshot.photoUrl": null,
                "ownerSnapshot.avatarEmoji": "business:person_growth",
                coverImageUrl: null,
                imageUrls: [],
                imagesCount: 0,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        await writer.close();
        if (snapshot.size < 300)
            return ids;
    }
};
const anonymizeComments = async (uid) => {
    while (true) {
        const snapshot = await db.collection("comments").where("authorId", "==", uid).limit(300).get();
        if (snapshot.empty)
            return;
        const writer = db.bulkWriter();
        for (const doc of snapshot.docs) {
            writer.update(doc.ref, {
                authorDeleted: true,
                authorId: null,
                userId: null,
                userNickname: "مستخدم محذوف",
                userAvatar: "business:person_growth",
                "authorSnapshot.displayName": "مستخدم محذوف",
                "authorSnapshot.photoUrl": null,
                "authorSnapshot.avatarEmoji": "business:person_growth",
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        await writer.close();
        if (snapshot.size < 300)
            return;
    }
};
const anonymizeConversations = async (uid) => {
    const ids = [];
    const snapshot = await db.collection("conversations").where("participantIds", "array-contains", uid).get();
    const writer = db.bulkWriter();
    for (const doc of snapshot.docs) {
        ids.push(doc.id);
        const data = doc.data();
        const update = {
            [`participantSnapshots.${uid}`]: {
                displayName: "مستخدم محذوف",
                avatarEmoji: "business:person_growth",
            },
            [`unreadCounts.${uid}`]: 0,
            archivedBy: firestore_1.FieldValue.arrayRemove(uid),
            deletedBy: firestore_1.FieldValue.arrayUnion(uid),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        };
        if (data.lastSenderId === uid)
            update.lastSenderId = null;
        writer.update(doc.ref, update);
    }
    await writer.close();
    return ids;
};
const anonymizeMessages = async (uid) => {
    while (true) {
        const snapshot = await db.collectionGroup("messages").where("senderId", "==", uid).limit(300).get();
        if (snapshot.empty)
            return;
        const writer = db.bulkWriter();
        for (const doc of snapshot.docs) {
            const data = doc.data();
            const update = {
                senderId: null,
                senderDeleted: true,
                readBy: firestore_1.FieldValue.arrayRemove(uid),
            };
            if (data.type === "image") {
                update.type = "text";
                update.text = "صورة حُذفت مع الحساب";
                update.imageUrl = null;
                update.imagePath = null;
            }
            writer.update(doc.ref, update);
        }
        await writer.close();
        if (snapshot.size < 300)
            return;
    }
};
const anonymizeVotes = async (uid) => {
    while (true) {
        const snapshot = await db.collectionGroup("votes").where("uid", "==", uid).limit(300).get();
        if (snapshot.empty)
            return;
        const writer = db.bulkWriter();
        snapshot.docs.forEach((doc) => writer.update(doc.ref, {
            uid: null,
            userDeleted: true,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }));
        await writer.close();
        if (snapshot.size < 300)
            return;
    }
};
const deleteBlocksTargetingUser = async (uid) => {
    while (true) {
        const snapshot = await db.collectionGroup("blockedUsers").where("uid", "==", uid).limit(300).get();
        if (snapshot.empty)
            return;
        const writer = db.bulkWriter();
        snapshot.docs.forEach((doc) => writer.delete(doc.ref));
        await writer.close();
        if (snapshot.size < 300)
            return;
    }
};
const anonymizeReports = async (uid) => {
    while (true) {
        const snapshot = await db.collection("reports").where("reporterId", "==", uid).limit(300).get();
        if (snapshot.empty)
            return;
        const writer = db.bulkWriter();
        snapshot.docs.forEach((doc) => writer.update(doc.ref, {
            reporterId: null,
            reportedBy: null,
            reporterDeleted: true,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }));
        await writer.close();
        if (snapshot.size < 300)
            return;
    }
};
const anonymizeSponsorshipRequests = async (uid) => {
    while (true) {
        const snapshot = await db.collection("sponsorshipRequests").where("requesterId", "==", uid).limit(300).get();
        if (snapshot.empty)
            return;
        const writer = db.bulkWriter();
        snapshot.docs.forEach((doc) => writer.update(doc.ref, {
            requesterId: null,
            contactName: "مستخدم محذوف",
            contactPhone: null,
            requesterDeleted: true,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }));
        await writer.close();
        if (snapshot.size < 300)
            return;
    }
};
const deleteStoragePrefix = async (prefix) => {
    try {
        await (0, storage_1.getStorage)().bucket().deleteFiles({ prefix });
    }
    catch (error) {
        console.error(`Failed to delete storage prefix ${prefix}`, error);
    }
};
exports.deleteMyAccount = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "يجب تسجيل الدخول لحذف الحساب.");
    }
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const nicknameKey = stringValue(userSnap.data()?.nicknameKey);
    const [ownedCouncilIds, conversationIds] = await Promise.all([
        anonymizeOwnedCouncils(uid),
        anonymizeConversations(uid),
        anonymizeComments(uid),
        anonymizeMessages(uid),
        anonymizeVotes(uid),
        anonymizeReports(uid),
        anonymizeSponsorshipRequests(uid),
        deleteCollection(`users/${uid}/fcmTokens`),
        deleteCollection(`users/${uid}/notifications`),
        deleteCollection(`users/${uid}/blockedUsers`),
        deleteBlocksTargetingUser(uid),
    ]).then((results) => [results[0], results[1]]);
    await Promise.all([
        deleteStoragePrefix(`users/${uid}/`),
        ...ownedCouncilIds.map((id) => deleteStoragePrefix(`councils/${id}/images/${uid}/`)),
        ...conversationIds.map((id) => deleteStoragePrefix(`conversations/${id}/images/${uid}/`)),
    ]);
    const writer = db.bulkWriter();
    if (nicknameKey)
        writer.delete(db.collection("nicknames").doc(nicknameKey));
    writer.delete(db.collection("publicProfiles").doc(uid));
    writer.delete(userRef);
    await writer.close();
    await (0, auth_1.getAuth)().deleteUser(uid);
    return { deleted: true };
});
//# sourceMappingURL=account.js.map