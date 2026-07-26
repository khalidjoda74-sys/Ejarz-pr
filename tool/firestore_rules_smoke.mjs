import assert from "node:assert/strict";

// Start the Firestore emulator with this repository's rules, then run:
// FIRESTORE_EMULATOR_HOST=127.0.0.1:8788 node tool/firestore_rules_smoke.mjs
const host = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8788";
const projectId = process.env.FIRESTORE_PROJECT_ID ?? "majalisna-rules-test";
const databaseRoot =
  `projects/${projectId}/databases/(default)/documents`;
const apiRoot = `http://${host}/v1/${databaseRoot}`;

const encodeTokenPart = (value) =>
  Buffer.from(JSON.stringify(value)).toString("base64url");

const authToken = (uid) => {
  const now = Math.floor(Date.now() / 1000);
  return [
    encodeTokenPart({alg: "none", typ: "JWT"}),
    encodeTokenPart({
      sub: uid,
      user_id: uid,
      aud: projectId,
      iss: `https://securetoken.google.com/${projectId}`,
      iat: now,
      exp: now + 3600,
      firebase: {
        sign_in_provider: "password",
        identities: {},
      },
    }),
    "",
  ].join(".");
};

const firestoreValue = (value) => {
  if (value === null) return {nullValue: null};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "number" && Number.isInteger(value)) {
    return {integerValue: String(value)};
  }
  if (Array.isArray(value)) {
    return {arrayValue: {values: value.map(firestoreValue)}};
  }
  if (typeof value === "object") {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map(([key, item]) => [
            key,
            firestoreValue(item),
          ]),
        ),
      },
    };
  }
  throw new TypeError(`Unsupported Firestore value: ${String(value)}`);
};

const fieldsFor = (data) =>
  Object.fromEntries(
    Object.entries(data).map(([key, value]) => [
      key,
      firestoreValue(value),
    ]),
  );

const request = async (
  url,
  {method = "GET", uid, admin = false, body} = {},
) => {
  const headers = {};
  if (admin) headers.authorization = "Bearer owner";
  if (uid) headers.authorization = `Bearer ${authToken(uid)}`;
  if (body !== undefined) headers["content-type"] = "application/json";
  return fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
};

const expectStatus = async (label, response, expected) => {
  const text = await response.text();
  assert.equal(
    response.status,
    expected,
    `${label}: expected HTTP ${expected}, got ${response.status}\n${text}`,
  );
};

const documentUrl = (path) => `${apiRoot}/${path}`;

const adminSet = async (path, data) => {
  await expectStatus(
    `admin seed ${path}`,
    await request(documentUrl(path), {
      method: "PATCH",
      admin: true,
      body: {fields: fieldsFor(data)},
    }),
    200,
  );
};

const adminDelete = async (path) => {
  await expectStatus(
    `admin delete ${path}`,
    await request(documentUrl(path), {method: "DELETE", admin: true}),
    200,
  );
};

const commitCreate = async (
  path,
  data,
  uid,
  timestampFields,
) => {
  return request(
    `http://${host}/v1/projects/${projectId}/databases/(default)/documents:commit`,
    {
      method: "POST",
      uid,
      body: {
        writes: [
          {
            update: {
              name: `${databaseRoot}/${path}`,
              fields: fieldsFor(data),
            },
            currentDocument: {exists: false},
            updateTransforms: timestampFields.map((fieldPath) => ({
              fieldPath,
              setToServerValue: "REQUEST_TIME",
            })),
          },
        ],
      },
    },
  );
};

const profile = (uid, {visible = true, demo = false} = {}) => ({
  uid,
  id: uid,
  displayName: `Member ${uid.toUpperCase()}`,
  username: `@member_${uid}`,
  avatarEmoji: "business:person_growth",
  publicPhotoUrl: null,
  isVisible: visible,
  demo,
});

const participantSnapshot = (uid, overrides = {}) => ({
  displayName: `Member ${uid.toUpperCase()}`,
  username: `@member_${uid}`,
  avatarEmoji: "business:person_growth",
  ...overrides,
});

const conversationBase = ({
  initiatorId,
  targetId,
  snapshots,
}) => ({
  participantIds: [initiatorId, targetId],
  participantSnapshots: snapshots ?? {
    [initiatorId]: participantSnapshot(initiatorId),
    [targetId]: participantSnapshot(targetId),
  },
  lastMessageText: "",
  lastMessageAt: null,
  lastSenderId: null,
  unreadCounts: {[initiatorId]: 0, [targetId]: 0},
  lastReadAt: {},
  status: "active",
  blockedBy: [],
  archivedBy: [],
  deletedBy: [],
  reportCount: 0,
});

const directConversation = (initiatorId, targetId, snapshots) => ({
  contextType: "direct",
  initiatorId,
  targetId,
  ...conversationBase({initiatorId, targetId, snapshots}),
});

const seedIdentity = async (
  uid,
  {status = "active", visible = true, demo = false} = {},
) => {
  await adminSet(`users/${uid}`, {uid, status});
  await adminSet(
    `publicProfiles/${uid}`,
    profile(uid, {visible, demo}),
  );
};

const main = async () => {
  for (const uid of ["a", "b", "c", "d", "e", "f"]) {
    await seedIdentity(uid, {
      status: uid === "d" ? "stopped" : "active",
      visible: uid !== "d",
      demo: uid === "c",
    });
  }

  await expectStatus(
    "users stay private for visitors",
    await request(documentUrl("users/a")),
    403,
  );
  await expectStatus(
    "a member reads only their own private user document",
    await request(documentUrl("users/a"), {uid: "a"}),
    200,
  );
  await expectStatus(
    "a member cannot read another private user document",
    await request(documentUrl("users/b"), {uid: "a"}),
    403,
  );
  await expectStatus(
    "visible profiles are public",
    await request(documentUrl("publicProfiles/b")),
    200,
  );
  await expectStatus(
    "hidden profiles are not public",
    await request(documentUrl("publicProfiles/d")),
    403,
  );
  await expectStatus(
    "a hidden profile remains readable by its owner",
    await request(documentUrl("publicProfiles/d"), {uid: "d"}),
    200,
  );
  await expectStatus(
    "clients cannot forge a public profile",
    await request(documentUrl("publicProfiles/a"), {
      method: "PATCH",
      uid: "a",
      body: {fields: fieldsFor(profile("a"))},
    }),
    403,
  );

  const clientCouncil = {
    title: "Client opportunity",
    city: "Riyadh",
    countryCode: "SA",
    countryName: "المملكة العربية السعودية",
    createdBy: "a",
    ownerId: "a",
    createdByName: "Member A",
    ownerSnapshot: {
      displayName: "Member A",
      photoUrl: null,
      avatarEmoji: "business:person_growth",
    },
    status: "active",
    visibility: "public",
    isCouncilOfDay: false,
    isPinned: false,
    sponsorId: null,
    voteCounts: {support: 0, against: 0, neutral: 0},
  };
  await expectStatus(
    "opportunities use the selected public identity",
    await commitCreate(
      "councils/client_valid",
      clientCouncil,
      "a",
      [],
    ),
    200,
  );
  await expectStatus(
    "opportunity owner identity forgery is rejected",
    await commitCreate(
      "councils/client_forged",
      {
        ...clientCouncil,
        createdByName: "Google Provider Name",
        ownerSnapshot: {
          ...clientCouncil.ownerSnapshot,
          displayName: "Google Provider Name",
        },
      },
      "a",
      [],
    ),
    403,
  );

  await adminSet("councils/real_b", {
    title: "Real opportunity",
    status: "active",
    visibility: "public",
    createdBy: "b",
    ownerId: "b",
    isSeedContent: false,
  });
  await adminSet("councils/demo_b", {
    title: "Demo opportunity",
    status: "active",
    visibility: "public",
    createdBy: "b",
    ownerId: "b",
    isSeedContent: true,
  });

  const legacyOpportunity = {
    councilId: "real_b",
    councilTitle: "Real opportunity",
    ownerId: "b",
    requesterId: "a",
    ...conversationBase({initiatorId: "a", targetId: "b"}),
  };
  await expectStatus(
    "legacy opportunity conversations remain compatible",
    await commitCreate(
      "conversations/opportunity_legacy",
      legacyOpportunity,
      "a",
      ["createdAt", "updatedAt"],
    ),
    200,
  );
  await expectStatus(
    "demo opportunities cannot create real conversations",
    await commitCreate(
      "conversations/opportunity_demo",
      {...legacyOpportunity, councilId: "demo_b"},
      "a",
      ["createdAt", "updatedAt"],
    ),
    403,
  );

  const directId = "direct_a_b";
  await expectStatus(
    "canonical direct conversation is created",
    await commitCreate(
      `conversations/${directId}`,
      directConversation("a", "b"),
      "a",
      ["createdAt", "updatedAt"],
    ),
    200,
  );
  await expectStatus(
    "the opposite side reuses the same deterministic document",
    await commitCreate(
      `conversations/${directId}`,
      directConversation("b", "a"),
      "b",
      ["createdAt", "updatedAt"],
    ),
    409,
  );
  await expectStatus(
    "a reversed duplicate direct id is rejected",
    await commitCreate(
      "conversations/direct_b_a",
      directConversation("b", "a"),
      "b",
      ["createdAt", "updatedAt"],
    ),
    403,
  );
  await expectStatus(
    "self messaging is rejected",
    await commitCreate(
      "conversations/direct_a_a",
      directConversation("a", "a"),
      "a",
      ["createdAt", "updatedAt"],
    ),
    403,
  );
  await expectStatus(
    "demo messaging is rejected",
    await commitCreate(
      "conversations/direct_a_c",
      directConversation("a", "c"),
      "a",
      ["createdAt", "updatedAt"],
    ),
    403,
  );
  await expectStatus(
    "stopped account messaging is rejected",
    await commitCreate(
      "conversations/direct_a_d",
      directConversation("a", "d"),
      "a",
      ["createdAt", "updatedAt"],
    ),
    403,
  );
  await expectStatus(
    "participant identity forgery is rejected",
    await commitCreate(
      "conversations/direct_e_f",
      directConversation("e", "f", {
        e: participantSnapshot("e"),
        f: participantSnapshot("f", {displayName: "Forged member"}),
      }),
      "e",
      ["createdAt", "updatedAt"],
    ),
    403,
  );
  await expectStatus(
    "a second valid direct conversation is created",
    await commitCreate(
      "conversations/direct_e_f",
      directConversation("e", "f"),
      "e",
      ["createdAt", "updatedAt"],
    ),
    200,
  );
  await adminSet("users/f", {uid: "f", status: "stopped"});
  await expectStatus(
    "existing conversations cannot message a stopped account",
    await commitCreate(
      "conversations/direct_e_f/messages/stopped_receiver",
      {
        senderId: "e",
        text: "Must be rejected",
        status: "sent",
        readBy: ["e"],
        type: "text",
      },
      "e",
      ["createdAt"],
    ),
    403,
  );

  await expectStatus(
    "direct messages are allowed before a block",
    await commitCreate(
      `conversations/${directId}/messages/message_1`,
      {
        senderId: "a",
        text: "Hello",
        status: "sent",
        readBy: ["a"],
        type: "text",
      },
      "a",
      ["createdAt"],
    ),
    200,
  );
  await expectStatus(
    "direct conversation reports omit the opportunity id",
    await commitCreate(
      "reports/direct_report",
      {
        targetType: "conversation",
        targetId: directId,
        targetPreview: "Direct conversation",
        conversationId: directId,
        reason: "Safety",
        description: "",
        details: "",
        reportedBy: "a",
        reporterId: "a",
        status: "pending",
        priority: "high",
      },
      "a",
      ["createdAt", "updatedAt"],
    ),
    200,
  );

  await adminSet("users/a/blockedUsers/b", {
    uid: "b",
    conversationId: directId,
  });
  await expectStatus(
    "messages are rejected when either side blocks",
    await commitCreate(
      `conversations/${directId}/messages/message_2`,
      {
        senderId: "a",
        text: "Blocked",
        status: "sent",
        readBy: ["a"],
        type: "text",
      },
      "a",
      ["createdAt"],
    ),
    403,
  );
  await adminDelete(`conversations/${directId}`);
  await expectStatus(
    "new direct conversations are rejected after a block",
    await commitCreate(
      `conversations/${directId}`,
      directConversation("a", "b"),
      "a",
      ["createdAt", "updatedAt"],
    ),
    403,
  );

  console.log("Firestore rules smoke tests passed.");
};

await main();
