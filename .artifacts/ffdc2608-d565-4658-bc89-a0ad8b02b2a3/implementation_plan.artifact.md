# Implementation Plan - Auto-Scrolling Promo Banner

The user wants the `PromoBanner` to scroll automatically (like GCash), even if the user doesn't swipe manually.

## Proposed Changes

### [Promo Banner]

#### [MODIFY] [promo_banner.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/home/promo_banner.dart)

- Convert `PromoBanner` from a `StatelessWidget` to a `StatefulWidget`.
- Implement `_PromoBannerState` to manage:
    - A `PageController` for programmatic scrolling.
    - A `Timer` to trigger scrolling every 4-5 seconds.
- In `initState`:
    - Initialize the `PageController`.
    - Start a periodic `Timer` that calls `_pageController.nextPage()` or loops back to the start if at the end of the slides.
- In `dispose`:
    - Cancel the `Timer` and dispose the `PageController` to prevent memory leaks.
- Ensure manual swiping still works and remains in sync with the auto-scroll logic.

## Verification Plan

### Manual Verification
- Open the **Home Screen**.
- Observe the **Promo Banner**:
    - It should automatically transition to the next slide after a few seconds.
    - When it reaches the last slide, it should smoothy loop back to the first slide.
    - Manual swiping should still work and correctly update the indicator dots.
- Verify that the transitions are smooth (using `Curves.easeInOut` and a reasonable duration).
