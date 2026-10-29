# Add Images to Promo Banners

This plan outlines the steps to add image support to each promo banner slide in `PromoBanner.dart`.

## User Review Required

> [!IMPORTANT]
> You will need to add the actual image files to your `assets/` folder and register them in `pubspec.yaml` for this to work. I will use placeholder asset paths in the code.

## Proposed Changes

### UI Components

#### [MODIFY] [promo_banner.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/widgets/home/promo_banner.dart)
- Update the `slides` list to include an `imagePath` for each slide.
- Modify the `itemBuilder` to display the image, typically as a `Positioned` element or a background image.

## Verification Plan

### Manual Verification
- Deploy the app and verify that the images appear in the promo banner slides.
- Check that the auto-scroll and manual swipe still work correctly.
