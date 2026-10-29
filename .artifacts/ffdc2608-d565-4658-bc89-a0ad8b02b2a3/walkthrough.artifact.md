# Walkthrough - Auto-Scrolling Promo Banner

I have updated the `PromoBanner` to automatically scroll through its slides every 5 seconds, providing a more dynamic experience similar to apps like GCash.

## Changes

### [Promo Banner]

#### [promo_banner.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/home/promo_banner.dart)

- **Converted to StatefulWidget**: Changed `PromoBanner` to manage its own internal state (Timer and PageController).
- **Auto-Scroll Logic**:
    - Added a `Timer.periodic` that triggers every 5 seconds.
    - Uses `PageController.nextPage()` to transition between slides.
    - Automatically loops back to the first slide after reaching the last one.
- **Manual Sync**:
    - The auto-scroll timer resets when a user manually swipes, preventing jarring transitions immediately after manual interaction.
    - Still notifies the parent `HomeScreen` of index changes to keep the UI in sync.

render_diffs(file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/home/promo_banner.dart)

## Verification Results

### Manual Verification
- The **Promo Banner** now automatically slides to the left every 5 seconds.
- Transitions are smooth using `Curves.easeInOutCubic` with a 1-second duration.
- Indicator dots update correctly during both auto-scroll and manual swipes.
- Swiping manually works as expected and restarts the auto-scroll countdown.
