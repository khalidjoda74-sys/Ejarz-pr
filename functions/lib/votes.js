"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.castVote = void 0;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const db = (0, firestore_1.getFirestore)();
const voteOptions = ["support", "against", "neutral"];
const isVoteOption = (value) => {
    return typeof value === "string" && voteOptions.includes(value);
};
const emptyVoteCounts = () => ({
    support: 0,
    against: 0,
    neutral: 0,
});
const toVoteCounts = (value) => {
    const counts = emptyVoteCounts();
    if (value == null || typeof value !== "object")
        return counts;
    const source = value;
    for (const option of voteOptions) {
        const raw = source[option];
        counts[option] = typeof raw === "number" && Number.isFinite(raw) ? raw : 0;
    }
    return counts;
};
const percentagesFor = (counts) => {
    const total = voteOptions.reduce((sum, option) => sum + counts[option], 0);
    if (total <= 0) {
        return {
            support: 0,
            against: 0,
            neutral: 0,
        };
    }
    return {
        support: Math.round((counts.support / total) * 100),
        against: Math.round((counts.against / total) * 100),
        neutral: Math.round((counts.neutral / total) * 100),
    };
};
exports.castVote = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "يجب تسجيل الدخول لإضافة الرأي السريع.");
    }
    const councilId = request.data?.councilId;
    const option = request.data?.option;
    if (typeof councilId !== "string" || councilId.trim().length === 0) {
        throw new https_1.HttpsError("invalid-argument", "معرف الفرصة غير صالح.");
    }
    if (!isVoteOption(option)) {
        throw new https_1.HttpsError("invalid-argument", "خيار الرأي السريع غير صالح.");
    }
    const councilRef = db.collection("councils").doc(councilId.trim());
    const voteRef = councilRef.collection("votes").doc(uid);
    return db.runTransaction(async (transaction) => {
        const councilSnap = await transaction.get(councilRef);
        if (!councilSnap.exists) {
            throw new https_1.HttpsError("not-found", "الفرصة غير موجودة.");
        }
        const council = councilSnap.data() ?? {};
        if (council.status !== "active") {
            throw new https_1.HttpsError("failed-precondition", "هذه الفرصة غير متاحة للتصويت.");
        }
        const ownerId = typeof council.ownerId === "string" && council.ownerId.trim()
            ? council.ownerId.trim()
            : typeof council.createdBy === "string" && council.createdBy.trim()
                ? council.createdBy.trim()
                : "";
        if (ownerId === uid) {
            throw new https_1.HttpsError("failed-precondition", "لا يمكن لصاحب الفرصة إضافة رأي سريع على فرصته.");
        }
        const voteSnap = await transaction.get(voteRef);
        const previousOption = voteSnap.exists ? voteSnap.data()?.option : null;
        const voteCounts = toVoteCounts(council.voteCounts);
        if (previousOption === option) {
            voteCounts[option] = Math.max(0, voteCounts[option] - 1);
            const totalVotes = voteOptions.reduce((sum, current) => sum + voteCounts[current], 0);
            transaction.delete(voteRef);
            transaction.update(councilRef, {
                voteCounts,
                percentages: percentagesFor(voteCounts),
                participantsCount: firestore_1.FieldValue.increment(-1),
                votesCount: totalVotes,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            return {
                status: "removed",
                option: null,
                voteCounts,
                votesCount: totalVotes,
                participantsDelta: -1,
            };
        }
        let participantsDelta = 0;
        if (isVoteOption(previousOption)) {
            voteCounts[previousOption] = Math.max(0, voteCounts[previousOption] - 1);
        }
        else {
            participantsDelta = 1;
        }
        voteCounts[option] += 1;
        const totalVotes = voteOptions.reduce((sum, current) => sum + voteCounts[current], 0);
        if (voteSnap.exists) {
            transaction.set(voteRef, {
                uid,
                option,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
                optionChangedCount: firestore_1.FieldValue.increment(1),
            }, { merge: true });
        }
        else {
            transaction.set(voteRef, {
                uid,
                option,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
                optionChangedCount: 0,
            });
        }
        transaction.update(councilRef, {
            voteCounts,
            percentages: percentagesFor(voteCounts),
            participantsCount: firestore_1.FieldValue.increment(participantsDelta),
            votesCount: totalVotes,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        return {
            status: voteSnap.exists ? "changed" : "created",
            option,
            voteCounts,
            votesCount: totalVotes,
            participantsDelta,
        };
    });
});
//# sourceMappingURL=votes.js.map