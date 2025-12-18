# Script to apply CORS configuration to Firebase Storage
# This fixes the issue where images don't load in the deployed admin app

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Firebase Storage CORS Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if gsutil is installed
Write-Host "Checking for gsutil..." -ForegroundColor Yellow
$gsutilCheck = Get-Command gsutil -ErrorAction SilentlyContinue

if (-not $gsutilCheck) {
    Write-Host ""
    Write-Host "❌ gsutil is not installed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install Google Cloud SDK:" -ForegroundColor Yellow
    Write-Host "  1. Download from: https://cloud.google.com/sdk/docs/install" -ForegroundColor White
    Write-Host "  2. Run the installer" -ForegroundColor White
    Write-Host "  3. Restart your terminal" -ForegroundColor White
    Write-Host "  4. Run this script again" -ForegroundColor White
    Write-Host ""
    Write-Host "Or use Method 3 in FIX_STORAGE_CORS.md (Google Cloud Console)" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ gsutil found!" -ForegroundColor Green
Write-Host ""

# Check if cors.json exists
if (-not (Test-Path "cors.json")) {
    Write-Host "❌ cors.json not found!" -ForegroundColor Red
    Write-Host "Make sure you're running this script from the project root." -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ cors.json found!" -ForegroundColor Green
Write-Host ""

# Default bucket name (adjust if different)
$bucketName = "bridge-72b26.firebasestorage.app"

Write-Host "Bucket name: $bucketName" -ForegroundColor Cyan
Write-Host ""
Write-Host "If your bucket name is different, edit this script and change `$bucketName" -ForegroundColor Yellow
Write-Host ""

# Ask for confirmation
$confirm = Read-Host "Apply CORS configuration? (y/n)"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Applying CORS configuration..." -ForegroundColor Green
Write-Host ""

# Apply CORS
try {
    $result = gsutil cors set cors.json "gs://$bucketName" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ CORS configuration applied successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Verifying configuration..." -ForegroundColor Yellow
        
        # Verify
        gsutil cors get "gs://$bucketName"
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  ✅ CORS Configuration Complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Your admin app should now be able to load images." -ForegroundColor Yellow
        Write-Host "Note: Changes may take a few minutes to propagate." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Test by:" -ForegroundColor White
        Write-Host "  1. Open your admin app: https://bridge-72b26.web.app" -ForegroundColor White
        Write-Host "  2. Navigate to User Verification" -ForegroundColor White
        Write-Host "  3. Check if ID images load" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "❌ Failed to apply CORS configuration!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Possible issues:" -ForegroundColor Yellow
        Write-Host "  1. Not authenticated - Run: gcloud auth login" -ForegroundColor White
        Write-Host "  2. Wrong project - Run: gcloud config set project bridge-72b26" -ForegroundColor White
        Write-Host "  3. Wrong bucket name - Check in Firebase Console → Storage → Settings" -ForegroundColor White
        Write-Host ""
        Write-Host "Error output:" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "❌ Error: $_" -ForegroundColor Red
    exit 1
}

