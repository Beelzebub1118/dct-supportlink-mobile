// functions/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

const runtimeOpts = {
  maxInstances: 10,
  memory: "256MB",
  timeoutSeconds: 60,
};

// helper: send to all tokens under users/{uid}/fcmTokens/* (token as docId or field)
async function notifyUser(uid, payload) {
  const snap = await db.collection("users").doc(uid).collection("fcmTokens").get();
  if (snap.empty) return;

  const tokens = snap.docs
    .map((d) => d.id || d.get("token"))
    .filter(Boolean);

  const resp = await messaging.sendEachForMulticast({
    ...payload,
    tokens,
  });

  // prune invalid tokens
  const toDelete = [];
  resp.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error?.code || "";
      if (
        code.includes("registration-token-not-registered") ||
        code.includes("invalid-argument")
      ) {
        const token = tokens[i];
        toDelete.push(
          db.collection("users").doc(uid).collection("fcmTokens").doc(token).delete().catch(() => null)
        );
      }
    }
  });
  await Promise.all(toDelete);
}

// 🔔 Fires when status changes in userReport/{reportId}
exports.onReportStatusChange = functions
  .runWith(runtimeOpts)
  .firestore.document("userReport/{reportId}")
  .onUpdate(async (change, ctx) => {
    const before = (change.before.get("status") || "").toString().toLowerCase().trim();
    const after  = (change.after.get("status")  || "").toString().toLowerCase().trim();
    if (!after || before === after) return null; // no change

    const d   = change.after.data() || {};
    const uid = d.uid;
    if (!uid) return null;

    // Normalize status for ID (remove spaces): "on process" → "onprocess"
    const statusKey = after.replace(/\s+/g, "");
    const reportId  = ctx.params.reportId;
    const notifId   = `report:${reportId}:${statusKey}`;

    const title =
      statusKey === "onprocess"
        ? "Your report is being processed"
        : statusKey === "resolved"
        ? "Report resolved"
        : "Report updated";

    const body =
      statusKey === "onprocess"
        ? `Report "${d.serviceType || d.platformName || reportId}" is now in progress.`
        : statusKey === "resolved"
        ? "A fix was submitted for your report. Please review & approve."
        : `Report ${reportId} is now ${after}.`;

    const data = {
      notifId,
      reportId,
      status: statusKey,
      route: `/reports/${reportId}`,
    };

    await notifyUser(uid, {
      notification: { title, body },
      data,
      android: {
        // Collapses duplicates in transit & helps local grouping
        collapseKey: notifId,
        priority: "high",
        notification: {
          channelId: "high_importance_channel", // must match your AndroidManifest
          tag: notifId,
        },
      },
      apns: {
        headers: {
          "apns-collapse-id": notifId,
          "apns-priority": "10",
        },
        payload: {
          aps: { sound: "default" },
        },
      },
    });

    return null;
  });
