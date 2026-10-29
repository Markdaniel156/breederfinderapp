# Fix Notification Recording for Arrivals

The user is reporting that arrivals are not being "recorded" for them on the notification screen. This is likely due to filters in the `NotificationProvider` that skip "on_the_way" status arrivals and only show arrivals where the user is the Host. Additionally, the real-time listener has a strict 30-second window which might cause arrivals to be missed if there is any clock skew.

## Proposed Changes

### [Notification]

#### [MODIFY] [notification_provider.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/providers/notification_provider.dart)
- Update `fetchNotifications` to fetch arrivals where the current user is either the **Host** or the **Visitor**.
- Remove the explicit `continue` for `on_the_way` status.
- Map `on_the_way` status to `NotificationType.onTheWay`.
- Adjust notification messages based on whether the user is the Host or the Visitor.
- Update `_initArrivalListener` to remove the `on_the_way` filter and use `NotificationType.onTheWay` when appropriate.
- Increase the real-time "freshness" window from 30 seconds to 2 minutes to be more robust.

#### [MODIFY] [notification_screen.dart](file:///C:/Users/Acer/StudioProjects/breederfinderapp/lib/screens/notification_screen.dart)
- Update the tap handler for `NotificationType.arrival` and `NotificationType.onTheWay` to handle cases where the user is the visitor (tapping should take them to the Host's profile instead of their own).

## Verification Plan

### Automated Tests
- I will check the build for any syntax errors in the modified files.

### Manual Verification
1. **Host Perspective:**
   - Simulate an arrival (via `map_screen.dart` or direct DB insert).
   - Verify that "New Visitor Arrived!" or "Visitor is on the way" appears in the notification list.
2. **Visitor Perspective:**
   - Simulate an arrival as the current user.
   - Verify that "Arrival Recorded" appears in the notification list.
3. **Navigation:**
   - Tap on an arrival notification and ensure it navigates to the correct profile (Host's profile if user is visitor, Visitor's profile if user is host).
