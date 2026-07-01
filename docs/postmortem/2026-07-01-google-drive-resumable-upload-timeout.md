# Google Drive Resumable Upload Timeout

## What happened

Google Drive backups could log a `:timeout` error while the file still appeared in the configured Drive folder. The bot uploaded media with a single multipart request, so large files could finish on Drive while the client timed out waiting for the final response.

## Root cause

The Google Drive client used `uploadType=multipart` for every upload. Google Drive documents multipart uploads as a small-file option, while large or interruption-prone uploads should use resumable sessions. Because the app sent metadata and the full media body in one request, a slow large upload had no reliable way to ask Drive whether the timed-out request had actually completed.

## Fix applied

Google Drive uploads now create a resumable upload session with `uploadType=resumable`, then upload media in 8 MB chunks using `Content-Range`. The client continues after `308 Resume Incomplete` and treats final `200` or `201` responses as success. If a chunk request times out, the client queries the same session with an empty status request and resumes from Drive's reported byte range or returns success when Drive reports the file is complete.

## What we learned

Timeout handling needs to match the remote API's upload protocol. For Drive media backups, reducing each request to bounded chunks is only half the fix; the important correctness property is preserving the resumable session so a lost response can be reconciled instead of reported as a failed upload.
