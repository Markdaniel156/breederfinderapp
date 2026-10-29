# Implementation Plan - Profile & Marker Consistency

Fix the inconsistency in profile images on the map by optimizing how marker icons are indexed, generated, and updated.

## User Review Required

> [!IMPORTANT]
> The inconsistency is likely caused by markers being indexed by `listing ID` instead of `user ID`. Since the map groups multiple listings under one user pinpoint, using the listing ID for the icon cache causes conflicts. I will change the cache to use user IDs and ensure icons are refreshed if the profile image changes.

## Proposed Changes

### Map Screen Marker Refinement

#### [MODIFY] [map_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/map_screen.dart)
- **Change Cache Key:** Change `_markerIcons` to be indexed by `userId` instead of `breeder.id`.
- **Image URL Tracking:** Keep track of the `imageUrl` used for each cached icon. If a user's image URL changes in the provider, re-generate the icon.
- **Grouping Sync:** Ensure the logic that selects which `Breeder` object represents a user on the map is identical to the logic used for marker icon lookup.
- **User Profile Sync:** Ensure the current user's moving marker (`_userMarkerIcon`) uses the same high-quality generation logic as other markers for a consistent look.

## Verification Plan

### Manual Verification
1. **Consistency Check:**
   - Log in with Account A and set a profile picture.
   - Log in with Account B and view Account A on the map.
   - Verify the profile picture is correct and high quality.
2. **Refresh Check:**
   - Change Account A's profile picture.
   - Re-open Account B's map.
   - Verify the marker icon updates to the new picture.
3. **Multiple Listings Check:**
   - Create two listings for Account A.
   - Verify only one pinpoint appears on Account B's map and it uses the correct profile picture.
