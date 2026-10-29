# Implementation Plan - Header UI Refinements

Refine the Home Screen header by removing icon backgrounds and fix the status bar visibility on the Feedback Screen.

## Proposed Changes

### [Home Screen]

#### [MODIFY] [home_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart)
- Update `_buildHeaderAction` to remove the semi-transparent white background (`Colors.white.withValues(alpha: 0.15)`) and border/shadow-like appearance. This will make the icons (Feedback and Notification) appear cleaner directly on the green gradient.

### [Feedback Screen]

#### [MODIFY] [feedback_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/feedback_screen.dart)
- Add `import 'package:flutter/services.dart';`.
- Update the `AppBar` to include `systemOverlayStyle`. This will ensure the status bar icons (battery, signal, time) are correctly colored based on the theme (dark icons for light mode, light icons for dark mode).

## Verification Plan

### Manual Verification
1.  Open the **Home Screen** and verify the Feedback and Notification icons no longer have a "box" or "shadow" around them.
2.  Navigate to the **Feedback Screen**.
3.  Verify the status bar icons (battery, signal, etc.) are clearly visible at the top of the screen.
