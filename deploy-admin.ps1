# Admin Interface Deployment Script
# This script builds and deploys the admin interface to Firebase Hosting

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Admin Interface Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Clean previous build
Write-Host "Step 1: Cleaning previous build..." -ForegroundColor Yellow
if (Test-Path "build/web") {
    Remove-Item -Recurse -Force "build/web"
    Write-Host "✅ Build directory cleaned" -ForegroundColor Green
}

# Step 2: Build the admin web app
Write-Host ""
Write-Host "Step 2: Building admin web app..." -ForegroundColor Green
flutter build web --release --target=lib/main_admin.dart

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ Build failed! Please check the errors above." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Build completed successfully!" -ForegroundColor Green
Write-Host ""

# Step 3: Deploy to Firebase Hosting
Write-Host "Step 3: Deploying to Firebase Hosting..." -ForegroundColor Green
firebase deploy --only hosting

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ Deployment failed! Please check the errors above." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ✅ Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your admin interface is now live at:" -ForegroundColor Yellow
Write-Host "  • https://bridge-72b26.web.app" -ForegroundColor White
Write-Host "  • https://bridge-72b26.firebaseapp.com" -ForegroundColor White
Write-Host ""

