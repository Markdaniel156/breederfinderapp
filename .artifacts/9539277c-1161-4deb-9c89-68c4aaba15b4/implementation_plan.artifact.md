# Profile Redirection Fix and Enhancement Implementation Plan

Fix the issue where tapping the profile in a post card does not navigate to the user's profile, and extend this functionality to the Market screen.

## User Review Required

> [!NOTE]
> I will be adjusting the tap detection logic on both the Home and Market screens. To ensure nested taps work correctly (the profile tap vs. the post detail tap), I will separate the hit areas or use more precise gesture handling.

## Proposed Changes

### home_screen.dart

#### [MODIFY] [home_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart)
- **Refactor `_buildListingItem`:**
    - Remove the top-level `GestureDetector` that wraps the entire card.
    - Add a `GestureDetector` specifically around the **Image** section to open post details.
    - Add a `GestureDetector` around the **Main Info** section (Name, Price, Location, Reviews) to open post details.
    - Ensure the **Profile Row** (Avatar + Poster Name) has its own `GestureDetector` that navigates to the `ProfileScreen`.
    - This separation prevents gesture conflicts and ensures the profile tap is always prioritized when hit.

### market_screen.dart

#### [MODIFY] [market_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/market_screen.dart)
- **Update `_buildAnimalGrid` item:**
    - Wrap the **Profile Row** (CircleAvatar + Poster Name) in a `GestureDetector`.
    - Implement `onTap` to navigate to `ProfileScreen(userId: breeder.userId)`.
    - Like the Home screen, ensure this tap is distinct from the image tap.

## Verification Plan

### Manual Verification
- **Home Screen:**
    - Tap the poster's name/avatar: Should open their profile.
    - Tap the animal image: Should open animal photos/details.
    - Tap the price/breed area: Should open animal photos/details.
- **Market Screen:**
    - Tap the poster's name/avatar in the grid card: Should open their profile.
    - Tap the animal image in the grid card: Should open animal details.
- **General:**
    - Verify that navigating to your own profile from a post still shows the "full" profile (with settings).
    - Verify that navigating to someone else's profile shows the "public" profile (Message button, no settings).
