# Dedicated Subscriptions Table Integration

To resolve the issue where payment status is not being recorded, we will move the subscription tracking to a dedicated `subscriptions` table. This provides a better audit trail and simplifies permissions.

## User Review Required

> [!IMPORTANT]
> **New Table**: You will need to run a new SQL script to create the `subscriptions` table.
>
> **Migration**: We will stop relying on the `is_subscribed` and `subscription_expires_at` columns in the `create_account` table and instead query the new `subscriptions` table.

## Proposed Changes

### [Database]

#### [SQL Query]
- Create `subscriptions` table with columns: `id`, `user_id`, `plan_name`, `amount`, `expires_at`, `created_at`.
- Enable RLS for the `subscriptions` table.

### [Screens & Logic]

#### [MODIFY] [subscription_screen.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/screens/subscription_screen.dart)
- Update `_finalizeSubscription` to **insert** into the `subscriptions` table instead of updating `create_account`.

#### [MODIFY] [login_screen.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/screens/login_screen.dart)
- Update `_signIn` to check the `subscriptions` table for the latest valid (non-expired) record for the user.

#### [MODIFY] [main.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/main.dart)
- Update `_checkSubscription` to query the `subscriptions` table.

## Verification Plan

### Manual Verification
1. **SQL Setup**: Run the provided SQL script and verify the table is created.
2. **Payment Recording**: Perform a test payment and verify a new row appears in the `subscriptions` table.
3. **Access Control**: Verify that a user with a valid row in `subscriptions` can access the Home screen, while others are redirected.
