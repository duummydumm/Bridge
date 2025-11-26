# Testing Duplicate Account Prevention

## How to Test

### Step 1: Register Your First Account

1. Open the app and go to the registration screen
2. Fill in the registration form with:

   - **First Name**: John
   - **Last Name**: Doe
   - **Email**: john.doe@example.com (use a unique email)
   - **Street**: 123 Main Street
   - **Barangay**: Select any barangay
   - **City**: Oroquieta
   - **Province**: Misamis Occidental
   - Upload an ID image
   - Complete the registration

3. **Check the console/logs** - You should see:
   ```
   🔍 Checking for duplicate account...
   ✅ No duplicate found, proceeding with registration...
   ```

### Step 2: Try to Register with the Same Name and Address

1. **Log out** from the first account (or use a different device/browser)
2. Go to registration again
3. Fill in the form with:

   - **First Name**: John (same as before)
   - **Last Name**: Doe (same as before)
   - **Email**: john.doe2@example.com (different email)
   - **Street**: 123 Main Street (same as before)
   - **Barangay**: Same barangay as before
   - **City**: Oroquieta (same as before)
   - Upload an ID image

4. **Expected Result**:
   - Registration should be **BLOCKED**
   - You should see a red error message:
     > "An account with this name and address already exists. Each person can only have one account. If you already have an account, please log in instead."
5. **Check the console/logs** - You should see:
   ```
   🔍 Checking for duplicate account...
   🔍 Duplicate check result: true (found 1 matching user(s))
   ❌ Registration blocked: Duplicate account found
   ```

### Step 3: Test Address Normalization

The system normalizes addresses, so these should also be blocked:

**Test Case 1: Address Abbreviation**

- First account: "123 Main Street"
- Second attempt: "123 Main St" → Should be blocked (normalized to same address)

**Test Case 2: Case Variations**

- First account: "123 MAIN STREET"
- Second attempt: "123 main street" → Should be blocked (normalized to lowercase)

**Test Case 3: Different Email**

- First account: john.doe@example.com
- Second attempt: john.doe2@example.com (different email, same name/address) → Should be blocked

### Step 4: Test Email Duplicate Check

1. Try to register with the same email as an existing account
2. **Expected Result**:
   - Registration should be **BLOCKED**
   - Error message: "An account with this email already exists..."

### Step 5: Test Legitimate Registration

1. Register with completely different name and address
2. **Expected Result**: Registration should succeed

## Important Notes

### Firestore Composite Index Required

The duplicate check requires a **composite index** in Firestore. If you see an error in the console like:

```
⚠️ Note: You may need to create a composite index in Firestore Console
   The query requires an index on: firstName, lastName, street, barangay, city
```

**To create the index:**

1. Go to Firebase Console → Firestore Database
2. Click on "Indexes" tab
3. Click "Create Index"
4. Collection: `users`
5. Add fields in this order:
   - `firstName` (Ascending)
   - `lastName` (Ascending)
   - `street` (Ascending)
   - `barangay` (Ascending)
   - `city` (Ascending)
6. Click "Create"

**OR** - Firestore will automatically suggest creating the index when you run the query. Just click the link in the error message.

### What Gets Normalized

- **Names**: Converted to lowercase (John → john)
- **Addresses**:
  - Abbreviations normalized (St → street, Ave → avenue)
  - Special characters removed
  - Extra spaces removed
  - Converted to lowercase

### Testing Checklist

- [ ] First registration succeeds
- [ ] Duplicate name + address is blocked
- [ ] Duplicate email is blocked
- [ ] Address variations are caught (St vs Street)
- [ ] Case variations are caught (MAIN vs main)
- [ ] Different name/address registration succeeds
- [ ] Console logs show duplicate check results

## Debugging

If the duplicate check isn't working:

1. **Check the console logs** - Look for the 🔍 emoji messages
2. **Verify the Firestore index exists** - Check Firebase Console
3. **Check existing user data** - Make sure the first user was created with normalized fields
4. **Verify the query** - Check if the normalized values match exactly

## Expected Behavior Summary

| Scenario                                 | Result     |
| ---------------------------------------- | ---------- |
| Same email                               | ❌ Blocked |
| Same name + address                      | ❌ Blocked |
| Same name + address (different email)    | ❌ Blocked |
| Similar address (St vs Street)           | ❌ Blocked |
| Different name + address                 | ✅ Allowed |
| Different email + different name/address | ✅ Allowed |
