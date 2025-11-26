# Testing the Feedback & Rating System

## ✅ Prerequisites

1. **Firebase Setup**: Make sure your Firebase project is configured
2. **Firestore Indexes**: Deploy the indexes from `firestore.indexes.json`
   ```bash
   firebase deploy --only firestore:indexes
   ```
3. **Two User Accounts**: You need at least 2 user accounts to test rating between users

---

## 🧪 Testing Methods

### **Method 1: Direct Testing (Easiest)**

Test the rating screen directly without going through rental completion.

#### Step 1: Get a User ID

1. Navigate to any user's public profile
2. Or use Firebase Console → Firestore → `users` collection
3. Copy any user ID (NOT your own ID if you want to rate someone else)

#### Step 2: Test the Rating Screen

You can test directly by navigating to the rating screen. Here are two ways:

**Option A: Add a Test Button (Recommended for Testing)**

Add this to your Profile Screen's action buttons or create a test route. You can temporarily add this code to navigate directly:

```dart
// In any screen where you want to test, add:
ElevatedButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubmitRatingScreen(
          ratedUserId: 'USER_ID_TO_RATE', // Replace with actual user ID
          ratedUserName: 'Test User',
          context: RatingContext.rental,
          transactionId: 'test-transaction-123', // Optional
          role: 'renter',
        ),
      ),
    );
  },
  child: Text('Test Rating Screen'),
)
```

**Option B: Use the Rental Detail Screen**

1. Go to `/rental/detail` route
2. Enter a rental request ID (if you have one)
3. Click "Mark Returned"
4. The rating prompt should appear

---

### **Method 2: Full Flow Testing (Real Scenario)**

Test the complete rental → rating flow:

#### Step 1: Create a Rental Request

1. Create a rental listing
2. Have another user request to rent it
3. Approve the request
4. Mark it as "Active"
5. Mark it as "Returned"

#### Step 2: Rating Prompt

- After marking as "Returned", a dialog should appear
- Click "Rate Now"
- The rating screen should open

---

### **Method 3: Test from Profile Screen**

Test viewing your own reviews:

1. Go to Profile Screen (`/profile`)
2. Scroll to "Reviews & Ratings" section
3. You should see:
   - Your average rating
   - List of reviews (if any)
   - "View All Reviews" button (if more than 2 reviews)

---

## 📝 Step-by-Step Testing Checklist

### ✅ Test 1: Submit a Rating

- [ ] Navigate to rating screen (use Method 1 or 2)
- [ ] Select star rating (1-5 stars)
- [ ] Enter optional feedback text
- [ ] Click "Submit Rating"
- [ ] Should see success message
- [ ] Check Firestore `ratings` collection for new document

### ✅ Test 2: View Reviews on Profile

- [ ] Go to Profile Screen
- [ ] Check "Reviews & Ratings" section shows:
  - Average rating (calculated from all ratings)
  - List of reviews
  - Star rating display
- [ ] Click "View All Reviews" (if more than 2)
- [ ] Verify all reviews are displayed

### ✅ Test 3: View Public Profile Reviews

- [ ] Go to another user's public profile
- [ ] Verify reviews section is visible
- [ ] Check that rating is displayed correctly
- [ ] Verify review items show correct information

### ✅ Test 4: Reputation Score Update

- [ ] Submit a rating for a user
- [ ] Check Firestore `users/{userId}` document
- [ ] Verify `reputationScore` field is updated
- [ ] Check profile screen shows updated score

### ✅ Test 5: Prevent Duplicate Ratings

- [ ] Try to rate the same user for the same transaction twice
- [ ] Should see error: "You have already rated this user for this transaction"
- [ ] Rating should not be submitted

### ✅ Test 6: Different Rating Contexts

Test rating for different transaction types:

- [ ] Rental (`RatingContext.rental`)
- [ ] Trade (`RatingContext.trade`) - if implemented
- [ ] Borrow (`RatingContext.borrow`) - if implemented
- [ ] Giveaway (`RatingContext.giveaway`) - if implemented

---

## 🔍 Verifying in Firestore

### Check Ratings Collection

```
Firestore → ratings collection
```

Each rating document should have:

- `ratedUserId` - User being rated
- `raterUserId` - User giving the rating
- `raterName` - Name of rater
- `rating` - Number (1-5)
- `feedback` - Optional text
- `context` - "rental", "trade", "borrow", or "giveaway"
- `transactionId` - Optional transaction ID
- `role` - "owner", "renter", "borrower", "lender", etc.
- `createdAt` - Timestamp
- `updatedAt` - Optional timestamp

### Check User Reputation

```
Firestore → users/{userId} → reputationScore
```

Should be a number between 0.0 and 5.0, calculated as average of all ratings.

---

## 🐛 Troubleshooting

### Issue: "Error fetching ratings" or No Reviews Showing

**Solution**:

- Check Firestore indexes are deployed
- Verify you have the `ratings` collection in Firestore
- Check console for error messages

### Issue: Reputation Score Not Updating

**Solution**:

- Check Firestore rules allow updates to `users` collection
- Verify `updateUserReputationScore()` is being called after rating submission
- Check console for errors

### Issue: Rating Screen Not Appearing After "Mark Returned"

**Solution**:

- Verify you're logged in
- Check that rental request exists and has correct `ownerId` and `renterId`
- Check console for error messages (should be in debugPrint)

### Issue: Firestore Index Errors

**Solution**:

```bash
# Deploy indexes
firebase deploy --only firestore:indexes

# Or create indexes manually in Firebase Console
```

---

## 🚀 Quick Test Commands

### Create a Test Rating via Firebase Console

1. Go to Firestore Console
2. Create a new document in `ratings` collection
3. Add these fields:

```json
{
  "ratedUserId": "USER_ID_1",
  "raterUserId": "USER_ID_2",
  "raterName": "Test Rater",
  "context": "rental",
  "rating": 5,
  "feedback": "Great experience!",
  "role": "renter",
  "createdAt": [TIMESTAMP],
  "transactionId": "test-123"
}
```

4. Check that user's profile to see the review

---

## 📱 Testing Checklist Summary

- [x] Submit rating works
- [x] View reviews on profile works
- [x] View reviews on public profile works
- [x] Reputation score calculates correctly
- [x] Duplicate ratings prevented
- [x] All rating contexts work
- [x] Firestore indexes deployed
- [x] No console errors

---

## 💡 Pro Tips

1. **Use Firebase Console** to manually check/create test data
2. **Use two devices/accounts** to test bidirectional ratings
3. **Check browser/device console** for debug messages
4. **Test with different rating values** (1-5 stars) to verify calculations
5. **Test with and without feedback** text to ensure both work

---

Happy Testing! 🎉
