# Implementation Plan - Aesthetic Limit Reached Card

The goal is to improve the user experience when a listing limit is reached. Instead of a full-screen overlay that blocks the posting form immediately, we will show an aesthetic "Limit Reached" card in the listing management screens and a non-blocking warning within the posting forms.

## User Review Required

> [!IMPORTANT]
> The full-screen `SubscriptionPlansView` replacement in `BreederPostingsScreen` and `TraderPostingsScreen` will be removed in favor of a non-blocking form with a warning at the top and a disabled submit button. This allows users to still view the form but informs them clearly why they cannot post.

## Proposed Changes

### [Widgets]

#### [NEW] [limit_reached_card.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/limit_reached_card.dart)
Create a new, aesthetic card widget to be used across the app when a limit is reached. It will feature:
- A soft, gradient background.
- A clear "Limit Reached" message with details about the current limit.
- An "Upgrade Now" button that opens the subscription plans.

### [Screens]

#### [MODIFY] [breeder_postings_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/breeder_postings_screen.dart)
- Remove the logic that replaces the form with `SubscriptionPlansView` upon entry.
- Add `_isLimitReached` boolean to the state.
- Show the `LimitReachedCard` at the top of the form if `_isLimitReached` is true.
- Disable the "Submit" button and update its text if the limit is reached.

#### [MODIFY] [trader_postings_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/trader_postings_screen.dart)
- Same modifications as `BreederPostingsScreen`.

#### [MODIFY] [manage_listings_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/manage_listings_screen.dart)
- Add a check for the listing limit.
- Display the `LimitReachedCard` at the top of the listings list if the limit is reached.

#### [MODIFY] [profile_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/profile_screen.dart)
- Add the `LimitReachedCard` in the "Listings" tab if the limit is reached.

## Verification Plan

### Automated Tests
- N/A (UI focused)

### Manual Verification
1. Log in as a user with 3 postings (Free Tier).
2. Go to **My Listings** (or Profile -> Listings). Verify that an aesthetic "Limit Reached" card appears at the top.
3. Tap "Post New". Verify that the form opens (no overlay), but a "Limit Reached" card is visible at the top of the form.
4. Verify that the "Submit Registration" button is disabled or shows a limit warning.
5. Tap "Upgrade Now" in the card and verify it opens the subscription plans.
