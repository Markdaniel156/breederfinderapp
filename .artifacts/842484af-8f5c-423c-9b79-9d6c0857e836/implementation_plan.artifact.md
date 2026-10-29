# Implementation Plan - Fix Profile Navigation from Post Card

The user is unable to visit the profile of a user when tapping their profile information in a post card. This likely affects both the main feed listings and the detail views.

## User Review Required

> [!IMPORTANT]
> I will be making the profile section clickable in both the main listing card and the detailed bottom sheet that opens when a card is tapped.

## Proposed Changes

### [Home Screen](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart)

#### [MODIFY] [home_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart)
- Update `_buildListingItem` to ensure the profile `GestureDetector` captures taps correctly, possibly by using `HitTestBehavior.opaque`.
- Update `_buildProfileRow` to accept a `userId` and wrap its content in a `GestureDetector` that navigates to the `ProfileScreen`.
- Update calls to `_buildProfileRow` in `_showTraderDetails` and `_showAnimalImages` to pass the correct `userId`.
- Update `_buildReviewItem` to make the reviewer's profile clickable.

### [Favorites Screen](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/favorites_screen.dart)

#### [MODIFY] [favorites_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/favorites_screen.dart)
- Update the bottom sheet in `_showPostDetails` to also allow navigation to the user's profile if applicable.
- Add a profile row to the favorite item if space permits, or ensure the detail sheet handles it.

## Verification Plan

### Manual Verification
- Tap on the profile image/name in the home screen feed -> Verify it opens the correct user's profile.
- Tap on a post card to open details -> Tap on the profile section in the bottom sheet -> Verify it opens the correct user's profile.
- Tap on a reviewer's profile in the review section -> Verify it opens the reviewer's profile.
