const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

// -----------------------------------------------------------------------------
// EmailJS configuration (for Firebase Cloud Functions HTTPS proxy)
// -----------------------------------------------------------------------------

// These values are loaded from Firebase Functions config:
//   firebase functions:config:set emailjs.service_id="service_xxx" \
//     emailjs.template_id="template_otp" \
//     emailjs.welcome_template_id="template_welcome" \
//     emailjs.public_key="your_public_key" \
//     emailjs.private_key="your_private_key"
//
// You can inspect them with:
//   firebase functions:config:get emailjs
//
// NOTE: Do NOT hard‑code private keys in this file.
const emailJsConfig = functions.config().emailjs || {};
const EMAILJS_SERVICE_ID = emailJsConfig.service_id;
const EMAILJS_TEMPLATE_ID = emailJsConfig.template_id;
const EMAILJS_WELCOME_TEMPLATE_ID = emailJsConfig.welcome_template_id;
const EMAILJS_PUBLIC_KEY = emailJsConfig.public_key;
const EMAILJS_PRIVATE_KEY = emailJsConfig.private_key;
const EMAILJS_API_URL = "https://api.emailjs.com/api/v1.0/email/send";

/**
 * Basic validation to ensure required EmailJS config is present.
 * We don't throw at module load time so that other functions can still work
 * even if EmailJS isn't configured.
 *
 * @param {boolean} requireWelcomeTemplate whether welcome template is required
 * @return {void}
 */
function validateEmailJsConfig(requireWelcomeTemplate = false) {
  if (
    !EMAILJS_SERVICE_ID ||
    !EMAILJS_TEMPLATE_ID ||
    !EMAILJS_PUBLIC_KEY ||
    !EMAILJS_PRIVATE_KEY
  ) {
    throw new Error(
      "EmailJS config missing. " +
        "Set it with: firebase functions:config:set " +
        'emailjs.service_id="..." emailjs.template_id="..." ' +
        'emailjs.public_key="..." emailjs.private_key="..."'
    );
  }

  if (requireWelcomeTemplate && !EMAILJS_WELCOME_TEMPLATE_ID) {
    throw new Error(
      "EmailJS welcome_template_id missing. " +
        "Set it with: firebase functions:config:set " +
        'emailjs.welcome_template_id="..."'
    );
  }
}

/**
 * Small helper to send JSON responses with CORS headers so that both
 * mobile apps and web can call these endpoints directly.
 *
 * @param {import("express").Response} res Express response
 * @param {number} status HTTP status code
 * @param {Object} data JSON payload
 * @return {void}
 */
function sendJson(res, status, data) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, X-Requested-With");
  res.status(status).json(data);
}

/**
 * Preflight handler for CORS
 *
 * @param {import("express").Request} req Express request
 * @param {import("express").Response} res Express response
 * @return {void|Object}
 */
function handleOptions(req, res) {
  if (req.method === "OPTIONS") {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, X-Requested-With");
    return res.status(204).send("");
  }
}

/**
 * HTTPS endpoint to send verification email with OTP via EmailJS.
 *
 * URL (default region): https://<region>-<project>.cloudfunctions.net/sendVerificationEmail
 *
 * Expected JSON body:
 * {
 *   "service_id": "service_xxx",        // optional, uses config by default
 *   "template_id": "template_xxx",      // optional, uses config by default
 *   "user_id": "public_key_optional",   // optional, config public_key used
 *   "template_params": {
 *     "to_email": "user@example.com",
 *     "to_name": "User Name",
 *     "otp": "123456",
 *     "reply_to": "user@example.com"
 *   }
 * }
 */
exports.sendVerificationEmail = functions.https.onRequest(async (req, res) => {
  // Handle CORS preflight
  const maybeOptions = handleOptions(req, res);
  if (maybeOptions) return;

  if (req.method !== "POST") {
    return sendJson(res, 405, {
      error: "Method not allowed",
      message: "Use POST with JSON body.",
    });
  }

  try {
    validateEmailJsConfig(false);

    const body = req.body || {};
    const templateParams = body.template_params || {};

    const toEmail = templateParams.to_email;
    const otp = templateParams.otp;

    if (!toEmail || !otp) {
      return sendJson(res, 400, {
        error: "Missing required fields",
        required: ["template_params.to_email", "template_params.otp"],
      });
    }

    const emailData = {
      service_id: body.service_id || EMAILJS_SERVICE_ID,
      template_id: body.template_id || EMAILJS_TEMPLATE_ID,
      // EmailJS strict mode: public key in user_id, private key in accessToken
      user_id: body.user_id || EMAILJS_PUBLIC_KEY,
      accessToken: EMAILJS_PRIVATE_KEY,
      template_params: {
        ...templateParams,
        to_email: toEmail,
        otp: otp,
      },
    };

    console.log(
      `sendVerificationEmail: Sending OTP email to ${toEmail} ` +
        `via template ${emailData.template_id}`
    );

    const response = await fetch(EMAILJS_API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(emailData),
    });

    const text = await response.text();

    if (response.ok) {
      console.log("sendVerificationEmail: EmailJS response:", text);
      return sendJson(res, 200, {
        success: true,
        message: "Verification email sent",
        email: toEmail,
      });
    }

    console.error(
      "sendVerificationEmail: EmailJS error",
      response.status,
      text
    );

    // Special handling for 403 "non-browser" style errors
    if (
      response.status === 403 &&
      (text.includes("non-browser") || text.includes("API calls are disabled"))
    ) {
      return sendJson(res, 403, {
        error: "EmailJS API calls disabled for non-browser applications.",
        message:
          "Enable 'Allow EmailJS API for non-browser applications' " +
          "in your EmailJS dashboard, or verify private key configuration.",
        status: 403,
        details: text,
      });
    }

    return sendJson(res, response.status || 500, {
      error: "Failed to send verification email",
      message: text || "Unknown EmailJS error",
      status: response.status || 500,
    });
  } catch (err) {
    console.error("sendVerificationEmail: Unexpected error", err);
    return sendJson(res, 500, {
      error: "Internal server error",
      message: err && err.message ? err.message : String(err),
    });
  }
});

/**
 * HTTPS endpoint to send welcome email via EmailJS.
 *
 * URL (default region): https://<region>-<project>.cloudfunctions.net/sendWelcomeEmail
 *
 * Body shape is the same as sendVerificationEmail, but otp is not required.
 */
exports.sendWelcomeEmail = functions.https.onRequest(async (req, res) => {
  // Handle CORS preflight
  const maybeOptions = handleOptions(req, res);
  if (maybeOptions) return;

  if (req.method !== "POST") {
    return sendJson(res, 405, {
      error: "Method not allowed",
      message: "Use POST with JSON body.",
    });
  }

  try {
    validateEmailJsConfig(true);

    const body = req.body || {};
    const templateParams = body.template_params || {};

    const toEmail = templateParams.to_email;
    if (!toEmail) {
      return sendJson(res, 400, {
        error: "Missing required fields",
        required: ["template_params.to_email"],
      });
    }

    const emailData = {
      service_id: body.service_id || EMAILJS_SERVICE_ID,
      template_id: body.template_id || EMAILJS_WELCOME_TEMPLATE_ID,
      user_id: body.user_id || EMAILJS_PUBLIC_KEY,
      accessToken: EMAILJS_PRIVATE_KEY,
      template_params: {
        ...templateParams,
        to_email: toEmail,
      },
    };

    console.log(
      `sendWelcomeEmail: Sending welcome email to ${toEmail} ` +
        `via template ${emailData.template_id}`
    );

    const response = await fetch(EMAILJS_API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(emailData),
    });

    const text = await response.text();

    if (response.ok) {
      console.log("sendWelcomeEmail: EmailJS response:", text);
      return sendJson(res, 200, {
        success: true,
        message: "Welcome email sent",
        email: toEmail,
      });
    }

    console.error("sendWelcomeEmail: EmailJS error", response.status, text);

    if (
      response.status === 403 &&
      (text.includes("non-browser") || text.includes("API calls are disabled"))
    ) {
      return sendJson(res, 403, {
        error: "EmailJS API calls disabled for non-browser applications.",
        message:
          "Enable 'Allow EmailJS API for non-browser applications' " +
          "in your EmailJS dashboard, or verify private key configuration.",
        status: 403,
        details: text,
      });
    }

    return sendJson(res, response.status || 500, {
      error: "Failed to send welcome email",
      message: text || "Unknown EmailJS error",
      status: response.status || 500,
    });
  } catch (err) {
    console.error("sendWelcomeEmail: Unexpected error", err);
    return sendJson(res, 500, {
      error: "Internal server error",
      message: err && err.message ? err.message : String(err),
    });
  }
});

/**
 * Scheduled function that runs every minute to check for due reminders
 * and send FCM push notifications
 */
exports.checkAndSendReminders = functions.pubsub
  .schedule("every 1 minutes")
  .timeZone("UTC")
  .onRun(async (context) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    console.log("Checking for due reminders at:", now.toDate());

    try {
      // Query reminders that are due and not yet sent
      // This includes both new reminders (scheduledTime <= now) and retries
      const dueReminders = await db
        .collection("reminders")
        .where("sent", "==", false)
        .where("scheduledTime", "<=", now)
        .limit(100) // Process up to 100 reminders per run
        .get();

      // Also get reminders that are ready for retry (have nextRetryTime <= now)
      const retryReminders = await db
        .collection("reminders")
        .where("sent", "==", false)
        .where("nextRetryTime", "<=", now)
        .limit(50) // Process up to 50 retry reminders per run
        .get();

      // Combine and deduplicate by reminder ID
      const allReminders = new Map();
      dueReminders.docs.forEach((doc) => {
        allReminders.set(doc.id, doc);
      });
      retryReminders.docs.forEach((doc) => {
        allReminders.set(doc.id, doc);
      });

      const remindersToProcess = Array.from(allReminders.values());

      console.log(
        `Found ${dueReminders.size} due reminders and ${retryReminders.size} retry reminders (${remindersToProcess.length} total to process)`
      );

      const batch = db.batch();

      for (const reminderDoc of remindersToProcess) {
        const reminder = reminderDoc.data();
        const reminderId = reminderDoc.id;

        // Skip if this is a retry reminder that's not ready yet
        if (reminder.nextRetryTime) {
          const nextRetryTime = reminder.nextRetryTime.toDate();
          if (nextRetryTime > now.toDate()) {
            // Not ready for retry yet, skip
            continue;
          }
        }

        // Check if userId exists
        if (!reminder.userId) {
          console.error(
            `Reminder ${reminderId} is missing userId field, skipping`
          );
          // Mark as sent with error to avoid retrying indefinitely
          batch.update(reminderDoc.ref, {
            sent: true,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            error: "Missing userId field",
          });
          continue;
        }

        console.log(
          `Processing reminder: ${reminderId} for user: ${reminder.userId}`
        );

        // Get user's FCM token
        let fcmToken = null;
        try {
          // Try to get token from user document first
          const userDoc = await db
            .collection("users")
            .doc(reminder.userId)
            .get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            fcmToken = userData && userData.fcmToken;
          }

          // If not found, try fcm_tokens collection
          if (!fcmToken) {
            const tokenDoc = await db
              .collection("fcm_tokens")
              .doc(reminder.userId)
              .get();
            if (tokenDoc.exists) {
              const tokenData = tokenDoc.data();
              fcmToken = tokenData && tokenData.token;
            }
          }
        } catch (error) {
          console.error(
            `Error fetching FCM token for user ${reminder.userId}:`,
            error
          );
        }

        if (!fcmToken) {
          console.warn(
            `No FCM token found for user ${reminder.userId}, skipping reminder ${reminderId}`
          );
          // Mark as sent anyway to avoid retrying indefinitely
          batch.update(reminderDoc.ref, {
            sent: true,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            error: "No FCM token found",
          });
          continue;
        }

        // Determine channel and priority based on reminder type
        const reminderType = reminder.reminderType || "";
        let channelId = "due_reminders";
        let priority = "high";

        // Handle overdue reminders (both borrow and rental)
        if (reminderType === "overdue" || reminderType === "rental_overdue") {
          channelId =
            reminderType === "rental_overdue"
              ? "rental_overdue_reminders"
              : "overdue_reminders";
          priority = "max";
        } else if (reminderType.startsWith("monthly_payment")) {
          // Handle monthly payment reminders for long-term rentals
          channelId = "rental_reminders";
          priority =
            reminderType === "monthly_payment_overdue" ? "max" : "high";
        } else if (reminderType.startsWith("rental_")) {
          // Handle other rental reminder types (rental_24h, rental_1h, rental_due)
          channelId = "rental_reminders";
          priority = "high";
        }

        // Prepare FCM message
        const message = {
          token: fcmToken,
          notification: {
            title: reminder.title || "Reminder",
            body: reminder.body || "",
          },
          data: {
            reminderId: reminderId,
            itemId: reminder.itemId || "",
            reminderType: reminderType,
            type: "reminder",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            priority: priority,
            notification: {
              channelId: channelId,
              priority: priority,
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
        };

        // Send FCM notification with retry logic
        let sendSuccess = false;
        let lastError = null;
        const maxRetries = 3;
        let retryCount = reminder.retryCount || 0;
        const maxRetryDelay = 24 * 60 * 60 * 1000; // 24 hours in milliseconds

        // Check if reminder is too old to retry (more than 24 hours past scheduled time)
        const scheduledTime = reminder.scheduledTime.toDate();
        const timeSinceScheduled = now.toDate() - scheduledTime;
        if (timeSinceScheduled > maxRetryDelay) {
          console.warn(
            `Reminder ${reminderId} is too old (${Math.floor(timeSinceScheduled / (60 * 60 * 1000))} hours), marking as failed`
          );
          batch.update(reminderDoc.ref, {
            sent: true,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            error: "Reminder too old to retry",
            retryCount: retryCount,
          });
          continue;
        }

        // Check if we've exceeded max retries
        if (retryCount >= maxRetries) {
          console.warn(
            `Reminder ${reminderId} exceeded max retries (${retryCount}), marking as failed`
          );
          batch.update(reminderDoc.ref, {
            sent: true,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            error: `Failed after ${retryCount} retries`,
            retryCount: retryCount,
          });
          continue;
        }

        try {
          await admin.messaging().send(message);
          sendSuccess = true;
          console.log(
            `Successfully sent reminder ${reminderId} to user ${reminder.userId}`
          );

          // Create notification in notifications collection for return reminders
          if (
            reminderType === "24h" ||
            reminderType === "1h" ||
            reminderType === "due"
          ) {
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            const todayStart = admin.firestore.Timestamp.fromDate(today);
            const todayEnd = admin.firestore.Timestamp.fromDate(
              new Date(today.getTime() + 24 * 60 * 60 * 1000)
            );

            const notificationType = `return_reminder_${reminderType}`;

            const existingNotification = await db
              .collection("notifications")
              .where("toUserId", "==", reminder.userId)
              .where("type", "==", notificationType)
              .where("itemId", "==", reminder.itemId || "")
              .where("createdAt", ">=", todayStart)
              .where("createdAt", "<", todayEnd)
              .limit(1)
              .get();

            if (existingNotification.empty) {
              await db.collection("notifications").add({
                toUserId: reminder.userId,
                type: notificationType,
                itemId: reminder.itemId || "",
                itemTitle: reminder.itemTitle || "Item",
                title: reminder.title || "",
                message: reminder.body || "",
                borrowerName: reminder.borrowerName || "",
                lenderName: reminder.lenderName || "",
                status: "unread",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(
                `Created return reminder notification for user ${reminder.userId}`
              );
            }
          }

          // For monthly payment reminders, also create notification in notifications collection
          if (reminderType.startsWith("monthly_payment")) {
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            const todayStart = admin.firestore.Timestamp.fromDate(today);
            const todayEnd = admin.firestore.Timestamp.fromDate(
              new Date(today.getTime() + 24 * 60 * 60 * 1000)
            );

            const notificationType =
              reminderType === "monthly_payment_overdue"
                ? "rental_monthly_payment_overdue"
                : "rental_monthly_payment_due";

            const existingNotification = await db
              .collection("notifications")
              .where("toUserId", "==", reminder.userId)
              .where("type", "==", notificationType)
              .where("requestId", "==", reminder.rentalRequestId || "")
              .where("createdAt", ">=", todayStart)
              .where("createdAt", "<", todayEnd)
              .limit(1)
              .get();

            if (existingNotification.empty && reminder.rentalRequestId) {
              await db.collection("notifications").add({
                toUserId: reminder.userId,
                type: notificationType,
                itemId: reminder.itemId || "",
                itemTitle: reminder.itemTitle || "Rental Item",
                requestId: reminder.rentalRequestId,
                monthlyAmount: reminder.monthlyAmount || 0,
                message: reminder.body || "",
                status: "unread",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(
                `Created monthly payment notification for user ${reminder.userId}`
              );
            }
          }

          // Mark reminder as sent (only if send was successful)
          if (sendSuccess) {
            batch.update(reminderDoc.ref, {
              sent: true,
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
              retryCount: 0, // Reset retry count on success
              lastError: null,
            });
          }

          // If this is an overdue reminder, schedule the next one for tomorrow at 9 AM
          if (
            reminder.reminderType === "overdue" ||
            reminder.reminderType === "rental_overdue"
          ) {
            const nextScheduledTime = new Date();
            nextScheduledTime.setDate(nextScheduledTime.getDate() + 1);
            nextScheduledTime.setHours(9, 0, 0, 0);

            // Preserve the reminder type (overdue or rental_overdue)
            const reminderType = reminder.reminderType;

            // Use the same reminder ID format based on type
            // For borrow: itemId_overdue_userId
            // For rental: rental_{requestId}_overdue_{userId} (preserve original format)
            let nextReminderId;
            if (reminderType === "rental_overdue") {
              // Extract rental request ID from the original reminder ID if available
              // Format: rental_{requestId}_overdue_{userId}
              const originalId = reminderId;
              if (
                originalId.startsWith("rental_") &&
                originalId.includes("_overdue_")
              ) {
                nextReminderId = originalId; // Use same ID format for recurring rental overdue
              } else {
                // Fallback: construct from available data
                const rentalRequestId =
                  reminder.rentalRequestId || reminder.itemId;
                nextReminderId = `rental_${rentalRequestId}_overdue_${reminder.userId}`;
              }
            } else {
              nextReminderId = `${reminder.itemId}_overdue_${reminder.userId}`;
            }

            // Prepare reminder data
            const nextReminderData = {
              userId: reminder.userId,
              itemId: reminder.itemId,
              itemTitle: reminder.itemTitle,
              scheduledTime:
                admin.firestore.Timestamp.fromDate(nextScheduledTime),
              title: reminder.title,
              body: reminder.body,
              reminderType: reminderType,
              isBorrower: reminder.isBorrower,
              sent: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };

            // Add optional fields if they exist
            if (reminder.borrowerName)
              nextReminderData.borrowerName = reminder.borrowerName;
            if (reminder.lenderName)
              nextReminderData.lenderName = reminder.lenderName;
            if (reminder.rentalRequestId)
              nextReminderData.rentalRequestId = reminder.rentalRequestId;
            if (reminder.ownerName)
              nextReminderData.ownerName = reminder.ownerName;
            if (reminder.renterName)
              nextReminderData.renterName = reminder.renterName;

            batch.set(
              db.collection("reminders").doc(nextReminderId),
              nextReminderData
            );
          }
        } catch (error) {
          lastError = error;
          console.error(
            `Error sending FCM message for reminder ${reminderId}:`,
            error
          );

          // Check error type to determine if we should retry
          const errorCode = error.code || "";
          const errorMessage = error.message || "";

          // Non-retryable errors (client errors)
          const nonRetryableErrors = [
            "invalid-argument",
            "invalid-registration-token",
            "registration-token-not-registered",
            "invalid-package-name",
            "authentication-error",
            "messaging/invalid-argument",
            "messaging/invalid-registration-token",
            "messaging/registration-token-not-registered",
            "messaging/invalid-package-name",
            "messaging/authentication-error",
          ];

          const isNonRetryable =
            nonRetryableErrors.some(
              (code) =>
                errorCode.includes(code) || errorMessage.includes(code)
            ) ||
            errorCode === "messaging/invalid-argument" ||
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered";

          if (isNonRetryable) {
            // Don't retry - mark as sent with error
            console.warn(
              `Non-retryable error for reminder ${reminderId}: ${errorCode}`
            );
            batch.update(reminderDoc.ref, {
              sent: true,
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
              error: `Non-retryable: ${errorCode || errorMessage}`,
              retryCount: retryCount,
              lastError: errorMessage,
            });
            continue;
          }

          // Retryable error - schedule retry with exponential backoff
          retryCount++;
          const backoffDelay = Math.min(
            Math.pow(2, retryCount - 1) * 60 * 1000, // Exponential: 1min, 2min, 4min
            60 * 60 * 1000 // Max 1 hour delay
          );
          const nextRetryTime = new Date(
            now.toDate().getTime() + backoffDelay
          );

          console.log(
            `Scheduling retry ${retryCount}/${maxRetries} for reminder ${reminderId} at ${nextRetryTime.toISOString()}`
          );

          // Update reminder with retry info
          batch.update(reminderDoc.ref, {
            retryCount: retryCount,
            lastError: errorMessage,
            lastRetryAttempt: admin.firestore.FieldValue.serverTimestamp(),
            nextRetryTime: admin.firestore.Timestamp.fromDate(nextRetryTime),
            // Keep sent = false so it will be picked up again
          });
        }
      }

      // Commit all updates
      await batch.commit();
      console.log("Completed processing reminders");

      return null;
    } catch (error) {
      console.error("Error in checkAndSendReminders:", error);
      throw error;
    }
  });

/**
 * HTTP function to manually trigger reminder check (for testing)
 */
exports.manualCheckReminders = functions.https.onRequest(async (req, res) => {
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();

  try {
    const dueReminders = await db
      .collection("reminders")
      .where("sent", "==", false)
      .where("scheduledTime", "<=", now)
      .limit(10)
      .get();

    res.json({
      success: true,
      message: `Found ${dueReminders.size} due reminders`,
      reminders: dueReminders.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      })),
    });
  } catch (error) {
    console.error("Error in manualCheckReminders:", error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

/**
 * Cloud Function that triggers when a new borrow request is created
 * Sends an FCM push notification to the lender
 */
exports.onBorrowRequestCreated = functions.firestore
  .document("borrow_requests/{requestId}")
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const requestData = snap.data();
    const requestId = context.params.requestId;

    // Only send notification for pending requests
    if (requestData.status !== "pending") {
      console.log(
        `Borrow request ${requestId} is not pending, skipping notification`
      );
      return null;
    }

    const lenderId = requestData.lenderId;
    const borrowerName = requestData.borrowerName || "Someone";
    const itemTitle = requestData.itemTitle || "an item";

    console.log(
      `New borrow request ${requestId} from ${borrowerName} for item: ${itemTitle}`
    );

    // Get lender's FCM token
    let fcmToken = null;
    const borrowerId = requestData.borrowerId;
    try {
      // Try to get token from user document first
      const userDoc = await db.collection("users").doc(lenderId).get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        fcmToken = userData && userData.fcmToken;
        const tokenUpdatedAt = userData && userData.fcmTokenUpdatedAt;
        console.log(
          `FCM token found in user document for lender ${lenderId}: ${
            fcmToken ? "exists" : "missing"
          }`
        );
        if (tokenUpdatedAt) {
          console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
        }
      } else {
        console.log(`User document not found for lender ${lenderId}`);
      }

      // If not found, try fcm_tokens collection
      if (!fcmToken) {
        const tokenDoc = await db.collection("fcm_tokens").doc(lenderId).get();
        if (tokenDoc.exists) {
          const tokenData = tokenDoc.data();
          fcmToken = tokenData && tokenData.token;
          const tokenUpdatedAt = tokenData && tokenData.updatedAt;
          console.log(
            "FCM token found in fcm_tokens collection for lender " +
              `${lenderId}: ${fcmToken ? "exists" : "missing"}`
          );
          if (tokenUpdatedAt) {
            console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
          }
        } else {
          console.log(
            "FCM token document not found in fcm_tokens collection " +
              `for lender ${lenderId}`
          );
        }
      }

      // Safety check: Verify we're not accidentally using borrower's token
      if (fcmToken && borrowerId) {
        // Check if borrower's token matches (this would indicate a problem)
        const borrowerDoc = await db.collection("users").doc(borrowerId).get();
        if (borrowerDoc.exists) {
          const borrowerData = borrowerDoc.data();
          const borrowerToken = borrowerData && borrowerData.fcmToken;
          if (borrowerToken === fcmToken) {
            console.error(
              "WARNING: Lender's FCM token matches borrower's token! " +
                "This means the notification will go to the borrower. " +
                `LenderId: ${lenderId}, BorrowerId: ${borrowerId}`
            );
            // Don't send notification if tokens match to prevent sending to wrong user
            return null;
          }
        }
      }
    } catch (error) {
      console.error(`Error fetching FCM token for lender ${lenderId}:`, error);
      return null;
    }

    if (!fcmToken) {
      console.warn(
        `No FCM token found for lender ${lenderId}, ` +
          "cannot send notification"
      );
      return null;
    }

    console.log(
      `Sending FCM notification to lender ${lenderId} ` +
        `(NOT borrower ${borrowerId})`
    );

    // Prepare FCM message
    const message = {
      token: fcmToken,
      notification: {
        title: "New Borrow Request",
        body: `${borrowerName} wants to borrow "${itemTitle}"`,
      },
      data: {
        type: "borrow_request",
        requestId: requestId,
        itemId: requestData.itemId || "",
        itemTitle: itemTitle,
        borrowerId: requestData.borrowerId || "",
        borrowerName: borrowerName,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "borrow_requests",
          priority: "high",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    // Send FCM notification
    try {
      await admin.messaging().send(message);
      console.log(
        `Successfully sent borrow request notification to lender ${lenderId}`
      );
      return null;
    } catch (error) {
      console.error(
        `Error sending FCM notification for borrow request ${requestId}:`,
        error
      );
      // Don't throw - we don't want to fail the borrow request creation if notification fails
      return null;
    }
  });

/**
 * Cloud Function that triggers when a new rental request is created
 * Sends an FCM push notification to the owner
 */
exports.onRentalRequestCreated = functions.firestore
  .document("rental_requests/{requestId}")
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const requestData = snap.data();
    const requestId = context.params.requestId;

    console.log(
      `[onRentalRequestCreated] Triggered for rental request ${requestId}`
    );
    console.log("[onRentalRequestCreated] Request data:", {
      status: requestData.status,
      rentType: requestData.rentType,
      ownerId: requestData.ownerId,
      renterId: requestData.renterId,
      itemTitle: requestData.itemTitle,
    });

    // Only send notification for requested/pending requests
    const status = requestData.status || "";
    console.log(`[onRentalRequestCreated] Checking status: "${status}"`);

    if (status !== "pending" && status !== "requested") {
      console.log(
        `[onRentalRequestCreated] Rental request ${requestId} is not ` +
          `pending/requested (status: "${status}"), skipping notification`
      );
      return null;
    }

    const ownerId = requestData.ownerId;
    const renterId = requestData.renterId;

    if (!ownerId) {
      console.error(
        `[onRentalRequestCreated] ERROR: No ownerId found in rental ` +
          `request ${requestId}`
      );
      return null;
    }

    if (!renterId) {
      console.error(
        `[onRentalRequestCreated] ERROR: No renterId found in rental ` +
          `request ${requestId}`
      );
      return null;
    }

    console.log(
      `[onRentalRequestCreated] Processing request - Owner: ${ownerId}, ` +
        `Renter: ${renterId}`
    );
    const itemTitle = requestData.itemTitle || "an item";

    // Fetch renter name from user document
    let renterName = "Someone";
    try {
      const renterDoc = await db.collection("users").doc(renterId).get();
      if (renterDoc.exists) {
        const renterData = renterDoc.data();
        const firstName = renterData.firstName || "";
        const lastName = renterData.lastName || "";
        renterName = `${firstName} ${lastName}`.trim();
        if (renterName === "") {
          renterName = renterData.email || "Someone";
        }
      }
    } catch (error) {
      console.error(`Error fetching renter name for ${renterId}:`, error);
    }

    console.log(
      `[onRentalRequestCreated] New rental request ${requestId} from ` +
        `${renterName} for item: ${itemTitle} (rentType: ` +
        `${requestData.rentType || "unknown"})`
    );

    // Get owner's FCM token
    let fcmToken = null;
    try {
      // Try to get token from user document first
      const userDoc = await db.collection("users").doc(ownerId).get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        fcmToken = userData && userData.fcmToken;
        const tokenUpdatedAt = userData && userData.fcmTokenUpdatedAt;
        console.log(
          `FCM token found in user document for owner ${ownerId}: ` +
            `${fcmToken ? "exists" : "missing"}`
        );
        if (tokenUpdatedAt) {
          console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
        }
      } else {
        console.log(`User document not found for owner ${ownerId}`);
      }

      // If not found, try fcm_tokens collection
      if (!fcmToken) {
        const tokenDoc = await db.collection("fcm_tokens").doc(ownerId).get();
        if (tokenDoc.exists) {
          const tokenData = tokenDoc.data();
          fcmToken = tokenData && tokenData.token;
          const tokenUpdatedAt = tokenData && tokenData.updatedAt;
          console.log(
            "FCM token found in fcm_tokens collection for owner " +
              `${ownerId}: ${fcmToken ? "exists" : "missing"}`
          );
          if (tokenUpdatedAt) {
            console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
          }
        } else {
          console.log(
            "FCM token document not found in fcm_tokens collection " +
              `for owner ${ownerId}`
          );
        }
      }

      // Safety check: Verify we're not accidentally using renter's token
      if (fcmToken && renterId) {
        // Check if renter's token matches (this would indicate a problem)
        const renterDoc = await db.collection("users").doc(renterId).get();
        if (renterDoc.exists) {
          const renterData = renterDoc.data();
          const renterToken = renterData && renterData.fcmToken;
          if (renterToken === fcmToken) {
            console.error(
              "WARNING: Owner's FCM token matches renter's token! " +
                "This means the notification will go to the renter. " +
                `OwnerId: ${ownerId}, RenterId: ${renterId}`
            );
            // Don't send notification if tokens match to prevent sending to wrong user
            return null;
          }
        }
      }
    } catch (error) {
      console.error(`Error fetching FCM token for owner ${ownerId}:`, error);
      return null;
    }

    if (!fcmToken) {
      console.warn(
        "[onRentalRequestCreated] No FCM token found for owner " +
          `${ownerId}, cannot send notification`
      );
      return null;
    }

    console.log(
      "[onRentalRequestCreated] Sending FCM notification to owner " +
        `${ownerId} (NOT renter ${renterId})`
    );

    // Prepare FCM message
    const message = {
      token: fcmToken,
      notification: {
        title: "New Rental Request",
        body: `${renterName} wants to rent "${itemTitle}"`,
      },
      data: {
        type: "rent_request",
        requestId: requestId,
        itemId: requestData.itemId || "",
        itemTitle: itemTitle,
        renterId: requestData.renterId || "",
        renterName: renterName,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "rental_requests",
          priority: "high",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    // Send FCM notification
    try {
      await admin.messaging().send(message);
      console.log(
        "[onRentalRequestCreated] Successfully sent rental request " +
          `notification to owner ${ownerId} for request ${requestId}`
      );
      return null;
    } catch (error) {
      console.error(
        "[onRentalRequestCreated] Error sending FCM notification for " +
          `rental request ${requestId}:`,
        error
      );
      // Don't throw - we don't want to fail the rental request creation if notification fails
      return null;
    }
  });

/**
 * Cloud Function that triggers when a new notification document is created.
 * Used here to send FCM push notifications for accepted/declined
 * borrow and rental requests.
 *
 * This keeps the FCM logic centralized and driven by the notifications
 * written by the Flutter app (`notifications` collection).
 */
exports.onNotificationCreated = functions.firestore
  .document("notifications/{notificationId}")
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const notificationId = context.params.notificationId;
    const notif = snap.data();

    console.log(
      `[onNotificationCreated] Triggered for notification ${notificationId}`
    );
    console.log(`[onNotificationCreated] Notification data:`, notif);

    if (!notif) {
      console.warn(
        `[onNotificationCreated] Empty notification payload for ` +
          `${notificationId}, skipping`
      );
      return null;
    }

    const type = notif.type;
    const decision = (notif.decision || "").toLowerCase();
    const toUserId = notif.toUserId;

    console.log(
      `[onNotificationCreated] Processing notification type: ${type}, ` +
        `toUserId: ${toUserId}`
    );

    // Only handle the specific decision/offer/message/donation/calamity/dispute/verification/missing_item notifications requested
    const handledTypes = [
      "borrow_request_decision",
      "rent_request_decision",
      "trade_offer",
      "trade_counter_offer",
      "trade_offer_decision",
      "chat_message",
      "message",
      "donation_request",
      "donation_request_decision",
      "calamity_event_created",
      "calamity_donation_received",
      "borrow_return_initiated",
      "borrow_return_confirmed",
      "borrow_return_disputed",
      "rent_return_initiated",
      "rent_return_verified",
      "item_overdue",
      "item_overdue_lender",
      "rental_overdue",
      "rental_overdue_owner",
      "dispute_compensation_proposed",
      "dispute_compensation_accepted",
      "dispute_compensation_rejected",
      "verification_approved",
      "verification_rejected",
      "missing_item_reported",
      "missing_item_reported_against_you",
      "missing_item_resolved",
    ];

    if (!handledTypes.includes(type)) {
      // Not a notification we care about for FCM
      console.log(
        `[onNotificationCreated] Notification type "${type}" is not handled, skipping FCM`
      );
      return null;
    }

    console.log(
      `[onNotificationCreated] Notification type "${type}" is handled, proceeding with FCM`
    );

    if (!toUserId) {
      console.warn(
        `[onNotificationCreated] No toUserId for notification ` +
          `${notificationId} (type: ${type}), skipping`
      );
      return null;
    }

    console.log(
      `[onNotificationCreated] Processing decision notification ` +
        `${notificationId} for user ${toUserId} (type: ${type}, ` +
        `decision: ${decision})`
    );

    // Resolve FCM token for the target user (same strategy as other functions)
    let fcmToken = null;
    try {
      // 1) Try user document
      const userDoc = await db.collection("users").doc(toUserId).get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        fcmToken = userData && userData.fcmToken;
        const tokenUpdatedAt = userData && userData.fcmTokenUpdatedAt;
        console.log(
          `FCM token found in user document for user ${toUserId}: ` +
            `${fcmToken ? "exists" : "missing"}`
        );
        if (tokenUpdatedAt) {
          console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
        }
      } else {
        console.log(
          `[onNotificationCreated] User document not found for ` +
            `user ${toUserId}`
        );
      }

      // 2) If still not found, try fcm_tokens collection
      if (!fcmToken) {
        const tokenDoc = await db.collection("fcm_tokens").doc(toUserId).get();
        if (tokenDoc.exists) {
          const tokenData = tokenDoc.data();
          fcmToken = tokenData && tokenData.token;
          const tokenUpdatedAt = tokenData && tokenData.updatedAt;
          console.log(
            "FCM token found in fcm_tokens collection for user " +
              `${toUserId}: ${fcmToken ? "exists" : "missing"}`
          );
          if (tokenUpdatedAt) {
            console.log(
              "[onNotificationCreated] Token last updated at: " +
                tokenUpdatedAt.toDate()
            );
          }
        } else {
          console.log(
            "FCM token document not found in fcm_tokens collection " +
              `for user ${toUserId}`
          );
        }
      }
    } catch (error) {
      console.error(
        `[onNotificationCreated] Error fetching FCM token for ` +
          `user ${toUserId}:`,
        error
      );
      return null;
    }

    if (!fcmToken) {
      console.warn(
        "[onNotificationCreated] No FCM token found for user " +
          `${toUserId}, cannot send push notification for ` +
          `notification ${notificationId}`
      );
      return null;
    }

    const itemTitle = notif.itemTitle || "an item";
    let title = "Notification";
    let body = "You have a new notification.";
    let channelId = "general";
    let dataType = type;
    let priority = "high"; // Default priority, can be overridden for urgent notifications

    // Build a more specific title/body based on type + decision
    if (type === "borrow_request_decision") {
      channelId = "borrow_requests";
      dataType = "borrow_request_decision";
      if (decision === "accepted") {
        title = "Borrow Request Accepted";
        body = `Your request to borrow "${itemTitle}" was accepted.`;
      } else if (decision === "declined") {
        title = "Borrow Request Declined";
        body = `Your request to borrow "${itemTitle}" was declined.`;
      } else {
        title = "Borrow Request Updated";
        body = `Your borrow request for "${itemTitle}" was updated.`;
      }
    } else if (type === "rent_request_decision") {
      channelId = "rental_requests";
      dataType = "rent_request_decision";
      if (decision === "accepted") {
        title = "Rental Request Accepted";
        body = `Your request to rent "${itemTitle}" was accepted.`;
      } else if (decision === "declined") {
        title = "Rental Request Declined";
        body = `Your request to rent "${itemTitle}" was declined.`;
      } else {
        title = "Rental Request Updated";
        body = `Your rental request for "${itemTitle}" was updated.`;
      }
    } else if (type === "trade_offer") {
      // Someone made a trade offer on the user's listing
      channelId = "trade_offers";
      dataType = "trade_offer";
      const fromUserName = notif.fromUserName || "Someone";
      title = "New Trade Offer";
      body = `${fromUserName} sent you a trade offer for "${itemTitle}".`;
    } else if (type === "trade_counter_offer") {
      // Listing owner made a counter-offer in response to a trade offer
      channelId = "trade_offers";
      dataType = "trade_counter_offer";
      const fromUserName = notif.fromUserName || "The owner";
      title = "New Counter-Offer";
      body = `${fromUserName} sent you a counter-offer for "${itemTitle}".`;
    } else if (type === "trade_offer_decision") {
      // Owner accepted/declined a trade offer
      channelId = "trade_offers";
      dataType = "trade_offer_decision";
      const ownerName = notif.ownerName || "The owner";
      if (decision === "accepted") {
        title = "Trade Offer Accepted";
        body = `${ownerName} accepted your trade offer for "${itemTitle}".`;
      } else if (decision === "declined") {
        title = "Trade Offer Declined";
        body = `${ownerName} declined your trade offer for "${itemTitle}".`;
      } else {
        title = "Trade Offer Updated";
        body = `Your trade offer for "${itemTitle}" was updated.`;
      }
    } else if (type === "chat_message" || type === "message") {
      // New chat or group chat message
      channelId = "messages";
      dataType = "chat_message";
      const senderName = notif.senderName || "Someone";
      const isGroup = !!notif.isGroup;
      const groupName = notif.groupName || "";

      if (isGroup && groupName) {
        title = `New message in ${groupName}`;
        body = `${senderName}: ${notif.content || "Sent a message"}`;
      } else {
        title = "New message";
        body = `${senderName}: ${notif.content || "Sent a message"}`;
      }
    } else if (type === "donation_request") {
      // Approval required: someone requested to claim a giveaway
      channelId = "donations";
      dataType = "donation_request";
      const claimantName = notif.fromUserName || "Someone";
      title = "New Claim Request";
      body = `${claimantName} requested to claim "${itemTitle}".`;
    } else if (type === "donation_request_decision") {
      // Donor accepted/declined a claim
      channelId = "donations";
      dataType = "donation_request_decision";
      const donorName = notif.donorName || "The donor";
      const customMessage = notif.message; // Use custom message if provided
      if (decision === "accepted") {
        title = "Claim Request Approved";
        body =
          customMessage ||
          `${donorName} approved your claim request for "${itemTitle}".`;
      } else if (decision === "declined") {
        title = "Claim Request Declined";
        body =
          customMessage ||
          `${donorName} declined your claim request for "${itemTitle}".`;
      } else {
        title = "Claim Request Updated";
        body =
          customMessage || `Your claim request for "${itemTitle}" was updated.`;
      }
    } else if (type === "calamity_event_created") {
      // New calamity relief event posted by admin
      channelId = "calamity_events";
      dataType = "calamity_event_created";
      const eventTitle = notif.eventTitle || "New Calamity Relief Event";
      const calamityType = notif.calamityType || "";
      const rawDescription = notif.eventDescription || "";

      // Keep description reasonably short for notification body
      let shortDescription = rawDescription;
      if (shortDescription.length > 140) {
        shortDescription = shortDescription.substring(0, 137) + "...";
      }

      if (calamityType) {
        title = `New ${calamityType} Relief Event`;
        body = shortDescription
          ? `${eventTitle}: ${shortDescription}`
          : `"${eventTitle}" is now active. Open the app to see how you can help.`;
      } else {
        title = "New Calamity Relief Event";
        body = shortDescription
          ? `${eventTitle}: ${shortDescription}`
          : `"${eventTitle}" is now active. Open the app to see how you can help.`;
      }
    } else if (type === "calamity_donation_received") {
      // Admin marked user's donation as received
      channelId = "calamity_events";
      dataType = "calamity_donation_received";
      const eventTitle = notif.eventTitle || "Calamity Event";
      const itemType = notif.itemType || "items";
      const quantity = notif.quantity || 0;
      title = "Donation Received";
      body = `Your donation of ${quantity} ${itemType} for "${eventTitle}" has been received.`;
    } else if (type === "borrow_return_initiated") {
      // Borrower initiated return - notify lender
      channelId = "borrow_requests";
      dataType = "borrow_return_initiated";
      const borrowerName = notif.fromUserName || "The borrower";
      title = "Return Initiated";
      body = `${borrowerName} has initiated return for "${itemTitle}". Please confirm the return.`;
     } else if (type === "borrow_return_confirmed") {
       // Lender confirmed/accepted the return - notify borrower
       channelId = "borrow_requests";
       dataType = "borrow_return_confirmed";
       const lenderName = notif.fromUserName || "The lender";
       title = "Return Confirmed";
       body = `${lenderName} has confirmed the return of "${itemTitle}". Thank you!`;
     } else if (type === "rent_return_initiated") {
       // Renter initiated return - notify owner
       channelId = "rental_requests";
       dataType = "rent_return_initiated";
       const renterName = notif.fromUserName || "The renter";
       const rentType = notif.rentType || "item";
       const message = notif.message || `Rental return initiated for "${itemTitle}"`;
       title = "Rental Return Initiated";
       body = `${renterName} has initiated return for "${itemTitle}". Please verify the return.`;
     } else if (type === "rent_return_verified") {
       // Owner verified/accepted the return - notify renter
       channelId = "rental_requests";
       dataType = "rent_return_verified";
       const ownerName = notif.ownerName || "The owner";
       const message = notif.message || `Owner has verified the return. Rental completed!`;
       title = "Rental Return Verified";
       body = `${ownerName} has verified the return of "${itemTitle}". ${message}`;
     } else if (type === "item_overdue") {
       // Borrowed item is overdue - notify borrower
       console.log(
         `[onNotificationCreated] Processing item_overdue notification ` +
           `for borrower ${toUserId}`
       );
       channelId = "overdue_reminders";
       dataType = "item_overdue";
       const lenderName = notif.lenderName || "The lender";
       const daysOverdue = notif.daysOverdue || 0;
       title = "⚠️ Overdue Item";
       if (daysOverdue === 0) {
         body = `Your borrowed item "${itemTitle}" is due today. Please return it to ${lenderName}.`;
       } else if (daysOverdue === 1) {
         body = `Your borrowed item "${itemTitle}" is 1 day overdue. Please return it to ${lenderName}.`;
       } else {
         body = `Your borrowed item "${itemTitle}" is ${daysOverdue} days overdue. Please return it to ${lenderName}.`;
       }
       priority = "high"; // FCM android.priority only accepts "normal" or "high"
       console.log(
         `[onNotificationCreated] item_overdue - title: "${title}", ` +
           `body: "${body}", daysOverdue: ${daysOverdue}`
       );
     } else if (type === "item_overdue_lender") {
       // Borrowed item is overdue - notify lender
       channelId = "overdue_reminders";
       dataType = "item_overdue_lender";
       const borrowerName = notif.borrowerName || "The borrower";
       const daysOverdue = notif.daysOverdue || 0;
       title = "⚠️ Overdue Item";
       if (daysOverdue === 0) {
         body = `The item "${itemTitle}" borrowed by ${borrowerName} is due today.`;
       } else if (daysOverdue === 1) {
         body = `The item "${itemTitle}" borrowed by ${borrowerName} is 1 day overdue.`;
       } else {
         body = `The item "${itemTitle}" borrowed by ${borrowerName} is ${daysOverdue} days overdue.`;
       }
       priority = "high"; // Use "high" instead of "max" - FCM only accepts "normal" or "high"
     } else if (type === "rental_overdue") {
       // Rental is overdue - notify renter
       channelId = "rental_overdue_reminders";
       dataType = "rental_overdue";
       const ownerName = notif.ownerName || "The owner";
       const daysOverdue = notif.daysOverdue || 0;
       const rentType = notif.rentType || "item";
       title = "⚠️ Rental Overdue";
       if (daysOverdue === 0) {
         body = `Your rental "${itemTitle}" is due today. Please return it to ${ownerName}.`;
       } else if (daysOverdue === 1) {
         body = `Your rental "${itemTitle}" is 1 day overdue. Please return it to ${ownerName}.`;
       } else {
         body = `Your rental "${itemTitle}" is ${daysOverdue} days overdue. Please return it to ${ownerName}.`;
       }
       priority = "high"; // Use "high" instead of "max" - FCM only accepts "normal" or "high"
     } else if (type === "rental_overdue_owner") {
       // Rental is overdue - notify owner
       channelId = "rental_overdue_reminders";
       dataType = "rental_overdue_owner";
       const renterName = notif.renterName || "The renter";
       const daysOverdue = notif.daysOverdue || 0;
       const rentType = notif.rentType || "item";
       title = "⚠️ Rental Overdue";
       if (daysOverdue === 0) {
         body = `The ${rentType} "${itemTitle}" rented by ${renterName} is due today.`;
       } else if (daysOverdue === 1) {
         body = `The ${rentType} "${itemTitle}" rented by ${renterName} is 1 day overdue.`;
       } else {
         body = `The ${rentType} "${itemTitle}" rented by ${renterName} is ${daysOverdue} days overdue.`;
       }
       priority = "high"; // FCM android.priority only accepts "normal" or "high"
     } else if (type === "borrow_return_disputed") {
      // Lender disputed the return condition
      channelId = "borrow_requests";
      dataType = "borrow_return_disputed";
      const lenderName = notif.fromUserName || "The lender";
      title = "Return Disputed";
      body = `${lenderName} disputed the return condition for "${itemTitle}". Please review the damage report.`;
    } else if (type === "dispute_compensation_proposed") {
      // Lender proposed compensation amount
      channelId = "borrow_requests";
      dataType = "dispute_compensation_proposed";
      const lenderName = notif.fromUserName || "The lender";
      const amount = notif.amount || 0;
      const amountText = amount > 0 ? `₱${amount.toFixed(2)}` : "";
      title = "Compensation Proposal";
      if (amountText) {
        body = `${lenderName} proposed compensation of ${amountText} for "${itemTitle}". Please review and respond.`;
      } else {
        body = `${lenderName} proposed compensation for "${itemTitle}". Please review and respond.`;
      }
    } else if (type === "dispute_compensation_accepted") {
      // Borrower accepted the compensation proposal
      channelId = "borrow_requests";
      dataType = "dispute_compensation_accepted";
      const borrowerName = notif.fromUserName || "The borrower";
      const amount = notif.amount || 0;
      const amountText = amount > 0 ? `₱${amount.toFixed(2)}` : "";
      title = "Compensation Accepted";
      if (amountText) {
        body = `${borrowerName} accepted your compensation proposal of ${amountText} for "${itemTitle}".`;
      } else {
        body = `${borrowerName} accepted your compensation proposal for "${itemTitle}".`;
      }
    } else if (type === "dispute_compensation_rejected") {
      // Borrower rejected the compensation proposal
      channelId = "borrow_requests";
      dataType = "dispute_compensation_rejected";
      const borrowerName = notif.fromUserName || "The borrower";
      title = "Compensation Rejected";
      body = `${borrowerName} rejected your compensation proposal for "${itemTitle}". You can propose a new amount.`;
    } else if (type === "verification_approved") {
      // User's account verification was approved by admin
      channelId = "general";
      dataType = "verification_approved";
      title = notif.title || "Account Verified Successfully";
      body =
        notif.message ||
        "Congratulations! Your account has been verified. You can now post items, borrow, rent, and use all features of the app.";
    } else if (type === "verification_rejected") {
      // User's account verification was rejected by admin
      channelId = "general";
      dataType = "verification_rejected";
      title = notif.title || "Verification Rejected";
      const rejectionReason =
        notif.rejectionReason ||
        notif.message ||
        "Your verification request was rejected. Please check your ID submission and try again.";
      body = rejectionReason;
    } else if (type === "missing_item_reported") {
      // Admin notification about missing item report
      channelId = "admin_notifications";
      dataType = "missing_item_reported";
      const itemTitle = notif.itemTitle || "an item";
      const reporterName = notif.reporterName || "An owner";
      const reportedUserName = notif.reportedUserName || "a user";
      const daysOverdue = notif.daysOverdue || 0;
      title = "Missing Item Reported";
      body = `${reporterName} reported that "${itemTitle}" has not been returned by ${reportedUserName} (${daysOverdue} days overdue).`;
    } else if (type === "missing_item_reported_against_you") {
      // Borrower/renter notification that they've been reported
      channelId = "borrow_requests";
      dataType = "missing_item_reported_against_you";
      const itemTitle = notif.itemTitle || "an item";
      const reporterName = notif.fromUserName || "The owner";
      title = "Missing Item Report";
      body = `${reporterName} has reported that "${itemTitle}" has not been returned. Please return the item immediately.`;
    } else if (type === "missing_item_resolved") {
      // Admin notification that a missing item report has been resolved
      channelId = "admin_notifications";
      dataType = "missing_item_resolved";
      const itemTitle = notif.itemTitle || "an item";
      const reportedUserName = notif.reportedUserName || "a user";
      title = "Missing Item Resolved";
      body = `The item "${itemTitle}" that was reported as not returned has been returned by ${reportedUserName}.`;
    }

    const message = {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: {
        type: dataType,
        notificationId: notificationId,
        requestId: notif.requestId || "",
        itemId: notif.itemId || "",
        itemTitle: itemTitle,
        tradeItemId: notif.tradeItemId || "",
        offerId: notif.offerId || "",
        conversationId: notif.conversationId || "",
        eventId: notif.eventId || "",
        eventTitle: notif.eventTitle || "",
        donationId: notif.donationId || "",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: priority, // Message priority: "normal" or "high" (FCM requirement)
        notification: {
          channelId: channelId,
          priority: priority === "high" ? "max" : priority, // Notification priority: can be "max" for urgent
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    console.log(
      `[onNotificationCreated] Preparing to send FCM for notification ` +
        `${notificationId} (type: ${type}) to user ${toUserId}`
    );
    console.log(`[onNotificationCreated] FCM message:`, {
      token: fcmToken ? `${fcmToken.substring(0, 20)}...` : "MISSING",
      title,
      body,
      channelId,
      priority,
      dataType,
    });

    try {
      await admin.messaging().send(message);
      console.log(
        "[onNotificationCreated] ✅ Successfully sent FCM notification " +
          `for ${notificationId} (type: ${type}) to user ${toUserId}`
      );
    } catch (error) {
      console.error(
        "[onNotificationCreated] ❌ Error sending FCM notification for " +
          `notification ${notificationId} (type: ${type}):`,
        error
      );
      console.error(`[onNotificationCreated] Error details:`, {
        code: error.code,
        message: error.message,
        stack: error.stack,
      });
    }

    return null;
  });

/**
 * Cloud Function that triggers when a new trade item is created
 * Checks for matches with existing trade items and sends notifications
 */
exports.onTradeItemCreated = functions.firestore
  .document("trade_items/{tradeItemId}")
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const newTradeItem = snap.data();
    const newTradeItemId = context.params.tradeItemId;

    // Only process open trade items
    if (newTradeItem.status !== "Open") {
      console.log(
        `Trade item ${newTradeItemId} is not open, ` + "skipping match check"
      );
      return null;
    }

    const newOfferedBy = newTradeItem.offeredBy;
    const newOfferedName = (newTradeItem.offeredItemName || "")
      .toLowerCase()
      .trim();
    const newOfferedCategory = (newTradeItem.offeredCategory || "")
      .toLowerCase()
      .trim();
    const newDesiredName = (newTradeItem.desiredItemName || "")
      .toLowerCase()
      .trim();
    const newDesiredCategory = (newTradeItem.desiredCategory || "")
      .toLowerCase()
      .trim();

    console.log(`Checking matches for new trade item: ${newTradeItemId}`);

    try {
      // Get all open trade items (excluding the new one)
      const allOpenTrades = await db
        .collection("trade_items")
        .where("status", "==", "Open")
        .limit(500) // Limit to avoid timeout
        .get();

      const matches = [];
      const notificationsBatch = db.batch();

      for (const existingTradeDoc of allOpenTrades.docs) {
        // Skip the new trade item itself
        if (existingTradeDoc.id === newTradeItemId) {
          continue;
        }

        const existingTrade = existingTradeDoc.data();
        const existingOfferedBy = existingTrade.offeredBy;

        // Skip if it's from the same user
        if (existingOfferedBy === newOfferedBy) {
          continue;
        }

        const existingOfferedName = (existingTrade.offeredItemName || "")
          .toLowerCase()
          .trim();
        const existingOfferedCategory = (existingTrade.offeredCategory || "")
          .toLowerCase()
          .trim();
        const existingDesiredName = (existingTrade.desiredItemName || "")
          .toLowerCase()
          .trim();
        const existingDesiredCategory = (existingTrade.desiredCategory || "")
          .toLowerCase()
          .trim();

        let matchFound = false;
        let matchReason = "";
        let matchType = "";

        // Check: They want what you're offering (new item offers what existing item wants)
        if (newDesiredName && existingDesiredName) {
          if (
            newOfferedName.includes(existingDesiredName) ||
            existingDesiredName.includes(newOfferedName) ||
            newOfferedName === existingDesiredName
          ) {
            matchFound = true;
            matchReason = `They want "${existingTrade.desiredItemName}" and you offer "${newTradeItem.offeredItemName}"`;
            matchType = "they_want_what_you_offer";
          }
        }

        // Check: They offer what you want (new item wants what existing item offers)
        if (!matchFound && newDesiredName && existingOfferedName) {
          if (
            existingOfferedName.includes(newDesiredName) ||
            newDesiredName.includes(existingOfferedName) ||
            existingOfferedName === newDesiredName
          ) {
            matchFound = true;
            matchReason = `They offer "${existingTrade.offeredItemName}" and you want "${newTradeItem.desiredItemName}"`;
            matchType = "they_offer_what_you_want";
          }
        }

        // Check category matches
        if (!matchFound) {
          // They want your category
          if (
            newOfferedCategory &&
            existingDesiredCategory &&
            newOfferedCategory === existingDesiredCategory
          ) {
            matchFound = true;
            matchReason =
              `They want items in "${existingTrade.desiredCategory}" ` +
              `category and you offer "${newTradeItem.offeredItemName}"`;
            matchType = "they_want_what_you_offer";
          }
          // They offer your desired category
          else if (
            newDesiredCategory &&
            existingOfferedCategory &&
            newDesiredCategory === existingOfferedCategory
          ) {
            matchFound = true;
            matchReason =
              `They offer "${existingTrade.offeredItemName}" in ` +
              `"${existingTrade.offeredCategory}" category ` +
              "which you're looking for";
            matchType = "they_offer_what_you_want";
          }
        }

        if (matchFound) {
          // Create notification for the owner of the existing trade item
          const notificationRef = db.collection("notifications").doc();
          notificationsBatch.set(notificationRef, {
            toUserId: existingOfferedBy,
            type: "trade_match",
            tradeItemId: newTradeItemId,
            matchedTradeItemId: existingTradeDoc.id,
            itemTitle: newTradeItem.offeredItemName,
            matchedItemTitle: existingTrade.offeredItemName,
            matchReason: matchReason,
            matchType: matchType,
            status: "unread",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          matches.push({
            userId: existingOfferedBy,
            matchReason: matchReason,
          });

          console.log(
            `Match found for user ${existingOfferedBy}: ${matchReason}`
          );
        }
      }

      // Commit all notifications
      if (matches.length > 0) {
        await notificationsBatch.commit();
        console.log(
          `Created ${matches.length} match notifications for trade item ${newTradeItemId}`
        );

        // Send FCM push notifications
        for (const match of matches) {
          try {
            // Get user's FCM token
            let fcmToken = null;
            const userDoc = await db
              .collection("users")
              .doc(match.userId)
              .get();
            if (userDoc.exists) {
              const userData = userDoc.data();
              fcmToken = userData && userData.fcmToken;
            }

            if (!fcmToken) {
              const tokenDoc = await db
                .collection("fcm_tokens")
                .doc(match.userId)
                .get();
              if (tokenDoc.exists) {
                const tokenData = tokenDoc.data();
                fcmToken = tokenData && tokenData.token;
              }
            }

            if (fcmToken) {
              const message = {
                token: fcmToken,
                notification: {
                  title: "New Trade Match! 🎯",
                  body: match.matchReason,
                },
                data: {
                  type: "trade_match",
                  tradeItemId: newTradeItemId,
                  click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                android: {
                  priority: "high",
                  notification: {
                    channelId: "trade_matches",
                    priority: "high",
                    sound: "default",
                  },
                },
                apns: {
                  payload: {
                    aps: {
                      sound: "default",
                      badge: 1,
                    },
                  },
                },
              };

              await admin.messaging().send(message);
              console.log(`Sent FCM notification to user ${match.userId}`);
            }
          } catch (error) {
            console.error(`Error sending FCM to user ${match.userId}:`, error);
            // Continue with other matches
          }
        }
      } else {
        console.log(`No matches found for trade item ${newTradeItemId}`);
      }

      return null;
    } catch (error) {
      console.error(
        `Error checking trade matches for ${newTradeItemId}:`,
        error
      );
      // Don't throw - we don't want to fail trade item creation if match check fails
      return null;
    }
  });

/**
 * Scheduled function that runs daily at 9 AM to check for overdue rentals
 * and automatically create overdue reminders for both renters and owners
 */
exports.checkAndScheduleOverdueRentals = functions.pubsub
  .schedule("0 9 * * *") // Every day at 9 AM UTC
  .timeZone("UTC")
  .onRun(async (context) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const nowDate = now.toDate();

    console.log(
      `[checkAndScheduleOverdueRentals] Checking for overdue rentals at ${nowDate.toISOString()}`
    );

    try {
      // Query all active rental requests
      const activeRentals = await db
        .collection("rental_requests")
        .where("status", "==", "active")
        .get();

      console.log(
        `[checkAndScheduleOverdueRentals] Found ${activeRentals.size} active rentals`
      );

      let scheduledCount = 0;

      for (const rentalDoc of activeRentals.docs) {
        const rental = rentalDoc.data();
        const requestId = rentalDoc.id;
        const endDate = rental.endDate;
        const rentType = rental.rentType || "item"; // Get rentType, default to "item"

        if (!endDate) {
          // Skip long-term rentals without end dates
          console.log(
            `[checkAndScheduleOverdueRentals] Skipping rental ${requestId} (rentType: ${rentType}) - no endDate (long-term rental)`
          );
          continue;
        }

        const endDateObj = endDate.toDate();

        // Check if rental is overdue
        if (endDateObj < nowDate) {
          const itemId = rental.itemId || "";
          const itemTitle = rental.itemTitle || "Rental Item";
          const renterId = rental.renterId;
          const ownerId = rental.ownerId;
          const renterName = rental.renterName || "Renter";
          const ownerName = rental.ownerName || "Owner";

          // Calculate days overdue
          const daysOverdue = Math.floor(
            (nowDate - endDateObj) / (1000 * 60 * 60 * 24)
          );

          console.log(
            `[checkAndScheduleOverdueRentals] Processing overdue rental ${requestId} (rentType: ${rentType}, daysOverdue: ${daysOverdue})`
          );

          // Schedule reminder for RENTER
          if (renterId) {
            const renterReminderId = `rental_${requestId}_overdue_${renterId}`;

            // Check if reminder already exists
            const existingRenterReminder = await db
              .collection("reminders")
              .doc(renterReminderId)
              .get();

            // Also create notification in notifications collection
            const today = new Date(nowDate);
            today.setHours(0, 0, 0, 0);
            const todayStart = admin.firestore.Timestamp.fromDate(today);
            const todayEnd = admin.firestore.Timestamp.fromDate(
              new Date(today.getTime() + 24 * 60 * 60 * 1000)
            );

            const existingRenterNotification = await db
              .collection("notifications")
              .where("toUserId", "==", renterId)
              .where("type", "==", "rental_overdue")
              .where("requestId", "==", requestId)
              .where("createdAt", ">=", todayStart)
              .where("createdAt", "<", todayEnd)
              .limit(1)
              .get();

            if (existingRenterNotification.empty) {
              await db.collection("notifications").add({
                toUserId: renterId,
                type: "rental_overdue",
                itemId: itemId,
                itemTitle: itemTitle,
                requestId: requestId,
                ownerId: ownerId,
                ownerName: ownerName,
                daysOverdue: daysOverdue,
                rentType: rentType,
                status: "unread",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(
                `[checkAndScheduleOverdueRentals] Created notification for renter ${renterId} (rentType: ${rentType})`
              );
            }

            if (!existingRenterReminder.exists) {
              // Schedule for today at 9 AM (or tomorrow if past 9 AM)
              const scheduledTime = new Date(nowDate);
              scheduledTime.setHours(9, 0, 0, 0);
              if (scheduledTime < nowDate) {
                scheduledTime.setDate(scheduledTime.getDate() + 1);
              }

              const renterTitle = "⚠️ Rental Overdue: " + itemTitle;
              let renterBody;
              if (daysOverdue === 0) {
                renterBody = `Your rental of "${itemTitle}" is due today. Please return it to ${ownerName}.`;
              } else if (daysOverdue === 1) {
                renterBody = `Your rental of "${itemTitle}" is 1 day overdue. Please return it to ${ownerName}.`;
              } else {
                renterBody = `Your rental of "${itemTitle}" is ${daysOverdue} days overdue. Please return it to ${ownerName}.`;
              }

              await db
                .collection("reminders")
                .doc(renterReminderId)
                .set({
                  userId: renterId,
                  itemId: itemId,
                  itemTitle: itemTitle,
                  scheduledTime:
                    admin.firestore.Timestamp.fromDate(scheduledTime),
                  title: renterTitle,
                  body: renterBody,
                  reminderType: "rental_overdue",
                  rentalRequestId: requestId,
                  ownerName: ownerName,
                  renterName: renterName,
                  rentType: rentType,
                  isBorrower: true,
                  sent: false,
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });

              console.log(
                `[checkAndScheduleOverdueRentals] Scheduled overdue reminder for renter ${renterId} (rentType: ${rentType})`
              );
              scheduledCount++;
            }
          }

          // Schedule reminder for OWNER
          if (ownerId) {
            const ownerReminderId = `rental_${requestId}_overdue_${ownerId}`;

            // Check if reminder already exists
            const existingOwnerReminder = await db
              .collection("reminders")
              .doc(ownerReminderId)
              .get();

            // Also create notification in notifications collection
            const today = new Date(nowDate);
            today.setHours(0, 0, 0, 0);
            const todayStart = admin.firestore.Timestamp.fromDate(today);
            const todayEnd = admin.firestore.Timestamp.fromDate(
              new Date(today.getTime() + 24 * 60 * 60 * 1000)
            );

            const existingOwnerNotification = await db
              .collection("notifications")
              .where("toUserId", "==", ownerId)
              .where("type", "==", "rental_overdue_owner")
              .where("requestId", "==", requestId)
              .where("createdAt", ">=", todayStart)
              .where("createdAt", "<", todayEnd)
              .limit(1)
              .get();

            if (existingOwnerNotification.empty) {
              await db.collection("notifications").add({
                toUserId: ownerId,
                type: "rental_overdue_owner",
                itemId: itemId,
                itemTitle: itemTitle,
                requestId: requestId,
                renterId: renterId,
                renterName: renterName,
                daysOverdue: daysOverdue,
                rentType: rentType,
                status: "unread",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(
                `[checkAndScheduleOverdueRentals] Created notification for owner ${ownerId} (rentType: ${rentType})`
              );
            }

            if (!existingOwnerReminder.exists) {
              // Schedule for today at 9 AM (or tomorrow if past 9 AM)
              const scheduledTime = new Date(nowDate);
              scheduledTime.setHours(9, 0, 0, 0);
              if (scheduledTime < nowDate) {
                scheduledTime.setDate(scheduledTime.getDate() + 1);
              }

              const ownerTitle = "⚠️ Rental Overdue: " + itemTitle;
              let ownerBody;
              if (daysOverdue === 0) {
                ownerBody = `The rental of "${itemTitle}" by ${renterName} is due today.`;
              } else if (daysOverdue === 1) {
                ownerBody = `The rental of "${itemTitle}" by ${renterName} is 1 day overdue.`;
              } else {
                ownerBody = `The rental of "${itemTitle}" by ${renterName} is ${daysOverdue} days overdue.`;
              }

              await db
                .collection("reminders")
                .doc(ownerReminderId)
                .set({
                  userId: ownerId,
                  itemId: itemId,
                  itemTitle: itemTitle,
                  scheduledTime:
                    admin.firestore.Timestamp.fromDate(scheduledTime),
                  title: ownerTitle,
                  body: ownerBody,
                  reminderType: "rental_overdue",
                  rentalRequestId: requestId,
                  ownerName: ownerName,
                  renterName: renterName,
                  rentType: rentType,
                  isBorrower: false,
                  sent: false,
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });

              console.log(
                `[checkAndScheduleOverdueRentals] Scheduled overdue reminder for owner ${ownerId} (rentType: ${rentType})`
              );
              scheduledCount++;
            }
          }
        }
      }

      console.log(
        `[checkAndScheduleOverdueRentals] Completed. Scheduled ${scheduledCount} overdue reminders`
      );
      return null;
    } catch (error) {
      console.error("[checkAndScheduleOverdueRentals] Error:", error);
      throw error;
    }
  });

/**
 * Scheduled function that runs daily at 9 AM to check for overdue monthly payments
 * in long-term rentals and automatically create notifications
 */
exports.checkAndNotifyOverdueMonthlyPayments = functions.pubsub
  .schedule("0 9 * * *") // Every day at 9 AM UTC
  .timeZone("UTC")
  .onRun(async (context) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const nowDate = now.toDate();

    console.log(
      `[checkAndNotifyOverdueMonthlyPayments] Checking for overdue monthly payments at ${nowDate.toISOString()}`
    );

    try {
      // Query all active long-term rental requests
      const activeRentals = await db
        .collection("rental_requests")
        .where("status", "==", "active")
        .get();

      console.log(
        `[checkAndNotifyOverdueMonthlyPayments] Found ${activeRentals.size} active rentals`
      );

      let notificationCount = 0;

      for (const rentalDoc of activeRentals.docs) {
        const rental = rentalDoc.data();
        const requestId = rentalDoc.id;
        const isLongTerm = rental.isLongTerm || false;
        const nextPaymentDue = rental.nextPaymentDueDate;

        if (!isLongTerm || !nextPaymentDue) {
          continue; // Skip non-long-term rentals or those without payment due dates
        }

        const dueDateObj = nextPaymentDue.toDate();

        // Check if payment is overdue or due soon
        if (dueDateObj < nowDate) {
          // Payment is overdue
          const itemId = rental.itemId || "";
          const itemTitle = rental.itemTitle || "Rental Item";
          const renterId = rental.renterId;
          const ownerId = rental.ownerId;
          const renterName = rental.renterName || "Renter";
          const ownerName = rental.ownerName || "Owner";
          const monthlyAmount = rental.monthlyPaymentAmount || 0;

          const daysOverdue = Math.floor(
            (nowDate - dueDateObj) / (1000 * 60 * 60 * 24)
          );

          // Create notification for RENTER
          if (renterId) {
            const today = new Date(nowDate);
            today.setHours(0, 0, 0, 0);
            const todayStart = admin.firestore.Timestamp.fromDate(today);
            const todayEnd = admin.firestore.Timestamp.fromDate(
              new Date(today.getTime() + 24 * 60 * 60 * 1000)
            );

            const existingRenterNotification = await db
              .collection("notifications")
              .where("toUserId", "==", renterId)
              .where("type", "==", "rental_monthly_payment_overdue")
              .where("requestId", "==", requestId)
              .where("createdAt", ">=", todayStart)
              .where("createdAt", "<", todayEnd)
              .limit(1)
              .get();

            if (existingRenterNotification.empty) {
              await db.collection("notifications").add({
                toUserId: renterId,
                type: "rental_monthly_payment_overdue",
                itemId: itemId,
                itemTitle: itemTitle,
                requestId: requestId,
                ownerId: ownerId,
                ownerName: ownerName,
                monthlyAmount: monthlyAmount,
                daysOverdue: daysOverdue,
                message: `Your monthly payment of ₱${monthlyAmount.toFixed(
                  2
                )} for "${itemTitle}" is ${
                  daysOverdue === 0
                    ? "due today"
                    : daysOverdue === 1
                    ? "1 day overdue"
                    : `${daysOverdue} days overdue`
                }.`,
                status: "unread",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(
                `[checkAndNotifyOverdueMonthlyPayments] Created overdue notification for renter ${renterId}`
              );
              notificationCount++;
            }
          }

          // Create notification for OWNER
          if (ownerId) {
            const today = new Date(nowDate);
            today.setHours(0, 0, 0, 0);
            const todayStart = admin.firestore.Timestamp.fromDate(today);
            const todayEnd = admin.firestore.Timestamp.fromDate(
              new Date(today.getTime() + 24 * 60 * 60 * 1000)
            );

            const existingOwnerNotification = await db
              .collection("notifications")
              .where("toUserId", "==", ownerId)
              .where("type", "==", "rental_monthly_payment_overdue")
              .where("requestId", "==", requestId)
              .where("createdAt", ">=", todayStart)
              .where("createdAt", "<", todayEnd)
              .limit(1)
              .get();

            if (existingOwnerNotification.empty) {
              await db.collection("notifications").add({
                toUserId: ownerId,
                type: "rental_monthly_payment_overdue",
                itemId: itemId,
                itemTitle: itemTitle,
                requestId: requestId,
                renterId: renterId,
                renterName: renterName,
                monthlyAmount: monthlyAmount,
                daysOverdue: daysOverdue,
                message: `Monthly payment of ₱${monthlyAmount.toFixed(
                  2
                )} for "${itemTitle}" by ${renterName} is ${
                  daysOverdue === 0
                    ? "due today"
                    : daysOverdue === 1
                    ? "1 day overdue"
                    : `${daysOverdue} days overdue`
                }.`,
                status: "unread",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(
                `[checkAndNotifyOverdueMonthlyPayments] Created overdue notification for owner ${ownerId}`
              );
              notificationCount++;
            }
          }
        } else {
          // Payment is due soon (within 3 days)
          const daysUntilDue = Math.floor(
            (dueDateObj - nowDate) / (1000 * 60 * 60 * 24)
          );
          if (daysUntilDue <= 3 && daysUntilDue >= 0) {
            const itemId = rental.itemId || "";
            const itemTitle = rental.itemTitle || "Rental Item";
            const renterId = rental.renterId;
            const monthlyAmount = rental.monthlyPaymentAmount || 0;

            if (renterId) {
              const today = new Date(nowDate);
              today.setHours(0, 0, 0, 0);
              const todayStart = admin.firestore.Timestamp.fromDate(today);
              const todayEnd = admin.firestore.Timestamp.fromDate(
                new Date(today.getTime() + 24 * 60 * 60 * 1000)
              );

              const existingNotification = await db
                .collection("notifications")
                .where("toUserId", "==", renterId)
                .where("type", "==", "rental_monthly_payment_due")
                .where("requestId", "==", requestId)
                .where("createdAt", ">=", todayStart)
                .where("createdAt", "<", todayEnd)
                .limit(1)
                .get();

              if (existingNotification.empty) {
                let message;
                if (daysUntilDue === 0) {
                  message = `Your monthly payment of ₱${monthlyAmount.toFixed(
                    2
                  )} for "${itemTitle}" is due today.`;
                } else if (daysUntilDue === 1) {
                  message = `Your monthly payment of ₱${monthlyAmount.toFixed(
                    2
                  )} for "${itemTitle}" is due tomorrow.`;
                } else {
                  message = `Your monthly payment of ₱${monthlyAmount.toFixed(
                    2
                  )} for "${itemTitle}" is due in ${daysUntilDue} days.`;
                }

                await db.collection("notifications").add({
                  toUserId: renterId,
                  type: "rental_monthly_payment_due",
                  itemId: itemId,
                  itemTitle: itemTitle,
                  requestId: requestId,
                  monthlyAmount: monthlyAmount,
                  message: message,
                  status: "unread",
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.log(
                  `[checkAndNotifyOverdueMonthlyPayments] Created due notification for renter ${renterId}`
                );
                notificationCount++;
              }
            }
          }
        }
      }

      console.log(
        `[checkAndNotifyOverdueMonthlyPayments] Completed. Created ${notificationCount} notifications`
      );
      return null;
    } catch (error) {
      console.error("[checkAndNotifyOverdueMonthlyPayments] Error:", error);
      throw error;
    }
  });

/**
 * Cloud Function that triggers when a new user document is created
 * Sends FCM push notification to all admin users about the new registration
 */
exports.onNewUserCreated = functions.firestore
  .document("users/{userId}")
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const userData = snap.data();
    const userId = context.params.userId;

    console.log(`[onNewUserCreated] New user registered: ${userId}`);

    // Only notify if user is not verified (pending verification)
    const isVerified = userData.isVerified || false;
    if (isVerified) {
      console.log(
        `[onNewUserCreated] User ${userId} is already verified, skipping notification`
      );
      return null;
    }

    // Get user details for notification
    const firstName = (userData.firstName || "").trim();
    const lastName = (userData.lastName || "").trim();
    const email = (userData.email || "").trim();

    // Build display name with better fallback logic
    let displayName = "";
    if (firstName && lastName) {
      displayName = `${firstName} ${lastName}`;
    } else if (firstName) {
      displayName = firstName;
    } else if (lastName) {
      displayName = lastName;
    } else if (email && email !== "Unknown") {
      // Use email username part if available
      const emailUsername = email.split("@")[0];
      displayName = emailUsername || "A new user";
    } else {
      displayName = "A new user";
    }

    console.log(
      `[onNewUserCreated] New user pending verification: ${displayName} (${email})`
    );

    // Find all admin users
    let adminUsers = [];
    try {
      const adminSnapshot = await db
        .collection("users")
        .where("isAdmin", "==", true)
        .get();
      adminUsers = adminSnapshot.docs;
      console.log(`[onNewUserCreated] Found ${adminUsers.length} admin users`);
    } catch (error) {
      console.error(`[onNewUserCreated] Error fetching admin users:`, error);
      return null;
    }

    if (adminUsers.length === 0) {
      console.log(
        "[onNewUserCreated] No admin users found, skipping notification"
      );
      return null;
    }

    // Send FCM notification to each admin
    const notificationPromises = adminUsers.map(async (adminDoc) => {
      const adminId = adminDoc.id;
      const adminData = adminDoc.data();

      // Get admin's FCM token
      let fcmToken = adminData.fcmToken;
      if (!fcmToken) {
        // Try fcm_tokens collection as fallback
        try {
          const tokenDoc = await db.collection("fcm_tokens").doc(adminId).get();
          if (tokenDoc.exists) {
            const tokenData = tokenDoc.data();
            fcmToken = tokenData && tokenData.token;
          }
        } catch (error) {
          console.error(
            `[onNewUserCreated] Error fetching FCM token for admin ${adminId}:`,
            error
          );
        }
      }

      if (!fcmToken) {
        console.warn(
          `[onNewUserCreated] No FCM token found for admin ${adminId}, skipping`
        );
        return null;
      }

      // Create notification in Firestore for admin
      try {
        await db.collection("notifications").add({
          toUserId: adminId,
          type: "new_user_registration",
          title: "New User Registration",
          message: `${displayName} has registered and is pending verification`,
          userId: userId,
          userName: displayName,
          userEmail: email,
          status: "unread",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.error(
          `[onNewUserCreated] Error creating notification for admin ${adminId}:`,
          error
        );
      }

      // Prepare FCM message
      const message = {
        token: fcmToken,
        notification: {
          title: "New User Registration",
          body: `${displayName} needs verification`,
        },
        data: {
          type: "new_user_registration",
          userId: userId,
          userName: displayName,
          userEmail: email,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "admin_notifications",
            priority: "high",
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      // Send FCM notification
      try {
        await admin.messaging().send(message);
        console.log(
          `[onNewUserCreated] Successfully sent FCM notification to admin ${adminId}`
        );
        return null;
      } catch (error) {
        console.error(
          `[onNewUserCreated] Error sending FCM notification to admin ${adminId}:`,
          error
        );
        return null;
      }
    });

    // Wait for all notifications to be sent
    await Promise.all(notificationPromises);
    console.log(
      `[onNewUserCreated] Completed sending notifications for new user ${userId}`
    );
    return null;
  });

// Note: Activity log entries for new user registrations are created
// directly from the client app (register screen) using FirestoreService.
// This avoids duplication and ensures metadata is populated from the
// final profile data the user submitted.

/**
 * Cloud Function that triggers when a user document is deleted from Firestore
 * Automatically deletes the corresponding Firebase Auth user to ensure complete cleanup
 */
exports.onUserDeleted = functions.firestore
  .document("users/{userId}")
  .onDelete(async (snap, context) => {
    const userId = context.params.userId;
    const userData = snap.data();

    console.log(`[onUserDeleted] User document deleted: ${userId}`);

    // Get user info for logging
    const userName = userData
      ? `${userData.firstName || ""} ${userData.lastName || ""}`.trim() ||
        userData.email ||
        "Unknown User"
      : "Unknown User";
    const userEmail = userData?.email || "N/A";

    console.log(
      `[onUserDeleted] Attempting to delete Firebase Auth user for: ${userName} (${userEmail})`
    );

    // Delete Firebase Auth user
    try {
      await admin.auth().deleteUser(userId);
      console.log(
        `[onUserDeleted] Successfully deleted Firebase Auth user: ${userId}`
      );
    } catch (error) {
      // Handle different error cases
      if (error.code === "auth/user-not-found") {
        // Auth user doesn't exist (maybe already deleted or never created)
        console.log(
          `[onUserDeleted] Firebase Auth user ${userId} not found - may have been already deleted or never existed`
        );
      } else {
        // Other errors (permissions, network, etc.)
        console.error(
          `[onUserDeleted] Error deleting Firebase Auth user ${userId}:`,
          error
        );
        // Don't throw - we don't want to fail the Firestore deletion if Auth deletion fails
        // The user document is already deleted, so this is best-effort cleanup
      }
    }

    // Log the deletion for audit purposes
    try {
      await admin
        .firestore()
        .collection("activity_logs")
        .add({
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          category: "system",
          action: "auth_user_deleted",
          actorId: "system",
          actorName: "System",
          targetId: userId,
          targetType: "user",
          description: `Firebase Auth user automatically deleted after Firestore user deletion: ${userName}`,
          metadata: {
            userId: userId,
            userName: userName,
            userEmail: userEmail,
            deletedAt: new Date().toISOString(),
          },
          severity: "info",
        });
      console.log(
        `[onUserDeleted] Created activity log for Auth user deletion`
      );
    } catch (logError) {
      // Don't fail if logging fails
      console.error(`[onUserDeleted] Error creating activity log:`, logError);
    }

    return null;
  });
