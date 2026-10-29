# Implement "Report User" Feature

Add a reporting mechanism to allow users to report scammers, fake listings, animal welfare concerns, etc. The report will include a reason, description, and optional evidence (images).

## User Review Required

> [!IMPORTANT]
> A new `reports` table and a `report-evidence` storage bucket must be created in Supabase for this feature to work correctly.
> **SQL for reports table:**
> ```sql
> create table reports (
>   id uuid default uuid_generate_v4() primary key,
>   reporter_id uuid references auth.users not null,
>   reported_user_id uuid references auth.users not null,
>   listing_id uuid, -- optional, if reporting a specific listing
>   reason text not null,
>   description text not null,
>   evidence_urls text[] default '{}',
>   created_at timestamp with time zone default timezone('utc'::text, now()) not null
> );
> ```

## Proposed Changes

### Models

#### [NEW] [report.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/models/report.dart)
Define the `Report` data model.

### Providers

#### [NEW] [report_provider.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/providers/report_provider.dart)
Handle report submission and image uploads to Supabase.

### Screens

#### [NEW] [report_user_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/report_user_screen.dart)
The reporting form with reason selection, description text field, and image upload for evidence.

#### [MODIFY] [main.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/main.dart)
Register `ReportProvider` in the `MultiProvider` block.

#### [MODIFY] [market_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/market_screen.dart)
Add a "Report User" button in the animal details modal.

#### [MODIFY] [favorites_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/favorites_screen.dart)
Add a "Report User" button in the post details modal.

#### [MODIFY] [home_screen.dart](file:///C:/Users/Acer/StudioProjects/BreederFinderApp/lib/screens/home_screen.dart)
Add a "Report User" button in the trader/breeder details modals.

## Verification Plan

### Manual Verification
- Navigate to a listing in `AniMarket`.
- Open the listing details.
- Tap the "Report User" button (newly added).
- Select a reason (e.g., "Scam or Fraud").
- Enter a description.
- Upload at least one screenshot as evidence.
- Submit the report.
- Verify that a success message is shown and the user is navigated back.
- Repeat the process from `Favorites` and `Home` screens.
