// functions/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

// Per-function runtime options (v1 API)
const runtimeOpts = {
  maxInstances: 10,
  memory: "256MB",
  timeoutSeconds: 60,
};

/**
 * Send a push to all tokens under users/{uid}/fcmTokens/*
 * We store tokens as doc IDs, with optional { token, platform, updatedAt } fields.
 */
async function notifyUser(uid, { title, body, data = {} }) {
  const snap = await db.collection("users").doc(uid).collection("fcmTokens").get();
  if (snap.empty) return;

  const tokens = snap.docs.map((d) => d.id);

  const message = {
    notification: { title, body },
    data,
    android: {
      notification: {
        channelId: "high_importance_channel", // must match your AndroidManifest meta-data
        priority: "HIGH",
      },
    },
    apns: {
      payload: { aps: { sound: "default", contentAvailable: true } },
    },
    tokens,
  };

  const resp = await messaging.sendEachForMulticast(message);

  // Remove tokens that are no longer valid
  const invalid = [];
  resp.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error?.code || "";
      if (
        code.includes("registration-token-not-registered") ||
        code.includes("invalid-argument")
      ) {
        invalid.push(tokens[i]);
      }
    }
  });
  await Promise.all(
    invalid.map((t) =>
      db.collection("users").doc(uid).collection("fcmTokens").doc(t).delete()
    )
  );
}

/**
 * Fires when an admin (or backend) creates a doc in onProcess/{reportId}
 * → Notifies the original reporter (doc.uid)
 */
exports.onReportMovedToProcess = functions
  .runWith(runtimeOpts)
  .firestore.document("onProcess/{reportId}")
  .onCreate(async (snap, ctx) => {
    const d = snap.data() || {};
    const uid = d.uid;
    if (!uid) return;

    await notifyUser(uid, {
      title: "Your report is being processed",
      body: `Report "${d.serviceType || d.platformName || "Update"}" is now in progress.`,
      data: {
        reportId: ctx.params.reportId,
        status: "onProcess",
      },
    });
  });

/**
 * Fires when a doc appears in resolvedReports/{reportId}
 * → Notifies the original reporter (doc.uid)
 */
exports.onReportResolved = functions
  .runWith(runtimeOpts)
  .firestore.document("resolvedReports/{reportId}")
  .onCreate(async (snap, ctx) => {
    const d = snap.data() || {};
    const uid = d.uid;
    if (!uid) return;

    await notifyUser(uid, {
      title: "Report resolved",
      body: "A fix was submitted for your report. Please review & approve.",
      data: {
        reportId: ctx.params.reportId,
        status: "resolved",
      },
    });
  });

/**
 * OPTIONAL: If you ever switch to a single collection and change a `status` field,
 * you can use this instead. Keep it commented out if you use separate collections.
 */
// exports.onStatusChange = functions
//   .runWith(runtimeOpts)
//   .firestore.document("userReport/{reportId}")
//   .onUpdate(async (change, ctx) => {
//     const before = (change.before.data().status || "").toLowerCase();
//     const after = (change.after.data().status || "").toLowerCase();
//     if (before === after) return;
//     const d = change.after.data() || {};
//     const uid = d.uid;
//     if (!uid) return;
//
//     let title = "Report updated";
//     let body = `Status: ${after}`;
//     if (after === "on process") {
//       title = "Your report is being processed";
//       body = `Report "${d.serviceType || d.platformName || "Update"}" is now in progress.`;
//     } else if (after === "resolved") {
//       title = "Report resolved";
//       body = "A fix was submitted for your report. Please review & approve.";
//     }
//
//     await notifyUser(uid, {
//       title,
//       body,
//       data: { reportId: ctx.params.reportId, status: after },
//     });
//   });
