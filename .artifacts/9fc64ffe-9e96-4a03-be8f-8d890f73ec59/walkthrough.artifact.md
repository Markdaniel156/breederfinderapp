# Square Map Button & Advanced Search Filters

I have redesigned the "MAP" button to be square and implemented a comprehensive filtering system for the search bar.

## Changes Made

### 1. Square Map Button in [home_header.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/home/home_header.dart)
- **Compact Square Design**: Replaced the wide rectangular "MAP" button with a symmetrical `40x40` square button.
- **Icon Centering**: Centered the map icon within the new square container and removed the text label to match the modern "Good morning" header style.
- **Formal Corners**: Updated the border radius to `10px` for a sharp yet balanced professional look.

### 2. Advanced Search Filters in [home_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart)
- **Advanced State Management**: Added persistent state for `Animal Category`, `Breed`, and `Location` filters.
- **Filter Bottom Sheet**:
    - Implemented a premium bottom sheet triggered by the "tune" icon in the search bar.
    - **Dynamic Categories**: Automatically populates the animal category list from available listings.
    - **Text Filters**: Added text input fields for specific Breeds and Locations.
    - **Visual Feedback**: The filter icon highlights in green when any advanced filter is active.
- **Updated Filtering Engine**: Refined the `_buildContent` logic to combine the main search query with these new advanced criteria.

## Verification Results

- [x] The MAP button is now a neat square beside the user's name.
- [x] Clicking the filter icon opens the "Search Filters" sheet.
- [x] Filtering by a specific animal (e.g., Dog) updates the feed correctly.
- [x] "Clear All" functionality in the filter sheet resets all advanced criteria.
