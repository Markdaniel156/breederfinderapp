# Implementation Plan - UI Polish & Layout Refinement

This plan aims to professionalize the Home Screen UI, specifically refining the header greeting, relocating the map icon for better accessibility, and optimizing the categories grid spacing.

## User Review Required

> [!IMPORTANT]
> - The map icon will be moved from the top navigation row to directly beside the user's greeting (e.g., "Good Afternoon Mark! 📍").
> - The greeting format will be updated to "Good [Time] [Name]!".
> - Spacing in the categories grid will be tightened to reduce white space and improve information density.

## Proposed Changes

### [Component] Home Header Refinement

#### [MODIFY] [home_header.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/widgets/home/home_header.dart)
- Remove the map icon from the top action row.
- Combine the time greeting and the user's name into a single line: `Good [Time] [Name]!`.
- Place a subtle Map Icon Button directly to the right of the greeting text.
- Adjust vertical padding for a more compact and professional look.

### [Component] Categories Grid Optimization

#### [MODIFY] [home_screen.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/screens/home_screen.dart)
- Reduce `mainAxisSpacing` (from 16 to 12) and `crossAxisSpacing` (from 12 to 8) in the `_buildCategoriesSection` grid.
- Slightly adjust `childAspectRatio` (from 0.52 to 0.54) to keep the tiles compact but readable.
- Reduce the top padding of the Categories section for a tighter layout.

### [Component] General Polish

#### [MODIFY] [listing_item.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/widgets/home/listing_item.dart)
- Refine card shadows and border colors for a more premium feel.
- Improve typography contrast for price and animal names.

## Verification Plan

### Manual Verification
- Verify the greeting displays correctly as "Good Afternoon Mark!" (or current time/name).
- Verify the map icon is clickable and triggers the map view.
- Ensure the categories grid looks balanced and doesn't have excess white space.
- Check for any layout overflows on different screen sizes.
