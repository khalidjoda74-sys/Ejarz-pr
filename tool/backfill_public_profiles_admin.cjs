"use strict";

const path = require("node:path");

const projectId = "majalisna-discussions-20260629";
const firebaseToolsRoot = process.argv[2];
const writeChanges = process.argv.includes("--write");
const verifyExisting = writeChanges || process.argv.includes("--verify");

if (!firebaseToolsRoot) {
  throw new Error("Pass the firebase-tools package root as the first argument.");
}

const auth = require(path.join(firebaseToolsRoot, "lib", "auth.js"));

const safeString = (value, fallback = "") =>
  typeof value === "string" && value.trim() ? value.trim() : fallback;

const fieldValue = (field) => {
  if (!field || typeof field !== "object") return undefined;
  if (Object.hasOwn(field, "stringValue")) return field.stringValue;
  if (Object.hasOwn(field, "booleanValue")) return field.booleanValue;
  if (Object.hasOwn(field, "timestampValue")) return field.timestampValue;
  if (Object.hasOwn(field, "nullValue")) return null;
  return undefined;
};

const userData = (document) =>
  Object.fromEntries(
    Object.entries(document.fields ?? {}).map(([key, value]) => [
      key,
      fieldValue(value),
    ]),
  );

const hasChosenPublicIdentity = (data) => {
  if (data.identityCompleted === false) return false;
  if (safeString(data.nickname) || safeString(data.nicknameKey)) return true;
  if (Object.hasOwn(data, "identityCompleted")) return false;
  return Boolean(
    safeString(data.username) &&
      (safeString(data.displayName) || safeString(data.name)),
  );
};

const safeTimestamp = (value, fallback) => {
  const candidate = safeString(value, safeString(fallback));
  const parsed = Date.parse(candidate);
  return Number.isFinite(parsed)
    ? new Date(parsed).toISOString()
    : new Date(0).toISOString();
};

const publicProfileForUser = (uid, data, fallbackCreatedAt) => {
  if (!hasChosenPublicIdentity(data)) return null;

  const displayName = safeString(
    data.nickname,
    safeString(data.displayName, safeString(data.name)),
  );
  if (!displayName) return null;

  const nicknameKey = safeString(data.nicknameKey);
  return {
    uid,
    id: uid,
    displayName,
    username: safeString(
      data.username,
      nicknameKey ? `@${nicknameKey}` : "",
    ),
    avatarEmoji: safeString(
      data.avatarEmoji,
      safeString(data.avatar, "business:person_growth"),
    ),
    publicPhotoUrl: safeString(data.publicPhotoUrl) || null,
    createdAt: safeTimestamp(data.createdAt, fallbackCreatedAt),
    isVisible: safeString(data.status, "active") === "active",
    demo: false,
  };
};

const firestoreFields = (profile) => ({
  uid: {stringValue: profile.uid},
  id: {stringValue: profile.id},
  displayName: {stringValue: profile.displayName},
  username: {stringValue: profile.username},
  avatarEmoji: {stringValue: profile.avatarEmoji},
  publicPhotoUrl:
    profile.publicPhotoUrl === null
      ? {nullValue: null}
      : {stringValue: profile.publicPhotoUrl},
  createdAt: {timestampValue: profile.createdAt},
  isVisible: {booleanValue: profile.isVisible},
  demo: {booleanValue: false},
});

const main = async () => {
  const account = auth.getGlobalDefaultAccount();
  if (!account?.tokens?.refresh_token) {
    throw new Error("Firebase CLI is not signed in.");
  }

  const tokenResult = await auth.getAccessToken(account.tokens.refresh_token, [
    "https://www.googleapis.com/auth/cloud-platform",
  ]);
  const accessToken =
    typeof tokenResult === "string" ? tokenResult : tokenResult?.access_token;
  if (!accessToken) {
    throw new Error("Unable to acquire a Firebase access token.");
  }

  const request = async (url, options = {}) => {
    const response = await fetch(url, {
      ...options,
      headers: {
        authorization: `Bearer ${accessToken}`,
        ...(options.body ? {"content-type": "application/json"} : {}),
      },
    });
    if (!response.ok) {
      const text = await response.text();
      throw new Error(
        `Firestore request failed (${response.status}): ${text.slice(0, 500)}`,
      );
    }
    return response.status === 204 ? null : response.json();
  };

  const documentsRoot =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    "/databases/(default)/documents";

  let pageToken = "";
  let scanned = 0;
  let eligible = 0;
  let ineligible = 0;
  const writes = [];
  const eligibleIds = new Set();

  do {
    const params = new URLSearchParams({
      pageSize: "300",
      orderBy: "__name__",
    });
    if (pageToken) params.set("pageToken", pageToken);

    const page = await request(`${documentsRoot}/users?${params}`);
    for (const document of page.documents ?? []) {
      const uid = document.name.split("/").pop();
      const profile = publicProfileForUser(
        uid,
        userData(document),
        document.createTime,
      );
      const profileName =
        `projects/${projectId}/databases/(default)/documents/publicProfiles/` +
        uid;

      scanned += 1;
      if (profile) {
        eligible += 1;
        eligibleIds.add(uid);
        writes.push({
          update: {
            name: profileName,
            fields: firestoreFields(profile),
          },
        });
      } else {
        ineligible += 1;
        writes.push({delete: profileName});
      }
    }
    pageToken = page.nextPageToken ?? "";
  } while (pageToken);

  if (writeChanges) {
    for (let offset = 0; offset < writes.length; offset += 400) {
      await request(
        `https://firestore.googleapis.com/v1/projects/${projectId}` +
          "/databases/(default)/documents:batchWrite",
        {
          method: "POST",
          body: JSON.stringify({writes: writes.slice(offset, offset + 400)}),
        },
      );
    }
  }

  let verifiedEligible = null;
  let unexpectedProfiles = null;
  if (verifyExisting) {
    const expectedKeys = [
      "avatarEmoji",
      "createdAt",
      "demo",
      "displayName",
      "id",
      "isVisible",
      "publicPhotoUrl",
      "uid",
      "username",
    ];
    const seenIds = new Set();
    let profilesPageToken = "";

    do {
      const params = new URLSearchParams({pageSize: "300"});
      if (profilesPageToken) {
        params.set("pageToken", profilesPageToken);
      }
      const page = await request(`${documentsRoot}/publicProfiles?${params}`);
      for (const document of page.documents ?? []) {
        const profileId = document.name.split("/").pop();
        const actualKeys = Object.keys(document.fields ?? {}).sort();
        if (
          actualKeys.length !== expectedKeys.length ||
          actualKeys.some((key, index) => key !== expectedKeys[index])
        ) {
          throw new Error(
            `Public profile ${profileId} has an unsafe field contract.`,
          );
        }
        const data = userData(document);
        if (
          data.uid !== profileId ||
          data.id !== profileId ||
          data.demo !== false ||
          !safeString(data.createdAt)
        ) {
          throw new Error(`Public profile ${profileId} failed identity checks.`);
        }
        seenIds.add(profileId);
      }
      profilesPageToken = page.nextPageToken ?? "";
    } while (profilesPageToken);

    const missing = [...eligibleIds].filter((uid) => !seenIds.has(uid));
    if (missing.length) {
      throw new Error(`${missing.length} eligible public profiles are missing.`);
    }
    verifiedEligible = eligibleIds.size;
    unexpectedProfiles = [...seenIds].filter(
      (uid) => !eligibleIds.has(uid),
    ).length;
  }

  console.log(
    JSON.stringify({
      dryRun: !writeChanges,
      scanned,
      eligible,
      ineligible,
      writesApplied: writeChanges ? writes.length : 0,
      verifiedEligible,
      unexpectedProfiles,
    }),
  );
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
