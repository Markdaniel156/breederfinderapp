# Categories Section Redesign

I have redesigned the Categories section to match the "Latest Feed" aesthetics and provide a more "formal" post-like experience.

## Changes Made

### Home Screen (Layout Sync)
- **Header Spacing**: Updated the `Categories` section top padding to `26px` in [home_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart), matching the `Latest Feed` header.
- **2-Column Grid**: Changed the grid from 4 columns to 2 columns. This allows each category to have more presence on the screen, similar to the post cards in the feed.
- **Increased Spacing**: Set `mainAxisSpacing` and `crossAxisSpacing` to `16px` to match the breathing room between feed items.

### Category Tile (Visual Refinement)
- **Reordered Elements**: Swapped the layout in [category_tile.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/home/category_tile.dart) so the **Category Name** and **Item Count** appear at the top, followed by the animal image.
- **Formal Card Styling**:
    - Added a background color (White/Dark green) and card-like border radius (`22px`).
    - Applied shadows and borders that match the `ListingItem` (post) style.
    - Included a count bubble for a more polished, "formal" look.
    - Used high-quality animal images as the focal point of the card.

## Verification
- [x] Categories section header is perfectly aligned with the Feed section header.
- [x] Tiles now look like professional "post" cards rather than simple icons.
- [x] Text hierarchy correctly places the name above the image.
