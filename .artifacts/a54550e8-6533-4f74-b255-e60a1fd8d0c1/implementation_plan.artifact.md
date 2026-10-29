# Enhance Help Center with FAQ Navigation

The goal is to expand the FAQ content and improve the user experience by navigating to a dedicated details page for each question, rather than using expandable tiles on the main Help Center screen.

## User Review Required

> [!IMPORTANT]
> This change will replace the existing expandable FAQ functionality with a navigation-based approach.

## Proposed Changes

### Screens

#### [NEW] [faq_detail_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/faq_detail_screen.dart)
Create a new screen to display a single FAQ's question and its detailed answer.
- Will receive `question` and `answer` as parameters.
- Follows the app's established design and typography.

#### [MODIFY] [help_center_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/help_center_screen.dart)
- Expand the `faqs` list with more content (e.g., profile updates, role management, password recovery, listing deletion, notification management).
- Update `_buildFAQItem` to use a `ListTile` or custom container that navigates to `FAQDetailScreen` on tap.
- Remove `ExpansionTile` usage.

## Verification Plan

### Manual Verification
1. **Navigation**:
    - Open the Help Center.
    - Tap on an FAQ item.
    - Verify it navigates to the `FAQDetailScreen` with the correct content.
2. **Content**:
    - Verify the new FAQ items are visible.
3. **UI/UX**:
    - Ensure the transition is smooth and follows the app's navigation patterns.
