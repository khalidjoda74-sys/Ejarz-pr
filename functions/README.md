# Majlisna Cloud Functions

Existing callable functions cover voting, comments, reports, sponsorship interest, and sponsorship events.

Recommended next production functions:

- `sendNotification`: reads `notifications` documents and sends FCM through Firebase Admin SDK.
- `processVoteTransaction`: optional stricter server-only vote processing if client vote writes are disabled.
- `updateAnalyticsDaily`: aggregates daily users, councils, votes, comments, revenue, and reports.
- `generateCompanyPollReport`: exports company poll results for customers.
- `cleanupExpiredBoosts`: ends expired boosts and clears pinned state when needed.
- `endExpiredCouncils`: closes councils whose `endsAt` has passed.

Do not put service account keys, FCM server keys, or other secrets in client code or this repository.
