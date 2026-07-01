# Google Drive Upload Visibility

## What happened

A URL download completed and logged `resource_created source=url_download`, but the media did not appear in the expected Google Drive folder. Runtime logs did not show whether the Drive backup was attempted, skipped, completed, or failed.

## Root cause

The URL download finalization path called `GoogleDrive.upload_file_content/3`, but the Google Drive client returned `{:ok, :skipped}` silently when a chat did not have both an access token and folder ID configured. Successful uploads were also silent. As a result, `resource_created` confirmed only local/resource creation, not the Google Drive backup outcome.

## Fix applied

Google Drive uploads now log a concise outcome at the integration boundary:

- `google_drive_upload_completed` when a file upload finishes.
- `google_drive_upload_failed` with status or reason when an upload fails.
- `google_drive_upload_skipped reason=not_configured` when a chat has no complete Drive configuration.

Tests now cover successful upload logging and skipped-upload logging.

## What we learned

Optional integrations still need clear runtime visibility at the point where work is skipped or completed. Resource creation and external backup are separate outcomes, so their logs should not imply each other.
