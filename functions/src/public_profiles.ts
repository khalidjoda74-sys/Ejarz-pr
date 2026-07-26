import {
  FieldPath,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

const db = getFirestore();

type UserData = Record<string, unknown>;
type PublicProfileData = {
  uid: string;
  id: string;
  displayName: string;
  username: string;
  avatarEmoji: string;
  publicPhotoUrl: string | null;
  createdAt: Timestamp;
  isVisible: boolean;
  demo: false;
};

const safeString = (value: unknown, fallback = ""): string => {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
};

const optionalString = (value: unknown): string | null => {
  const result = safeString(value);
  return result || null;
};

const safeTimestamp = (
  value: unknown,
  fallback: Timestamp,
): Timestamp => {
  if (value instanceof Timestamp) return value;
  if (value instanceof Date && Number.isFinite(value.getTime())) {
    return Timestamp.fromDate(value);
  }
  return fallback;
};

const hasChosenPublicIdentity = (data: UserData): boolean => {
  if (data.identityCompleted === false) return false;
  if (safeString(data.nickname)) return true;
  if (safeString(data.nicknameKey)) return true;

  // Modern accounts must explicitly choose their in-app identity. The
  // identityCompleted flag alone can also describe a returning provider
  // account, so it is deliberately not sufficient for a public profile.
  if (Object.prototype.hasOwnProperty.call(data, "identityCompleted")) {
    return false;
  }

  // Legacy releases stored a chosen public identity as username + name.
  return Boolean(
    safeString(data.username) &&
      (safeString(data.displayName) || safeString(data.name)),
  );
};

const publicProfileForUser = (
  uid: string,
  data: UserData,
  fallbackCreatedAt: Timestamp,
): PublicProfileData | null => {
  if (!hasChosenPublicIdentity(data)) return null;

  const displayName = safeString(
    data.nickname,
    safeString(data.displayName, safeString(data.name)),
  );
  if (!displayName) return null;

  const nicknameKey = safeString(data.nicknameKey);
  const username = safeString(
    data.username,
    nicknameKey ? `@${nicknameKey}` : "",
  );
  const avatarEmoji = safeString(
    data.avatarEmoji,
    safeString(data.avatar, "business:person_growth"),
  );

  return {
    uid,
    id: uid,
    displayName,
    username,
    avatarEmoji,
    publicPhotoUrl: optionalString(data.publicPhotoUrl),
    createdAt: safeTimestamp(data.createdAt, fallbackCreatedAt),
    isVisible: safeString(data.status, "active") === "active",
    demo: false,
  };
};

const publicProfilesEqual = (
  current: UserData,
  expected: PublicProfileData,
): boolean => {
  const expectedKeys = [
    "uid",
    "id",
    "displayName",
    "username",
    "avatarEmoji",
    "publicPhotoUrl",
    "createdAt",
    "isVisible",
    "demo",
  ].sort();
  const currentKeys = Object.keys(current).sort();
  if (
    currentKeys.length !== expectedKeys.length ||
    currentKeys.some((key, index) => key !== expectedKeys[index])
  ) {
    return false;
  }
  return current.uid === expected.uid &&
    current.id === expected.id &&
    current.displayName === expected.displayName &&
    current.username === expected.username &&
    current.avatarEmoji === expected.avatarEmoji &&
    current.publicPhotoUrl === expected.publicPhotoUrl &&
    current.createdAt instanceof Timestamp &&
    current.createdAt.isEqual(expected.createdAt) &&
    current.isVisible === expected.isVisible &&
    current.demo === expected.demo;
};

const isActiveAdmin = async (
  uid: string,
  token: Record<string, unknown>,
): Promise<boolean> => {
  if (token.admin === true) return true;
  const adminSnapshot = await db.collection("admins").doc(uid).get();
  return adminSnapshot.exists && adminSnapshot.data()?.status === "active";
};

export const syncPublicProfile = onDocumentWritten(
  {
    region: "us-central1",
    document: "users/{uid}",
  },
  async (event): Promise<void> => {
    const uid = event.params.uid;
    const publicProfileRef = db.collection("publicProfiles").doc(uid);
    const after = event.data?.after;
    const current = await publicProfileRef.get();

    if (!after?.exists) {
      if (current.exists) await publicProfileRef.delete();
      return;
    }

    const profile = publicProfileForUser(
      uid,
      after.data() ?? {},
      after.createTime ??
        event.data?.before.createTime ??
        current.createTime ??
        Timestamp.fromMillis(0),
    );
    if (!profile) {
      if (current.exists) await publicProfileRef.delete();
      return;
    }

    if (
      current.exists &&
      publicProfilesEqual(current.data() ?? {}, profile)
    ) {
      return;
    }

    // Deliberately overwrite the document so no legacy/private fields survive.
    await publicProfileRef.set(profile);
  },
);

export const backfillPublicProfiles = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
    invoker: "private",
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Authentication is required.",
      );
    }
    if (!(await isActiveAdmin(uid, request.auth?.token ?? {}))) {
      throw new HttpsError(
        "permission-denied",
        "An active administrator account is required.",
      );
    }

    // Safe by default. A real write requires dryRun: false explicitly.
    const dryRun = request.data?.dryRun !== false;
    const requestedLimit = Number(request.data?.limit);
    const limit = Number.isFinite(requestedLimit)
      ? Math.min(500, Math.max(1, Math.trunc(requestedLimit)))
      : 250;
    const startAfter = safeString(request.data?.startAfter);

    let query = db
      .collection("users")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (startAfter) query = query.startAfter(startAfter);

    const snapshot = await query.get();
    const writer = dryRun ? null : db.bulkWriter();
    let eligible = 0;
    let ineligible = 0;

    for (const userSnapshot of snapshot.docs) {
      const profile = publicProfileForUser(
        userSnapshot.id,
        userSnapshot.data(),
        userSnapshot.createTime,
      );
      const profileRef = db
        .collection("publicProfiles")
        .doc(userSnapshot.id);

      if (profile) {
        eligible += 1;
        writer?.set(profileRef, profile);
      } else {
        ineligible += 1;
        writer?.delete(profileRef);
      }
    }
    await writer?.close();

    const lastDocument = snapshot.docs[snapshot.docs.length - 1];
    return {
      dryRun,
      scanned: snapshot.size,
      eligible,
      ineligible,
      written: dryRun ? 0 : eligible,
      deleted: dryRun ? 0 : ineligible,
      nextCursor:
        snapshot.size === limit && lastDocument ? lastDocument.id : null,
    };
  },
);
