/**
 * OPTIONAL server-side reminder backup.
 *
 * The app does not need this. Reminders are scheduled on-device with exact
 * alarms (see lib/services/notification_service.dart), which works offline and
 * costs nothing. This function exists only if you want a second channel that
 * still fires when the phone has been off for days, or if you later add a web
 * or iOS client.
 *
 * Before it will do anything you must:
 *   1. Be on the Blaze plan (scheduled functions require it).
 *   2. Add `firebase_messaging` to the Flutter app and write each device's FCM
 *      token to  users/{uid}/devices/{token}  with a `token` field.
 *   3. `cd functions && npm install && firebase deploy --only functions`
 *
 * Without step 2 this function runs, finds no device tokens, and exits.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// Days before the deadline on which the server also pushes a reminder.
const LEAD_DAYS = [3, 0];

// Runs once a day. Change the timezone to wherever you actually are.
exports.deadlineReminders = onSchedule(
  { schedule: "0 9 * * *", timeZone: "Europe/Stockholm" },
  async () => {
    const today = startOfUtcDay(new Date());

    const targets = LEAD_DAYS.map((lead) => ({
      lead,
      date: addDays(today, lead),
    }));

    const users = await db.collection("users").listDocuments();
    let sent = 0;

    for (const userRef of users) {
      const deviceSnap = await userRef.collection("devices").get();
      const tokens = deviceSnap.docs
        .map((d) => d.get("token"))
        .filter((t) => typeof t === "string" && t.length > 0);
      if (tokens.length === 0) continue;

      for (const { lead, date } of targets) {
        const snap = await userRef
          .collection("positions")
          .where("status", "==", "notApplied")
          .where("archived", "==", false)
          .where("deadline", ">=", admin.firestore.Timestamp.fromDate(date))
          .where(
            "deadline",
            "<",
            admin.firestore.Timestamp.fromDate(addDays(date, 1))
          )
          .get();

        for (const doc of snap.docs) {
          const p = doc.data();
          if (p.reminderEnabled === false) continue;

          const title =
            lead === 0
              ? `Deadline today: ${p.university}`
              : `Deadline in ${lead} days: ${p.university}`;

          await admin.messaging().sendEachForMulticast({
            tokens,
            notification: {
              title,
              body: `${p.programme || "Application"} — still marked as not applied.`,
            },
            data: { positionId: doc.id },
            android: { priority: "high" },
          });
          sent += 1;
        }
      }
    }

    logger.info(`deadlineReminders: pushed ${sent} reminder(s).`);
  }
);

function startOfUtcDay(d) {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function addDays(d, n) {
  const copy = new Date(d);
  copy.setUTCDate(copy.getUTCDate() + n);
  return copy;
}
