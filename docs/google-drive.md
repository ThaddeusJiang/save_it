# Google Drive Guide

SaveIt can optionally upload downloaded files to Google Drive after Telegram delivery starts. Telegram and Google Drive delivery run independently, so one channel can fail without blocking the other.

## Self-Hosting Configuration

Google Drive upload is optional. To enable it for a self-hosted bot, configure these environment variables:

```sh
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
```

The bot uses Google's OAuth 2.0 device flow and requests the Drive `drive.file` scope. The OAuth app must allow the device flow and have access to the Google Drive API.

Keep the regular bot configuration as well:

```sh
TELEGRAM_BOT_TOKEN=
COBALT_API_URL=
TYPESENSE_URL=
TYPESENSE_API_KEY=
```

`COBALT_API_URL`, `TYPESENSE_URL`, and `TYPESENSE_API_KEY` have local defaults, but production deployments should set them explicitly.

## Google Cloud Setup

1. Open Google Cloud Console.
2. Create or select a project for the bot.
3. Enable the Google Drive API for that project.
4. Configure the OAuth consent screen.
5. Create an OAuth client that supports device authorization.
6. Copy the client ID and client secret into `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`.
7. Restart the bot after changing environment variables.

If the OAuth app is in testing mode, add the Google accounts that will use the bot as test users.

## Telegram Setup

Google login and folder selection are configured from Telegram.

### 1. Log In To Google

In a private chat, group, or supergroup where you are an administrator, run:

```text
/code
```

The bot replies with a verification URL and a user code. Open the URL in a browser, enter the code, and approve access with the Google account that should own the uploaded files.

After approving access, run:

```text
/login
```

The bot stores the Google access token for that Telegram chat.

### 2. Configure The Google Drive Folder

Open Google Drive in a browser, navigate to the target folder, and copy the folder ID from the URL.

For a folder URL like:

```text
https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOpQrStUvWxYz
```

the folder ID is:

```text
1AbCdEfGhIjKlMnOpQrStUvWxYz
```

Send the folder ID to the bot:

```text
/folder 1AbCdEfGhIjKlMnOpQrStUvWxYz
```

The bot stores the folder ID for that Telegram chat.

## Runtime Behavior

- If the chat has no Google login, Google Drive upload is skipped silently.
- If the chat is logged in but Google Drive upload fails, the existing progress message is updated with `Send to google drive failed, <reason>`.
- If Telegram delivery fails, the existing progress message is updated with `Send to telegram failed, <reason>`.
- The original user message is deleted only after Telegram delivery succeeds.
- Google Drive failure does not undo or block a successful Telegram delivery.

## Troubleshooting

- `Failed to get device code`: check `GOOGLE_OAUTH_CLIENT_ID`, the OAuth client type, and whether the Google Drive API is enabled.
- `/login` fails after approval: run `/code` again and complete the browser flow before running `/login`.
- `Send to google drive failed, ...`: verify the folder ID, the Google account permissions, and whether the OAuth app is allowed for that user.
- Files appear in Telegram but not Drive: confirm that the chat has completed both `/login` and `/folder <folder_id>`.
