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
  if (!EMAILJS_SERVICE_ID || !EMAILJS_TEMPLATE_ID ||
      !EMAILJS_PUBLIC_KEY || !EMAILJS_PRIVATE_KEY) {
    throw new Error(
        "EmailJS config missing. " +
        "Set it with: firebase functions:config:set " +
        "emailjs.service_id=\"...\" emailjs.template_id=\"...\" " +
        "emailjs.public_key=\"...\" emailjs.private_key=\"...\"",
    );
  }

  if (requireWelcomeTemplate && !EMAILJS_WELCOME_TEMPLATE_ID) {
    throw new Error(
        "EmailJS welcome_template_id missing. " +
        "Set it with: firebase functions:config:set " +
        "emailjs.welcome_template_id=\"...\"",
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
        `via template ${emailData.template_id}`,
    );

    const response = await fetch(EMAILJS_API_URL, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
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
        text,
    );

    // Special handling for 403 "non-browser" style errors
    if (response.status === 403 &&
        (text.includes("non-browser") || text.includes("API calls are disabled"))) {
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
        `via template ${emailData.template_id}`,
    );

    const response = await fetch(EMAILJS_API_URL, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
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

    console.error(
        "sendWelcomeEmail: EmailJS error",
        response.status,
        text,
    );

    if (response.status === 403 &&
        (text.includes("non-browser") || text.includes("API calls are disabled"))) {
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
      // scheduledTime <= now AND sent == false
        const dueReminders = await db
            .collection("reminders")
            .where("sent", "==", false)
            .where("scheduledTime", "<=", now)
            .limit(100) // Process up to 100 reminders per run
            .get();

        console.log(`Found ${dueReminders.size} due reminders`);

        const batch = db.batch();

        for (const reminderDoc of dueReminders.docs) {
          const reminder = reminderDoc.data();
          const reminderId = reminderDoc.id;

          console.log(`Processing reminder: ${reminderId} for user: ${reminder.userId}`);

          // Get user's FCM token
          let fcmToken = null;
          try {
          // Try to get token from user document first
            const userDoc = await db.collection("users").doc(reminder.userId).get();
            if (userDoc.exists) {
              const userData = userDoc.data();
              fcmToken = userData && userData.fcmToken;
            }

            // If not found, try fcm_tokens collection
            if (!fcmToken) {
              const tokenDoc = await db.collection("fcm_tokens").doc(reminder.userId).get();
              if (tokenDoc.exists) {
                const tokenData = tokenDoc.data();
                fcmToken = tokenData && tokenData.token;
              }
            }
          } catch (error) {
            console.error(`Error fetching FCM token for user ${reminder.userId}:`, error);
          }

          if (!fcmToken) {
            console.warn(`No FCM token found for user ${reminder.userId}, skipping reminder ${reminderId}`);
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
            channelId = reminderType === "rental_overdue" ? "rental_overdue_reminders" : "overdue_reminders";
            priority = "max";
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

          // Send FCM notification
          try {
            await admin.messaging().send(message);
            console.log(`Successfully sent reminder ${reminderId} to user ${reminder.userId}`);

            // Mark reminder as sent
            batch.update(reminderDoc.ref, {
              sent: true,
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // If this is an overdue reminder, schedule the next one for tomorrow at 9 AM
            if (reminder.reminderType === "overdue" || reminder.reminderType === "rental_overdue") {
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
                if (originalId.startsWith("rental_") && originalId.includes("_overdue_")) {
                  nextReminderId = originalId; // Use same ID format for recurring rental overdue
                } else {
                  // Fallback: construct from available data
                  const rentalRequestId = reminder.rentalRequestId || reminder.itemId;
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
                scheduledTime: admin.firestore.Timestamp.fromDate(nextScheduledTime),
                title: reminder.title,
                body: reminder.body,
                reminderType: reminderType,
                isBorrower: reminder.isBorrower,
                sent: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              };

              // Add optional fields if they exist
              if (reminder.borrowerName) nextReminderData.borrowerName = reminder.borrowerName;
              if (reminder.lenderName) nextReminderData.lenderName = reminder.lenderName;
              if (reminder.rentalRequestId) nextReminderData.rentalRequestId = reminder.rentalRequestId;

              batch.set(db.collection("reminders").doc(nextReminderId), nextReminderData);
            }
          } catch (error) {
            console.error(`Error sending FCM message for reminder ${reminderId}:`, error);
            // Mark as sent with error to avoid retrying indefinitely
            batch.update(reminderDoc.ref, {
              sent: true,
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
              error: error.message,
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
        console.log(`Borrow request ${requestId} is not pending, skipping notification`);
        return null;
      }

      const lenderId = requestData.lenderId;
      const borrowerName = requestData.borrowerName || "Someone";
      const itemTitle = requestData.itemTitle || "an item";

      console.log(`New borrow request ${requestId} from ${borrowerName} for item: ${itemTitle}`);

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
          console.log(`FCM token found in user document for lender ${lenderId}: ${fcmToken ? 'exists' : 'missing'}`);
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
            `${lenderId}: ${fcmToken ? "exists" : "missing"}`,
        );
            if (tokenUpdatedAt) {
              console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
            }
          } else {
          console.log(
              "FCM token document not found in fcm_tokens collection " +
              `for lender ${lenderId}`,
          );
          }
        }
        
        // Safety check: Verify we're not accidentally using borrower's token
        if (fcmToken && borrowerId) {
          // Check if borrower's token matches (this would indicate a problem)
          const borrowerDoc = await db.collection("users")
              .doc(borrowerId).get();
          if (borrowerDoc.exists) {
            const borrowerData = borrowerDoc.data();
            const borrowerToken = borrowerData && borrowerData.fcmToken;
            if (borrowerToken === fcmToken) {
              console.error(
                  "WARNING: Lender's FCM token matches borrower's token! " +
                  "This means the notification will go to the borrower. " +
                  `LenderId: ${lenderId}, BorrowerId: ${borrowerId}`,
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
            "cannot send notification",
        );
        return null;
      }
      
      console.log(
          `Sending FCM notification to lender ${lenderId} ` +
          `(NOT borrower ${borrowerId})`,
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
        console.log(`Successfully sent borrow request notification to lender ${lenderId}`);
        return null;
      } catch (error) {
        console.error(`Error sending FCM notification for borrow request ${requestId}:`, error);
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
          `[onRentalRequestCreated] Triggered for rental request ${requestId}`,
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
            `pending/requested (status: "${status}"), skipping notification`,
        );
        return null;
      }

      const ownerId = requestData.ownerId;
      const renterId = requestData.renterId;

      if (!ownerId) {
        console.error(
            `[onRentalRequestCreated] ERROR: No ownerId found in rental ` +
            `request ${requestId}`,
        );
        return null;
      }

      if (!renterId) {
        console.error(
            `[onRentalRequestCreated] ERROR: No renterId found in rental ` +
            `request ${requestId}`,
        );
        return null;
      }

      console.log(
          `[onRentalRequestCreated] Processing request - Owner: ${ownerId}, ` +
          `Renter: ${renterId}`,
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
          `${requestData.rentType || "unknown"})`,
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
              `${fcmToken ? "exists" : "missing"}`,
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
                `${ownerId}: ${fcmToken ? "exists" : "missing"}`,
            );
            if (tokenUpdatedAt) {
              console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
            }
          } else {
            console.log(
                "FCM token document not found in fcm_tokens collection " +
                `for owner ${ownerId}`,
            );
          }
        }

        // Safety check: Verify we're not accidentally using renter's token
        if (fcmToken && renterId) {
          // Check if renter's token matches (this would indicate a problem)
          const renterDoc = await db.collection("users")
              .doc(renterId).get();
          if (renterDoc.exists) {
            const renterData = renterDoc.data();
            const renterToken = renterData && renterData.fcmToken;
            if (renterToken === fcmToken) {
              console.error(
                  "WARNING: Owner's FCM token matches renter's token! " +
                  "This means the notification will go to the renter. " +
                  `OwnerId: ${ownerId}, RenterId: ${renterId}`,
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
            `${ownerId}, cannot send notification`,
        );
        return null;
      }

      console.log(
          "[onRentalRequestCreated] Sending FCM notification to owner " +
          `${ownerId} (NOT renter ${renterId})`,
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
            `notification to owner ${ownerId} for request ${requestId}`,
        );
        return null;
      } catch (error) {
        console.error(
            "[onRentalRequestCreated] Error sending FCM notification for " +
            `rental request ${requestId}:`,
            error,
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

      if (!notif) {
        console.warn(
            `[onNotificationCreated] Empty notification payload for ` +
            `${notificationId}, skipping`,
        );
        return null;
      }

      const type = notif.type;
      const decision = (notif.decision || "").toLowerCase();
      const toUserId = notif.toUserId;

      // Only handle the specific decision/offer/message/donation/calamity notifications requested
      if (type !== "borrow_request_decision" &&
          type !== "rent_request_decision" &&
          type !== "trade_offer" &&
          type !== "trade_offer_decision" &&
          type !== "chat_message" &&
          type !== "message" &&
          type !== "donation_request" &&
          type !== "donation_request_decision" &&
          type !== "calamity_event_created" &&
          type !== "calamity_donation_received") {
        // Not a notification we care about for FCM
        return null;
      }

      if (!toUserId) {
        console.warn(
            `[onNotificationCreated] No toUserId for notification ` +
            `${notificationId} (type: ${type}), skipping`,
        );
        return null;
      }

      console.log(
          `[onNotificationCreated] Processing decision notification ` +
          `${notificationId} for user ${toUserId} (type: ${type}, ` +
          `decision: ${decision})`,
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
              `${fcmToken ? "exists" : "missing"}`,
          );
          if (tokenUpdatedAt) {
            console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
          }
        } else {
          console.log(
              `[onNotificationCreated] User document not found for ` +
              `user ${toUserId}`,
          );
        }

        // 2) If still not found, try fcm_tokens collection
        if (!fcmToken) {
          const tokenDoc = await db.collection("fcm_tokens")
              .doc(toUserId).get();
          if (tokenDoc.exists) {
            const tokenData = tokenDoc.data();
            fcmToken = tokenData && tokenData.token;
            const tokenUpdatedAt = tokenData && tokenData.updatedAt;
            console.log(
                "FCM token found in fcm_tokens collection for user " +
                `${toUserId}: ${fcmToken ? "exists" : "missing"}`,
            );
            if (tokenUpdatedAt) {
              console.log(
                  "[onNotificationCreated] Token last updated at: " +
                  tokenUpdatedAt.toDate(),
              );
            }
          } else {
            console.log(
                "FCM token document not found in fcm_tokens collection " +
                `for user ${toUserId}`,
            );
          }
        }
      } catch (error) {
        console.error(
            `[onNotificationCreated] Error fetching FCM token for ` +
            `user ${toUserId}:`,
            error,
        );
        return null;
      }

      if (!fcmToken) {
        console.warn(
            "[onNotificationCreated] No FCM token found for user " +
            `${toUserId}, cannot send push notification for ` +
            `notification ${notificationId}`,
        );
        return null;
      }

      const itemTitle = notif.itemTitle || "an item";
      let title = "Notification";
      let body = "You have a new notification.";
      let channelId = "general";
      let dataType = type;

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
        if (decision === "accepted") {
          title = "Claim Request Approved";
          body = `${donorName} approved your claim request for "${itemTitle}".`;
        } else if (decision === "declined") {
          title = "Claim Request Declined";
          body = `${donorName} declined your claim request for "${itemTitle}".`;
        } else {
          title = "Claim Request Updated";
          body = `Your claim request for "${itemTitle}" was updated.`;
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
          priority: "high",
          notification: {
            channelId: channelId,
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

      try {
        await admin.messaging().send(message);
        console.log(
            "[onNotificationCreated] Successfully sent decision FCM " +
            `notification for ${notificationId} to user ${toUserId}`,
        );
      } catch (error) {
        console.error(
            "[onNotificationCreated] Error sending FCM notification for " +
            `notification ${notificationId}:`,
            error,
        );
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
            `Trade item ${newTradeItemId} is not open, ` +
            "skipping match check",
        );
        return null;
      }

      const newOfferedBy = newTradeItem.offeredBy;
      const newOfferedName = (newTradeItem.offeredItemName || "")
          .toLowerCase().trim();
      const newOfferedCategory = (newTradeItem.offeredCategory || "")
          .toLowerCase().trim();
      const newDesiredName = (newTradeItem.desiredItemName || "")
          .toLowerCase().trim();
      const newDesiredCategory = (newTradeItem.desiredCategory || "")
          .toLowerCase().trim();

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
              .toLowerCase().trim();
          const existingOfferedCategory = (existingTrade.offeredCategory || "")
              .toLowerCase().trim();
          const existingDesiredName = (existingTrade.desiredItemName || "")
              .toLowerCase().trim();
          const existingDesiredCategory = (existingTrade.desiredCategory || "")
              .toLowerCase().trim();

          let matchFound = false;
          let matchReason = "";
          let matchType = "";

          // Check: They want what you're offering (new item offers what existing item wants)
          if (newDesiredName && existingDesiredName) {
            if (newOfferedName.includes(existingDesiredName) || 
                existingDesiredName.includes(newOfferedName) ||
                newOfferedName === existingDesiredName) {
              matchFound = true;
              matchReason = `They want "${existingTrade.desiredItemName}" and you offer "${newTradeItem.offeredItemName}"`;
              matchType = "they_want_what_you_offer";
            }
          }

          // Check: They offer what you want (new item wants what existing item offers)
          if (!matchFound && newDesiredName && existingOfferedName) {
            if (existingOfferedName.includes(newDesiredName) || 
                newDesiredName.includes(existingOfferedName) ||
                existingOfferedName === newDesiredName) {
              matchFound = true;
              matchReason = `They offer "${existingTrade.offeredItemName}" and you want "${newTradeItem.desiredItemName}"`;
              matchType = "they_offer_what_you_want";
            }
          }

          // Check category matches
          if (!matchFound) {
            // They want your category
            if (newOfferedCategory && existingDesiredCategory && 
                newOfferedCategory === existingDesiredCategory) {
              matchFound = true;
              matchReason =
                `They want items in "${existingTrade.desiredCategory}" ` +
                `category and you offer "${newTradeItem.offeredItemName}"`;
              matchType = "they_want_what_you_offer";
            }
            // They offer your desired category
            else if (newDesiredCategory && existingOfferedCategory && 
                     newDesiredCategory === existingOfferedCategory) {
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

            console.log(`Match found for user ${existingOfferedBy}: ${matchReason}`);
          }
        }

        // Commit all notifications
        if (matches.length > 0) {
          await notificationsBatch.commit();
          console.log(`Created ${matches.length} match notifications for trade item ${newTradeItemId}`);

          // Send FCM push notifications
          for (const match of matches) {
            try {
              // Get user's FCM token
              let fcmToken = null;
              const userDoc = await db.collection("users").doc(match.userId).get();
              if (userDoc.exists) {
                const userData = userDoc.data();
                fcmToken = userData && userData.fcmToken;
              }

              if (!fcmToken) {
                const tokenDoc = await db.collection("fcm_tokens").doc(match.userId).get();
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
        console.error(`Error checking trade matches for ${newTradeItemId}:`, error);
        // Don't throw - we don't want to fail trade item creation if match check fails
        return null;
      }
    });

