const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

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
              reminderType: reminder.reminderType || "",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
            android: {
              priority: "high",
              notification: {
                channelId: reminder.reminderType === "overdue" ? "overdue_reminders" : "due_reminders",
                priority: reminder.reminderType === "overdue" ? "max" : "high",
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
            if (reminder.reminderType === "overdue") {
              const nextScheduledTime = new Date();
              nextScheduledTime.setDate(nextScheduledTime.getDate() + 1);
              nextScheduledTime.setHours(9, 0, 0, 0);

              // Use the same reminder ID format: itemId_overdue_userId
              // This ensures each user gets their own recurring reminder
              const nextReminderId = `${reminder.itemId}_overdue_${reminder.userId}`;
              batch.set(db.collection("reminders").doc(nextReminderId), {
                userId: reminder.userId,
                itemId: reminder.itemId,
                itemTitle: reminder.itemTitle,
                scheduledTime: admin.firestore.Timestamp.fromDate(nextScheduledTime),
                title: reminder.title,
                body: reminder.body,
                reminderType: "overdue",
                borrowerName: reminder.borrowerName,
                lenderName: reminder.lenderName,
                isBorrower: reminder.isBorrower,
                sent: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
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
            console.log(`FCM token found in fcm_tokens collection for lender ${lenderId}: ${fcmToken ? 'exists' : 'missing'}`);
            if (tokenUpdatedAt) {
              console.log(`Token last updated at: ${tokenUpdatedAt.toDate()}`);
            }
          } else {
            console.log(`FCM token document not found in fcm_tokens collection for lender ${lenderId}`);
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
              console.error(`WARNING: Lender's FCM token matches borrower's token! This means the notification will go to the borrower. LenderId: ${lenderId}, BorrowerId: ${borrowerId}`);
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
        console.warn(`No FCM token found for lender ${lenderId}, cannot send notification`);
        return null;
      }
      
      console.log(`Sending FCM notification to lender ${lenderId} (NOT borrower ${borrowerId})`);

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
        console.log(`Trade item ${newTradeItemId} is not open, skipping match check`);
        return null;
      }

      const newOfferedBy = newTradeItem.offeredBy;
      const newOfferedName = (newTradeItem.offeredItemName || "").toLowerCase().trim();
      const newOfferedCategory = (newTradeItem.offeredCategory || "").toLowerCase().trim();
      const newDesiredName = (newTradeItem.desiredItemName || "").toLowerCase().trim();
      const newDesiredCategory = (newTradeItem.desiredCategory || "").toLowerCase().trim();

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

          const existingOfferedName = (existingTrade.offeredItemName || "").toLowerCase().trim();
          const existingOfferedCategory = (existingTrade.offeredCategory || "").toLowerCase().trim();
          const existingDesiredName = (existingTrade.desiredItemName || "").toLowerCase().trim();
          const existingDesiredCategory = (existingTrade.desiredCategory || "").toLowerCase().trim();

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
              matchReason = `They want items in "${existingTrade.desiredCategory}" category and you offer "${newTradeItem.offeredItemName}"`;
              matchType = "they_want_what_you_offer";
            }
            // They offer your desired category
            else if (newDesiredCategory && existingOfferedCategory && 
                     newDesiredCategory === existingOfferedCategory) {
              matchFound = true;
              matchReason = `They offer "${existingTrade.offeredItemName}" in "${existingTrade.offeredCategory}" category which you're looking for`;
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

