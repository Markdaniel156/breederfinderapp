# Refine Category Tile Layout

The user wants the category animal pictures to be smaller, remove the "white covering" (excessive padding/background), and fix the internal spacing.

## Proposed Changes

### [Home Screen & Category Tiles]

#### [MODIFY] [category_tile.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/home/category_tile.dart)
*   **Reduce Padding**: Decrease the outer container padding from `12` to `8` to remove the "heavy" frame look.
*   **Small Fixed Image**: Replace the `Expanded` image container with a fixed `SizedBox` (approx `60x60`) to make the animal pictures smaller and more like thumbnails.
*   **Remove Background**: Remove the `Colors.grey[50]` / `Colors.black26` background from the image container to eliminate the "covering" effect.
*   **Tighten Spacing**: Reduce the `SizedBox` height between the category text and the image from `10` to `6`.

#### [MODIFY] [home_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart)
*   **Aspect Ratio**: Update `childAspectRatio` to around `1.2` or `1.3` in the `SliverGridDelegate` to reflect the shorter, more compact cards.

## Verification Plan

### Manual Verification
*   Check the Home screen to ensure Category pictures are small thumbnails.
*   Verify that the "white frame" around images is gone.
*   Ensure the spacing between the category name and picture is tight and consistent.
