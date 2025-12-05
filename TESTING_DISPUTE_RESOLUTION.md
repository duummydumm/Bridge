# Testing Guide: Dispute Resolution Workflow

This guide will help you test the complete dispute resolution workflow for borrowed items.

## Prerequisites

1. **Two test accounts** (or use two devices/browsers):

   - **Lender Account**: The person lending the item
   - **Borrower Account**: The person borrowing the item

2. **Test Item**: Create an item in the app that can be borrowed

## Test Scenario Setup

### Step 1: Create a Borrow Request Flow

1. **As Borrower**:

   - Browse items and find a test item
   - Request to borrow the item
   - Wait for lender approval

2. **As Lender**:

   - Go to "My Borrow Requests" or notifications
   - Approve the borrow request
   - Set a return date

3. **As Borrower**:
   - Confirm the item is borrowed (status should be "borrowed")

### Step 2: Initiate Return (Borrower)

1. **As Borrower**:

   - Navigate to "My Borrowed Items" or "Active Borrows"
   - Find the borrowed item
   - Click "Return Item"
   - Fill in condition report:
     - Condition: Select "Same", "Better", "Worse", or "Damaged"
     - Add notes (optional)
     - Upload photos (optional)
   - Submit the return

   **Expected Result**:

   - Status changes to "return_initiated"
   - Lender receives notification

### Step 3: Lender Disputes Return

1. **As Lender**:

   - Go to "Pending Returns" or notifications
   - Find the return request
   - Review borrower's condition report
   - Click "Dispute Return" or "Reject Condition"
   - Fill in damage report:
     - Description of damage
     - Estimated repair cost (e.g., ₱500.00)
     - Upload damage photos (optional)
   - Submit dispute

   **Expected Result**:

   - Status changes to "return_disputed"
   - Borrower receives notification
   - Item appears in:
     - Borrower's "Disputed Returns" screen
     - Lender's "Lender Disputes" screen

---

## Testing Dispute Resolution Workflow

### Test Case 1: Lender Proposes Compensation → Borrower Accepts

#### Step 1: Lender Proposes Compensation

1. **As Lender**:

   - Navigate to: **Borrow → Lender Disputes** (from drawer menu)
   - Find the disputed item
   - Click **"Propose Compensation"** button
   - Enter:
     - Amount: e.g., `₱500.00`
     - Notes (optional): e.g., "For repair of damaged screen"
   - Click **"Propose"**

   **Expected Result**:

   - Status badge shows "Proposal Pending" (blue)
   - Compensation proposal appears in dispute card
   - Borrower receives notification: "Compensation proposal received"
   - Button changes to show proposal is pending

#### Step 2: Borrower Views Proposal

1. **As Borrower**:
   - Navigate to: **Borrow → Disputed Returns** (from drawer menu)
   - Find the disputed item with compensation proposal
   - Verify:
     - Status badge shows "Proposal Pending" (blue)
     - Compensation amount is displayed
     - Proposal notes are shown (if provided)
     - "Accept" and "Reject" buttons are visible

#### Step 3: Borrower Accepts Compensation

1. **As Borrower**:

   - Click **"Accept"** button
   - Confirm the acceptance

   **Expected Result**:

   - Status badge changes to "Compensation Accepted" (green)
   - Message: "Compensation proposal accepted. Lender will be notified."
   - Lender receives notification: "Compensation accepted"
   - Item status changes to "returned"
   - Item becomes available again

#### Step 4: Lender Records Payment

1. **As Lender**:

   - Go to **Lender Disputes** screen
   - Find the dispute with "Compensation Accepted" status
   - Click **"Record Payment"** button
   - Enter payment details:
     - Payment method (optional)
     - Payment date (optional)
     - Notes (optional)
   - Click **"Record Payment"**

   **Expected Result**:

   - Status badge changes to "Resolved" (green)
   - Message: "Payment recorded. Dispute resolved."
   - Dispute is marked as resolved
   - Dispute disappears from active disputes list (or shows as resolved)

---

### Test Case 2: Lender Proposes Compensation → Borrower Rejects

#### Step 1-2: Same as Test Case 1 (Lender proposes, Borrower views)

#### Step 3: Borrower Rejects Compensation

1. **As Borrower**:

   - Click **"Reject"** button
   - Enter rejection reason (optional): e.g., "Amount is too high"
   - Confirm rejection

   **Expected Result**:

   - Status badge changes to "Compensation Rejected" (orange)
   - Message: "Compensation proposal rejected. Lender will be notified."
   - Lender receives notification: "Compensation rejected"
   - Lender can see rejection reason (if provided)

#### Step 4: Lender Sees Rejection

1. **As Lender**:
   - Go to **Lender Disputes** screen
   - Find the dispute
   - Verify:
     - Status shows "Proposal Rejected" (orange)
     - Rejection reason is displayed (if provided)
     - **"Propose New Amount"** button is available
     - **"Message Borrower"** button is available

#### Step 5: Lender Proposes New Amount (Optional)

1. **As Lender**:

   - Click **"Propose New Amount"**
   - Enter a different amount (e.g., ₱300.00)
   - Add notes explaining the new proposal
   - Submit

   **Expected Result**:

   - New proposal is created
   - Status changes back to "Proposal Pending"
   - Borrower receives new notification
   - Cycle can repeat (accept/reject)

---

### Test Case 3: View Dispute Details Modal

#### As Borrower:

1. Go to **Disputed Returns** screen
2. Click on any dispute card
3. **Expected**: Modal opens showing:
   - Full item details
   - Damage report with photos
   - Compensation proposal (if any)
   - Action buttons (Accept/Reject/Message)
   - All condition photos from both parties

#### As Lender:

1. Go to **Lender Disputes** screen
2. Click on any dispute card
3. **Expected**: Modal opens showing:
   - Full item details
   - Borrower's condition report
   - Damage report with photos
   - Compensation proposal status
   - Action buttons (Propose/Record Payment/Message)

---

### Test Case 4: Edge Cases

#### Test 4.1: Multiple Proposals

1. Lender proposes ₱500
2. Borrower rejects
3. Lender proposes ₱300
4. Borrower accepts
5. **Expected**: Latest proposal is the active one

#### Test 4.2: Message Functionality

1. From any dispute card, click **"Message Lender"** (borrower) or **"Message Borrower"** (lender)
2. **Expected**:
   - Chat screen opens
   - Conversation is created/linked to the item
   - Can discuss dispute details

#### Test 4.3: Notification Flow

Check notifications at each step:

- ✅ Borrower receives notification when lender proposes
- ✅ Lender receives notification when borrower accepts
- ✅ Lender receives notification when borrower rejects
- ✅ Borrower receives notification when lender records payment

---

## Quick Test Checklist

### Borrower Side:

- [ ] Can view disputed returns in "Disputed Returns" screen
- [ ] Can see compensation proposals
- [ ] Can accept compensation proposal
- [ ] Can reject compensation proposal with reason
- [ ] Can message lender from dispute screen
- [ ] Receives notifications for proposals
- [ ] Status badges update correctly

### Lender Side:

- [ ] Can view disputes in "Lender Disputes" screen
- [ ] Can propose compensation amount
- [ ] Can see proposal status (pending/accepted/rejected)
- [ ] Can record payment after acceptance
- [ ] Can propose new amount after rejection
- [ ] Can message borrower from dispute screen
- [ ] Receives notifications for accept/reject
- [ ] Status badges update correctly

### Data Integrity:

- [ ] Item status updates correctly (disputed → returned → available)
- [ ] Dispute resolution data is saved in Firestore
- [ ] All timestamps are recorded
- [ ] Notifications are created correctly
- [ ] No duplicate proposals can be created while one is pending

---

## Manual Firestore Testing (Optional)

If you want to test directly in Firestore Console:

### Create a Test Dispute:

1. Find a `borrow_requests` document with status `'accepted'`
2. Update it to:

```json
{
  "status": "return_disputed",
  "returnConfirmedAt": [Firestore Timestamp],
  "damageReport": {
    "description": "Screen cracked",
    "estimatedCost": 500.00,
    "photos": []
  }
}
```

3. Then test the workflow from the app

### Check Dispute Resolution Data:

After testing, check the `borrow_requests` document for:

```json
{
  "disputeResolution": {
    "proposedAmount": 500.00,
    "proposedBy": "lender_user_id",
    "proposedAt": [Timestamp],
    "proposalNotes": "For repair",
    "status": "proposal_pending" // or "accepted", "rejected", "resolved"
  }
}
```

---

## Troubleshooting

### Issue: "Can only propose compensation for disputed returns"

- **Solution**: Make sure the borrow request status is `'return_disputed'`

### Issue: "Only the lender can propose compensation"

- **Solution**: Make sure you're logged in as the lender account

### Issue: Dispute not showing in screens

- **Solution**:
  - Check Firestore: status should be `'return_disputed'`
  - Refresh the screen
  - Check user IDs match (lenderId/borrowerId)

### Issue: Notifications not appearing

- **Solution**:
  - Check Firestore `notifications` collection
  - Verify `toUserId` matches the logged-in user
  - Check notification type matches expected values

---

## Success Criteria

✅ **Workflow is complete** when:

1. Lender can propose compensation
2. Borrower can accept/reject
3. Lender can record payment
4. Item status updates correctly
5. All parties receive notifications
6. UI reflects correct status at each step
7. No errors in console/logs

---

## Next Steps After Testing

If everything works:

- ✅ Feature is ready for production
- Consider adding analytics tracking
- Consider adding email notifications (optional)

If issues found:

- Document the issue
- Check Firestore rules/permissions
- Verify user authentication
- Check network connectivity
