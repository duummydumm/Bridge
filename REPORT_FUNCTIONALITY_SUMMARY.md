# Report Functionality Summary

## ✅ Currently Implemented Report Features

### 1. **User Reports** (reportUser)

Users can report other users from:

#### a. **User Profile Screen** (`lib/screens/user_public_profile_screen.dart`)

- **Location**: Profile menu (three dots icon in AppBar)
- **Context Type**: `'profile'`
- **Features**:
  - Report reasons: Spam, Harassment, Inappropriate Content, Fraud, Other
  - Optional description field
  - Reports the user profile

#### b. **Chat Detail Screen** (`lib/screens/chat_detail_screen.dart`)

- **Location**: Options menu (three dots icon in AppBar) → "Report User"
- **Context Type**: `'chat'`
- **Context ID**: Conversation ID
- **Features**:
  - Report reasons: Spam, Harassment, Inappropriate Content, Fraud, Other
  - Optional description field
  - Links report to specific conversation

### 2. **Content Reports** (reportContent)

Users can report content from:

#### a. **Giveaway Detail Screen** (`lib/screens/donate/giveaway_detail_screen.dart`)

- **Location**: Options menu or report button
- **Content Type**: `'giveaway'`
- **Features**:
  - Report reasons: Spam, Inappropriate Content, Fraud, Other
  - Optional description field
  - Updates giveaway's `reportCount` and `isReported` flag

---

## ❌ Missing Report Functionality (Should Be Added)

### 1. **Item/Borrow Reports**

**Screens that need report functionality:**

#### a. **Borrow Items Screen** (`lib/screens/borrow/borrow_items_screen.dart`)

- **What to report**: Items available for borrowing
- **Content Type**: `'item'`
- **Where to add**: Item detail view or item card menu
- **Context**: Item listing for borrowing

#### b. **Borrowed Items Detail Screen** (`lib/screens/borrow/borrowed_items_detail_screen.dart`)

- **What to report**: Specific borrowed item or the lender
- **Content Type**: `'item'` (for item) or use `reportUser` (for lender)
- **Where to add**: AppBar actions menu
- **Context**: Active borrowing transaction

### 2. **Rental Reports**

**Screens that need report functionality:**

#### a. **Rent Items Screen** (`lib/screens/rental/rent_items_screen.dart`)

- **What to report**: Rental listings
- **Content Type**: `'item'` or `'rental'`
- **Where to add**: Rental listing detail view
- **Context**: Rental item listing

#### b. **Rental Detail Screen** (`lib/screens/rental/rent_item_screen.dart`)

- **What to report**: Rental listing or owner
- **Content Type**: `'item'` or `'rental'` (for listing) or use `reportUser` (for owner)
- **Where to add**: AppBar actions menu
- **Context**: Rental listing details

#### c. **Active Rental Detail Screen** (`lib/screens/rental/active_rental_detail_screen.dart`)

- **What to report**: Active rental or the other party
- **Content Type**: `'rental'` (for rental) or use `reportUser` (for other party)
- **Where to add**: AppBar actions menu
- **Context**: Active rental transaction

#### d. **Rental Request Detail Screen** (`lib/screens/rental/rental_request_detail_screen.dart`)

- **What to report**: Rental request or the other party
- **Content Type**: `'rental'` (for request) or use `reportUser` (for other party)
- **Where to add**: AppBar actions menu
- **Context**: Rental request details

### 3. **Trade Reports**

**Screens that need report functionality:**

#### a. **Trade Items Screen** (`lib/screens/trade/trade_items_screen.dart`)

- **What to report**: Trade item listings
- **Content Type**: `'item'` or `'trade'`
- **Where to add**: Trade item detail view or card menu
- **Context**: Trade item listing

#### b. **Trade Offer Detail Screen** (`lib/screens/trade/trade_offer_detail_screen.dart`)

- **What to report**: Trade offer or the other party
- **Content Type**: `'trade'` (for offer) or use `reportUser` (for other party)
- **Where to add**: AppBar actions menu
- **Context**: Trade offer details

### 4. **Item Detail Screens (General)**

**Screens that might need report functionality:**

#### a. **Due Soon Items Detail Screen** (`lib/screens/due_soon_items_detail_screen.dart`)

- **What to report**: Item or lender
- **Content Type**: `'item'` (for item) or use `reportUser` (for lender)
- **Where to add**: AppBar actions menu

---

## 📋 Implementation Guide

### For Adding Item/Content Reports:

1. **Import the service:**

```dart
import '../../services/report_block_service.dart';
final ReportBlockService _reportBlockService = ReportBlockService();
```

2. **Add report button/menu item:**

```dart
// In AppBar actions or menu
IconButton(
  icon: const Icon(Icons.flag_outlined, color: Colors.orange),
  onPressed: () => _reportItem(),
)
```

3. **Create report dialog:**

```dart
void _reportItem() {
  String selectedReason = 'spam';
  final TextEditingController descriptionController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Report Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reason selection (RadioListTile)
              // Description field (TextField)
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _reportBlockService.reportContent(
                reporterId: authProvider.user!.uid,
                reporterName: userProvider.currentUser?.fullName ?? 'Unknown',
                contentType: 'item', // or 'trade', 'rental'
                contentId: itemId,
                contentTitle: itemTitle,
                ownerId: ownerId,
                ownerName: ownerName,
                reason: selectedReason,
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
              );
              // Show success message
            },
            child: const Text('Report'),
          ),
        ],
      ),
    ),
  );
}
```

### For Adding User Reports in Detail Screens:

Use the same pattern as in `chat_detail_screen.dart`:

- Add to AppBar actions menu
- Use `reportUser()` method
- Set appropriate `contextType` (e.g., `'trade'`, `'rental'`, `'borrow'`)
- Include `contextId` if applicable

---

## 🎯 Priority Recommendations

### High Priority:

1. **Trade Offer Detail Screen** - Users need to report problematic trade offers
2. **Rental Detail Screens** - Users need to report problematic rentals/owners
3. **Borrow Items Screen** - Users need to report problematic items

### Medium Priority:

4. **Trade Items Screen** - Report trade listings
5. **Active Rental Detail** - Report during active rental

### Low Priority:

6. **Due Soon Items Detail** - Less critical, but good to have

---

## 📝 Notes

- The `reportContent()` method in `report_block_service.dart` currently only updates `reportCount` for giveaways. You may want to extend it to handle items and trades similarly.
- Consider adding report counts to item models if not already present.
- All reports go to the same `reports` collection and are viewable in the Admin Reports Tab.
