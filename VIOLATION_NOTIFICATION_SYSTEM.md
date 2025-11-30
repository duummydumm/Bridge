# Violation & Report Notification System

## ✅ Implemented Features

### 1. **Automatic Notifications When Violations Are Filed**

When an admin files a violation against a user, the system now:

**Location:** `lib/services/admin_service.dart` - `fileViolation()` method

**What Happens:**

1. ✅ Violation count is incremented
2. ✅ **Notification is automatically sent to the user**
3. ✅ Activity log is created
4. ✅ Warning level is assigned based on violation count

**Notification Details:**

- **Type:** `violation_issued`
- **Title:** Varies based on violation count
- **Message:** Includes warning level and admin note (if provided)
- **Warning Levels:**
  - `warning` - For 1-2 violations
  - `critical` - For 3+ violations

**Warning Messages by Violation Count:**

| Count | Title                                 | Message                                                                                             |
| ----- | ------------------------------------- | --------------------------------------------------------------------------------------------------- |
| 1     | First Violation - Warning             | ⚠️ You have received your first violation. Please review our community guidelines...                |
| 2     | Second Violation - Serious Warning    | ⚠️⚠️ You have received a second violation. Continued violations may result in account suspension... |
| 3     | Third Violation - Final Warning       | 🚨 You have received a third violation. Your account is at high risk of suspension...               |
| 4+    | Multiple Violations - Account at Risk | 🚨🚨 You have received X violations. Your account is at severe risk of permanent suspension...      |

**Auto-Suspension:**

- If violation count reaches **5 or more**, the account is **automatically suspended**
- An additional suspension notification is sent to the user

---

### 2. **Notifications When Reports Are Resolved**

When an admin resolves a report, the system now:

**Location:** `lib/services/admin_service.dart` - `resolveReport()` method

**What Happens:**

1. ✅ Report status is updated to 'resolved'
2. ✅ **Notification sent to the REPORTER**
3. ✅ **Notification sent to the REPORTED USER** (if it's a user report)
4. ✅ Activity log is created

**Notification to Reporter:**

- **Type:** `report_resolved`
- **Title:** "Report Resolved"
- **Message:** "Your report against [User Name] has been reviewed and resolved by an administrator."

**Notification to Reported User:**

- **Type:** `report_resolved`
- **Title:** "Report Review Completed"
- **Message:** Varies based on resolution:
  - If resolved/dismissed: "A report filed against you has been reviewed. The report has been [resolved/dismissed]. Please continue to follow our community guidelines."
  - Other resolutions: "A report filed against you has been reviewed and marked as: [resolution]."

---

### 3. **Warning System Based on Violation Counts**

The system implements a progressive warning system:

**Warning Levels:**

1. **First Violation (Count = 1)**

   - Level: `warning`
   - Message: Reminds user to review guidelines
   - Tone: Informational

2. **Second Violation (Count = 2)**

   - Level: `warning`
   - Message: Warns about potential suspension
   - Tone: Serious

3. **Third Violation (Count = 3)**

   - Level: `critical`
   - Message: Final warning before suspension
   - Tone: Urgent

4. **Fourth+ Violation (Count = 4+)**

   - Level: `critical`
   - Message: Severe risk of permanent suspension
   - Tone: Critical

5. **Fifth Violation (Count = 5)**
   - **Automatic Account Suspension**
   - Additional suspension notification sent
   - User must contact support

---

## 📋 Notification Structure

All notifications are stored in the `notifications` collection with:

```dart
{
  'toUserId': String,           // User receiving the notification
  'type': String,               // 'violation_issued' or 'report_resolved'
  'title': String,              // Notification title
  'message': String,            // Notification message
  'violationCount': int?,       // For violations only
  'violationNote': String?,     // Admin's note
  'warningLevel': String?,      // 'warning' or 'critical'
  'reportId': String?,          // For report resolutions
  'status': 'unread',           // Notification status
  'createdAt': Timestamp,       // When notification was created
}
```

---

## 🔄 Complete Workflow

### Violation Workflow:

1. Admin files violation → User receives notification immediately
2. User sees warning message based on violation count
3. If count reaches 5 → Auto-suspension + suspension notification

### Report Resolution Workflow:

1. Admin resolves report → Both parties receive notifications
2. Reporter knows their report was reviewed
3. Reported user knows the outcome (if applicable)

---

## 🎯 Benefits

1. **Transparency:** Users are immediately notified when violations occur
2. **Accountability:** Users know when reports against them are resolved
3. **Progressive Warnings:** Users receive escalating warnings before suspension
4. **Automatic Enforcement:** System auto-suspends at 5 violations
5. **Activity Logging:** All actions are logged for admin review

---

## 📝 Admin Actions That Send Notifications

| Action              | Notification Sent? | To Whom                  |
| ------------------- | ------------------ | ------------------------ |
| File Violation      | ✅ Yes             | Reported User            |
| Resolve Report      | ✅ Yes             | Reporter + Reported User |
| Suspend User        | ✅ Yes             | Suspended User           |
| Reject Verification | ✅ Yes             | Rejected User            |
| Approve User        | ❌ No              | (No notification needed) |
| Restore User        | ❌ No              | (No notification needed) |

---

## 🔧 Technical Details

**Files Modified:**

- `lib/services/admin_service.dart`
  - `fileViolation()` - Added notification and warning system
  - `resolveReport()` - Added notifications to both parties

**Dependencies:**

- Uses existing `notifications` collection
- Uses existing `activity_logs` collection
- Integrates with `suspendUser()` for auto-suspension

**Error Handling:**

- Notification failures don't prevent violation filing or report resolution
- Errors are logged but don't break the workflow
- Best-effort approach ensures core functionality always works

---

## ✅ Testing Checklist

- [ ] File violation → User receives notification
- [ ] First violation → Warning message received
- [ ] Second violation → Serious warning received
- [ ] Third violation → Final warning received
- [ ] Fourth violation → Critical warning received
- [ ] Fifth violation → Auto-suspension + suspension notification
- [ ] Resolve report → Reporter receives notification
- [ ] Resolve user report → Reported user receives notification
- [ ] Check notification appears in user's notification screen
- [ ] Verify activity logs are created

---

## 🚀 Next Steps (Optional Enhancements)

1. **Email Notifications:** Send email when critical violations occur
2. **Push Notifications:** Use FCM for real-time push notifications
3. **Violation Appeal System:** Allow users to appeal violations
4. **Custom Warning Thresholds:** Make violation thresholds configurable
5. **Violation History Page:** Show users their violation history
