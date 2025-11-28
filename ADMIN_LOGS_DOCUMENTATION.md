# Admin Activity Logs Documentation

## Overview

The Activity Logs system allows admins to monitor all user activities and platform events in real-time. This provides a comprehensive audit trail for security, compliance, and platform management.

## What Information is Captured in Each Log Entry

Each activity log contains the following information:

### Core Fields

- **Timestamp**: Exact date and time when the activity occurred (server timestamp)
- **Category**: Type of activity (user, transaction, content, admin, system)
- **Action**: Specific action performed (e.g., `user_registered`, `item_listed`)
- **Actor ID**: User ID who performed the action
- **Actor Name**: Display name of the user who performed the action
- **Target ID**: (Optional) ID of the item/resource affected
- **Target Type**: (Optional) Type of resource affected (e.g., `item`, `user`, `transaction`)
- **Description**: Human-readable description of what happened
- **Severity**: Level of importance (info, warning, critical)
- **Metadata**: Additional context-specific information (JSON object)

## Log Categories and User Activities

### 1. User Actions (`category: 'user'`)

Admins can track:

#### User Registration & Account Management

- **user_registered**: New user registration
  - Metadata: `email`, `method` (registration method)
  - Severity: `info`
- **user_verified**: User account verification by admin
  - Metadata: `userId`, `userName`, `verificationType`
  - Severity: `info`
- **profile_updated**: User profile information changes
  - Metadata: `fieldsUpdated` (list of changed fields)
  - Severity: `info`

#### Account Status Changes

- **user_banned**: User account suspension/ban
  - Metadata: `userId`, `userName`, `reason`, `duration`
  - Severity: `critical`
- **user_unbanned**: User account restoration
  - Metadata: `userId`, `userName`
  - Severity: `info`

### 2. Transaction Events (`category: 'transaction'`)

Admins can monitor all borrowing, renting, and trading activities:

#### Borrowing Activities

- **borrow_request_created**: User creates a borrow request
  - Metadata: `itemId`, `itemTitle`, `lenderId`, `duration`
  - Severity: `info`
- **borrow_accepted**: Lender accepts a borrow request
  - Metadata: `requestId`, `borrower`, `item`, `returnDate`
  - Severity: `info`
- **borrow_rejected**: Lender rejects a borrow request
  - Metadata: `requestId`, `borrower`, `item`, `reason`
  - Severity: `info`
- **borrow_completed**: Item returned successfully
  - Metadata: `requestId`, `itemId`, `borrower`, `lender`
  - Severity: `info`

#### Rental Activities

- **rental_request_created**: User creates a rental request
  - Metadata: `itemId`, `itemTitle`, `ownerId`, `duration`, `totalPrice`
  - Severity: `info`
- **rental_accepted**: Owner accepts rental request
  - Metadata: `requestId`, `renter`, `item`, `startDate`, `endDate`
  - Severity: `info`
- **rental_payment_received**: Payment processed for rental
  - Metadata: `amount`, `renterId`, `renterName`, `itemTitle`, `paymentId`
  - Severity: `info`
- **rental_completed**: Rental period ended
  - Metadata: `requestId`, `itemId`, `renter`, `owner`
  - Severity: `info`

#### Trading Activities

- **trade_offered**: User offers a trade
  - Metadata: `offeredItem`, `requestedItem`, `targetUser`
  - Severity: `info`
- **trade_accepted**: Trade offer accepted
  - Metadata: `tradeId`, `offeredItem`, `requestedItem`, `parties`
  - Severity: `info`
- **trade_completed**: Trade successfully completed
  - Metadata: `tradeId`, `itemsExchanged`
  - Severity: `info`

### 3. Content Actions (`category: 'content'`)

Admins can track all content creation and modifications:

#### Item Listings

- **item_listed**: User creates a new item listing
  - Metadata: `itemTitle`, `category`, `price`, `type` (rent/borrow/trade)
  - Severity: `info`
- **item_updated**: User modifies an existing listing
  - Metadata: `itemId`, `itemTitle`, `fieldsUpdated`
  - Severity: `info`
- **item_deleted**: User removes a listing
  - Metadata: `itemId`, `itemTitle`, `reason`
  - Severity: `info`

#### Giveaways

- **giveaway_created**: User creates a giveaway
  - Metadata: `itemTitle`, `condition`, `location`
  - Severity: `info`
- **giveaway_claimed**: User claims a giveaway
  - Metadata: `giveawayId`, `itemTitle`, `claimerId`, `claimerName`
  - Severity: `info`

### 4. Administrative Actions (`category: 'admin'`)

Admins can see all administrative operations:

#### User Management

- **user_verified**: Admin verifies a user account
  - Metadata: `userId`, `userName`, `verificationType`
  - Severity: `info`
- **user_banned**: Admin bans a user
  - Metadata: `userId`, `userName`, `reason`, `duration`
  - Severity: `critical`
- **user_unbanned**: Admin restores a banned user
  - Metadata: `userId`, `userName`
  - Severity: `info`

#### Report Management

- **report_resolved**: Admin resolves a user report
  - Metadata: `reportId`, `reportedUser`, `reportType`, `resolution`
  - Severity: `warning` or `info`

#### Verification

- **verification_approved**: Admin approves ID verification
  - Metadata: `userId`, `userName`, `idType`
  - Severity: `info`
- **verification_rejected**: Admin rejects ID verification
  - Metadata: `userId`, `userName`, `rejectionReason`
  - Severity: `info`

#### Disputes

- **dispute_opened**: User opens a dispute
  - Metadata: `itemTitle`, `lender`, `damageType`, `estimatedCost`
  - Severity: `warning`
- **dispute_resolved**: Admin resolves a dispute
  - Metadata: `disputeId`, `resolution`, `parties`, `outcome`
  - Severity: `info` or `warning`

### 5. System Events (`category: 'system'`)

Admins can monitor system-level activities:

#### Calamity Events

- **calamity_event_created**: Admin creates a calamity donation event
  - Metadata: `eventTitle`, `calamityType`, `targetAmount`, `status`
  - Severity: `critical`

#### Notifications

- **bulk_notification_sent**: System sends bulk notifications
  - Metadata: `notificationType`, `recipientCount`
  - Severity: `info`

#### Security Events

- **failed_login_attempt**: Multiple failed login attempts detected
  - Metadata: `attemptCount`, `ipAddress`, `targetAccount`
  - Severity: `warning`

#### System Maintenance

- **database_backup**: Automated backup completed
  - Metadata: `backupSize`, `duration`
  - Severity: `info`

## What Admins Can See

### In the Logs Interface

1. **Real-time Activity Stream**: All logs appear in real-time as they occur
2. **Search Functionality**: Search logs by description, action, or actor name
3. **Filtering Options**:
   - By Category (User, Transaction, Content, Admin, System)
   - By Severity (Info, Warning, Critical)
   - By Time Range (Today, This Week, This Month, All Time)
4. **Detailed View**: Each log card shows:
   - Category badge with color coding
   - Severity indicator
   - Timestamp (relative or absolute)
   - Description
   - Actor name
   - Target type (if applicable)
   - Expandable metadata section with all additional details

### Information Available Per Log

- **Who**: Actor name and ID
- **What**: Action type and description
- **When**: Exact timestamp
- **Where**: Target resource (item, user, transaction) if applicable
- **Why/How**: Metadata with context-specific information
- **Importance**: Severity level

## Privacy & Security

- **Access Control**: Only admins can view activity logs (enforced by Firestore security rules)
- **Data Retention**: Logs are stored indefinitely unless manually deleted
- **Sensitive Data**: Email addresses and personal information may appear in metadata - handle with care
- **Audit Trail**: All admin actions are logged for accountability

## Current Implementation Status

⚠️ **Note**: The logging infrastructure is fully set up, but activity logs are currently only created through the `SampleLogsGenerator` utility. To enable automatic logging for user activities, you need to add `createActivityLog()` calls in the appropriate places:

### Recommended Integration Points:

1. **User Registration** (`lib/screens/auth/register.dart`)

   - Log when new users register

2. **Item Creation** (`lib/providers/item_provider.dart`)

   - Log when users create/update/delete items

3. **Transaction Actions** (Borrow/Rent/Trade providers)

   - Log when users create requests, accept/reject offers, complete transactions

4. **Admin Actions** (Admin screens)

   - Log when admins verify users, ban users, resolve reports

5. **Payment Processing**
   - Log payment transactions

## Example: Adding Logging to User Registration

```dart
// In register.dart after successful registration
await firestoreService.createActivityLog(
  category: 'user',
  action: 'user_registered',
  actorId: uid,
  actorName: '${firstName} ${lastName}',
  description: 'New user registered on the platform',
  metadata: {
    'email': email,
    'method': 'email',
    'province': province,
    'city': city,
  },
  severity: 'info',
);
```

## Summary

Admins can track:

- ✅ All user account activities (registration, verification, profile updates)
- ✅ All transactions (borrow, rent, trade requests and completions)
- ✅ All content changes (item listings, giveaways)
- ✅ All administrative actions (verifications, bans, report resolutions)
- ✅ System events (calamity events, notifications, security events)

Each log provides complete context including who, what, when, where, and why, making it easy for admins to monitor platform activity and investigate issues.
