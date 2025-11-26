# Firebase Storage Organization Guide

## 📁 Recommended Folder Structure

All listing images are now organized in a clean, scalable structure:

```
listings/
  ├── borrow/          # For borrow/lend items
  │   └── {userId}/
  │       └── {itemId}/
  │           └── image_{timestamp}.jpg
  ├── rent/            # For rental listings
  │   └── {userId}/
  │       └── {listingId}/
  │           └── image_{timestamp}.jpg
  ├── trade/           # For trade items
  │   └── {userId}/
  │       └── {itemId}/
  │           └── image_{timestamp}.jpg
  └── donate/          # For donate items
      └── {userId}/
          └── {itemId}/
              └── image_{timestamp}.jpg
```

### Benefits:

- ✅ **Organized by listing type** - Easy to browse in Firebase Console
- ✅ **Organized by user** - All images for a user are grouped together
- ✅ **Organized by item** - All images for a specific item are in one folder
- ✅ **Scalable** - Works well even with thousands of listings
- ✅ **Easy to clean up** - Can delete entire user folders if needed

## 🔧 Updated Upload Methods

### 1. Borrow/Lend/Donate Items

**Before:**

```dart
await storageService.uploadItemImage(
  file: imageFile,
  itemId: itemId,
);
```

**After:**

```dart
await storageService.uploadItemImage(
  file: imageFile,
  itemId: itemId,
  userId: userId,           // NEW: Required
  listingType: 'borrow',     // NEW: Required ('borrow' or 'donate')
);
```

**Note:** `'lend'` is automatically converted to `'borrow'` for consistency.

### 2. Rental Listings

**New dedicated method:**

```dart
await storageService.uploadRentalImage(
  file: imageFile,
  listingId: listingId,
  userId: userId,
);
```

**Or with compressed bytes:**

```dart
await storageService.uploadRentalImageBytes(
  bytes: compressedBytes,
  listingId: listingId,
  userId: userId,
  contentType: 'image/jpeg',
);
```

### 3. Trade Items

**New dedicated method:**

```dart
await storageService.uploadTradeImage(
  file: imageFile,
  itemId: itemId,
  userId: userId,
);
```

**Or with compressed bytes:**

```dart
await storageService.uploadTradeImageBytes(
  bytes: compressedBytes,
  itemId: itemId,
  userId: userId,
  contentType: 'image/jpeg',
);
```

## 📝 Code Examples

### Example 1: Uploading Borrow Item Images

```dart
final userProvider = Provider.of<UserProvider>(context, listen: false);
final userId = userProvider.currentUser?.uid ?? authProvider.user?.uid;

for (final image in selectedImages) {
  final imageUrl = await storageService.uploadItemImage(
    file: image,
    itemId: itemId,
    userId: userId!,
    listingType: 'borrow', // or 'donate'
  );
  imageUrls.add(imageUrl);
}
```

### Example 2: Uploading Rental Listing Images

```dart
final userProvider = Provider.of<UserProvider>(context, listen: false);
final userId = userProvider.currentUser?.uid ?? authProvider.user?.uid;

for (final image in selectedImages) {
  final imageUrl = await storageService.uploadRentalImage(
    file: image,
    listingId: listingId,
    userId: userId!,
  );
  imageUrls.add(imageUrl);
}
```

### Example 3: Uploading Trade Item Images

```dart
final userProvider = Provider.of<UserProvider>(context, listen: false);
final userId = userProvider.currentUser?.uid ?? authProvider.user?.uid;

final imageUrl = await storageService.uploadTradeImage(
  file: imageFile,
  itemId: tradeItemId,
  userId: userId!,
);
```

## 🔄 Migration Notes

### Backward Compatibility

- Old images in `items/{itemId}/` will continue to work
- New uploads will use the new structure
- Consider migrating old images gradually if needed

### Path Examples

**Old structure:**

```
items/
  └── item_123456/
      └── image_1234567890.jpg
```

**New structure:**

```
listings/
  └── borrow/
      └── user_abc123/
          └── item_123456/
              └── image_1234567890.jpg
```

## 🗑️ Deleting Images

The `deleteImages()` method automatically handles both old and new paths:

```dart
// Works with both old and new paths
await storageService.deleteImages(imageUrls);
```

## 📊 Firebase Console View

When you browse Firebase Storage, you'll see:

```
listings/
  ├── borrow/
  │   ├── user_abc123/
  │   │   ├── item_001/
  │   │   │   ├── image_1234567890.jpg
  │   │   │   └── image_1234567891.jpg
  │   │   └── item_002/
  │   │       └── image_1234567892.jpg
  │   └── user_def456/
  │       └── item_003/
  │           └── image_1234567893.jpg
  ├── rent/
  │   └── user_abc123/
  │       └── listing_001/
  │           └── image_1234567894.jpg
  ├── trade/
  │   └── user_abc123/
  │       └── trade_001/
  │           └── image_1234567895.jpg
  └── donate/
      └── user_abc123/
          └── item_004/
              └── image_1234567896.jpg
```

This makes it easy to:

- Find all images for a specific user
- Find all images for a specific listing type
- Clean up images when a user deletes their account
- Monitor storage usage by category
