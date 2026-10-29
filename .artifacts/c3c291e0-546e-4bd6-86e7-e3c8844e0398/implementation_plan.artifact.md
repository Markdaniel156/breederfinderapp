# Implementation Plan - Arrival Geofencing Enhancements

The goal is to increase the arrival geofencing radius to 200 meters and add a way for users to cancel an active arrival tracking session.

## User Review Required

> [!NOTE]
> The arrival threshold and map circle will both be updated to 200 meters. A "Cancel Arrival" button will be added to the breeder details view.

## Proposed Changes

### Geofencing Service

#### [MODIFY] [geofencing_service.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/services/geofencing_service.dart)

- Update the distance threshold in `monitorGeofences` from `100` to `200` meters for arrival notifications.

### Map Screen

#### [MODIFY] [map_screen.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/screens/map_screen.dart)

- Update `_getUserArrivalCircle` to use a `radius` of `200`.
- In `_showBreederDetails` bottom sheet:
    - Check if the `breeder.id` matches `widget.geofenceService?.activeTargetId`.
    - If it matches, show a "Cancel Arrival" button instead of the "Arrive here" button.
    - The "Cancel Arrival" button will call `setActiveTarget(null)` and trigger a UI refresh via `setState`.

## Verification Plan

### Manual Verification
1. **Radius Check**: Tap "Arrive here" and verify the green circle on the map is now twice as large (200m radius).
2. **Cancel Button**:
    - Tap "Arrive here" for a breeder.
    - Re-open that breeder's details.
    - Verify the button now says "Cancel Arrival".
    - Tap "Cancel Arrival".
    - Verify the green circle disappears from the map.
3. **Trigger Check**: (If testing on device/emulator with location simulation) Verify that arrival notifications now trigger when entering the 200m zone.
