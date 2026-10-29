# Square Map Button & Advanced Search Filters

This plan aims to refine the "MAP" button's shape and implement an advanced filtering system for the Home Screen search.

## User Review Required

> [!IMPORTANT]
> I will be adding new state variables to `HomeScreen` to track advanced filters: `_selectedAnimal`, `_selectedBreed`, and `_selectedLocation`.

## Proposed Changes

### [Component] Home UI Refinement

#### [MODIFY] [home_header.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/home/home_header.dart)
- Update the "MAP" button decoration:
    - Change `borderRadius` from `12` to `8` (or even `4` for a sharper square look).
    - Adjust `padding` from `(14, 8)` to `(10, 10)` to make it more square in shape.
    - Change `Row` to `Column` or just center the content to fit the square better.
    - *Decision*: I will keep it as a slightly rounded square (radius 8) with balanced padding for a modern aesthetic.

#### [MODIFY] [home_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart)
- **Advanced Filtering State**:
    - Add `String? _filterAnimal`, `String? _filterBreed`, `String? _filterLocation`.
- **Filter UI**:
    - Implement `_showFilterBottomSheet(bool isDark)` triggered by the `tune_rounded` icon in the search bar.
    - Add clear/apply logic for filters.
- **Search Bar Update**:
    - Make the filter icon clickable to open the bottom sheet.
- **Filtering Logic**:
    - Update `_buildContent` (specifically `allListings` filtering) to include the new criteria.

## Verification Plan

### Manual Verification
- Verify the "MAP" button looks square and aesthetic.
- Open the filter bottom sheet and select an animal/breed/location.
- Apply the filter and verify the feed updates correctly.
- Clear the filters and verify all listings return.
