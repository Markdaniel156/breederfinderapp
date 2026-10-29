# Implementation Plan - Sync User Role After Application Approval

Add a synchronization function to ensure that once a customer's seller application is approved, their account role and verification status are automatically updated in the `create_account` table.

## User Review Required

> [!IMPORTANT]
> This logic runs on the client-side (app) and triggers a synchronization when a user logs in or starts the app. This is a practical approach for projects without complex backend triggers or server-side functions.

## Proposed Changes

### Auth Provider
#### [MODIFY] [auth_provider.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/providers/auth_provider.dart)
- Add `syncUserRoleAfterApproval(String userId)` method to handle the logic of checking `seller_applications` and updating `create_account`.

### Initialization Logic
#### [MODIFY] [main.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/main.dart)
- Update `_fetchUserRole` to call `syncUserRoleAfterApproval` for authenticated users.

### Login Logic
#### [MODIFY] [login_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/login_screen.dart)
- Call `syncUserRoleAfterApproval` after a successful login to ensure the role is updated immediately upon the first login after approval.

## Verification Plan

### Automated Tests
- N/A (Manual verification on device/emulator is preferred for UI/Supabase flows)

### Manual Verification
1. **Mock Data:** Manually set a user's application status to 'APPROVED' and `role_applied` to 'BREEDER' in the `seller_applications` table using Supabase dashboard.
2. **Launch App:** Open the app with that user already logged in. Verify the role updates from 'CUSTOMER' to 'BREEDER'.
3. **Login:** Log out and log back in. Verify the "Account Approved" notification appears and the role is correct.
