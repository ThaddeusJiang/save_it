# Google Drive Large File Upload Failure

## What happened

Google Drive uploads used the multipart upload endpoint for all files. This was fragile for long videos and other large files because the entire upload was sent as one request body.

## Root cause

The Google Drive client used `uploadType=multipart` and built one multipart body in memory. The file-path upload path also read the whole file before sending it and included an invalid `Content-Length: */*` header.

## Fix applied

Changed Google Drive uploads to use the resumable upload flow:

1. Create an upload session with `uploadType=resumable`.
2. Read the session `Location` response header.
3. Upload file bytes in 8 MB chunks with `Content-Range`.
4. Continue after `308 Resume Incomplete` and return the final `200` or `201` response.

Added tests for a single-chunk upload and a multi-chunk upload that receives `308` before completing.

## What we learned

Multipart uploads are only suitable for small Google Drive files in this application. Large media should use resumable upload sessions so network timeouts and process memory pressure stay bounded.
