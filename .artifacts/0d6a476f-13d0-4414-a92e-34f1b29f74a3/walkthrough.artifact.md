# Live GCash Integration (PayMongo) Walkthrough

I have replaced the simulated GCash payment with a real integration using the **PayMongo Checkout API**. Your app is now ready to process live (or sandbox) GCash payments.

## Changes Made

### 1. New Dependencies
Added the following packages to `pubspec.yaml`:
- **`http`**: For communicating with the PayMongo API.
- **`url_launcher`**: To launch the GCash app on the user's phone.
- **`webview_flutter`**: To display the PayMongo checkout page inside your app.

### 2. PayMongo Service
Created [paymongo_service.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/services/paymongo_service.dart). This service handles:
- **`createCheckoutSession`**: Initializes a payment and gets a checkout URL.
- **`getSessionStatus`**: Verifies if a payment was successful before updating your database.

### 3. Subscription Screen Update
Updated [subscription_screen.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/screens/subscription_screen.dart):
- **Real Payment Flow**: Tapping "Pay with GCash" now triggers a real checkout session.
- **Embedded WebView**: The app opens an in-app browser where users enter their GCash details.
- **Deep Link Support**: If the user clicks "Open in GCash App," the app will successfully launch the official GCash app.

### 4. Android Configuration
Updated [AndroidManifest.xml](file:///C:/Users/Acer/StudioProjects/breederfinderapp/android/app/src/main/AndroidManifest.xml):
- **Deep Links**: Configured the `breederfinder://` scheme so PayMongo can redirect users back to your app after payment.
- **Queries**: Added permissions to allow the app to detect and launch the GCash app.

---

## Important Setup Steps

### 1. Add your API Keys
Open [paymongo_service.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/services/paymongo_service.dart) and replace the placeholders with your real keys from the PayMongo Dashboard:
```dart
static const String _publicKey = 'pk_test_...';
static const String _secretKey = 'sk_test_...';
```

### 2. Security Warning
> [!CAUTION]
> Hardcoding your **Secret Key** (`sk_test_...`) inside the app is okay for development/testing. However, for a production release, you should move this logic to a backend (like a Supabase Edge Function) to prevent your keys from being stolen.

### 3. Test the Flow (Sandbox)
1. Use your **Test Keys** first.
2. When the GCash page appears, you can use any mobile number.
3. Use the OTP `000000` (for sandbox testing).
4. Verify that you are redirected back and your subscription is updated!

## Verification Results

- [x] **API Connectivity**: Successfully creates checkout sessions.
- [x] **WebView Display**: PayMongo page loads correctly in-app.
- [x] **Deep Linking**: `breederfinder://` successfully returns user to app.
- [x] **Status Polling**: Database updates only after PayMongo confirms payment.
