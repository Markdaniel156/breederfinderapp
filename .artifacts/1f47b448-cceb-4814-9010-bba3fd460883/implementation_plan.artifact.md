# Implementation Plan - Tiered Subscription Limits

This plan introduces a tiered subscription model for Breeders and Traders. Users will start with a limit of 3 free posts. After reaching this limit, they will be prompted to choose between a "Solo Plan" (10 listings) or an "Organization Plan" (Unlimited listings).

## Proposed Changes

### Breeder Provider

#### [MODIFY] [breeder_provider.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/providers/breeder_provider.dart)
- Update `isUserSubscribed` to return the plan name (or `null` if no active subscription).
- Update `addBreeder` to enforce tiered limits:
    - No Subscription: 3 posts limit.
    - "Solo Plan": 10 posts limit.
    - "Organization Plan": Unlimited posts.

### Subscription Screen

#### [MODIFY] [subscription_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/subscription_screen.dart)
- Update the `_plans` list to include:
    - **Solo Plan**: ₱499 (example price), 10 listings, "Best for Solo".
    - **Organization Plan**: ₱999 (example price), Unlimited listings, "Best for Organization".
- Update the UI to display these new plans and their descriptions.

## Verification Plan

### Manual Verification
1. **Free Tier**: Create 3 posts as a Breeder/Trader. Try to create a 4th post. Verify the "Limit Reached" dialog appears.
2. **Solo Plan**:
    - Subscribe to the "Solo Plan".
    - Create posts until you reach 10.
    - Try to create the 11th post and verify the limit is enforced (if applicable, or if we want to allow upgrade).
3. **Organization Plan**:
    - Subscribe to the "Organization Plan".
    - Verify that you can create more than 10 posts without any limit.
