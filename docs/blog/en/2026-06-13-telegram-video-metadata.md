# The MP4 Metadata Bug Hiding Behind a Telegram Bot Upload

2026-06-13

Some bugs are valuable not because the patch is large, but because they expose a boundary we had been treating as simpler than it really was.

This one started with a strange symptom in save_it: a video downloaded by the bot and sent to Telegram would sometimes appear with the wrong aspect ratio. The original file was fine. If the same file was downloaded manually and uploaded through a Telegram client, it displayed correctly. Large videos also did not always behave like streamable Telegram videos; they were less likely to start loading automatically.

The obvious question was: is this a Telegram Bot API limitation, or an ex_gram limitation?

The answer turned out to be: partly yes, but not in the way that first appeared.

## The misleading part

When the original file displays correctly and a manual Telegram upload displays correctly, it is tempting to assume the bot API is damaging the video. But the upload path matters.

A Telegram client can inspect and prepare a video before upload. A bot upload is much more explicit: the bot sends a file and a set of parameters, and Telegram makes a decision from those inputs. ex_gram is mostly a wrapper around that API. If we do not provide width, height, duration, or a stream-friendly MP4 structure, ex_gram will not invent that information for us.

The issue was not that ex_gram sent correct metadata incorrectly. The issue was that save_it was not sending enough metadata in the first place.

## `supports_streaming` is necessary, not sufficient

Telegram Bot API's `sendVideo` method supports video `duration`, `width`, `height`, and `supports_streaming`. The same official documentation says regular Bot API video uploads are currently limited to 50 MB. If you switch to a Local Bot API Server, uploads can go up to 2000 MB.

That explains two separate things:

- Large videos really do run into a Bot API boundary when using the normal hosted API.
- `supports_streaming: true` is only a signal that the uploaded video is suitable for streaming. It does not guarantee every Telegram client will eagerly load every uploaded MP4.

Streaming behavior also depends on the MP4 container itself. An MP4 can be perfectly playable while still being poorly arranged for progressive playback. If the `moov` atom is near the end of the file, a client may need more of the file before it can start playback. For bot uploads, it is safer to prepare the file as faststart-compatible before sending it.

## Aspect ratio is display metadata, not just pixels

The aspect ratio bug came from another subtle media detail: encoded dimensions and display dimensions are not always the same thing.

Phone videos are a common example. A vertical video may be encoded with one width and height, then carry rotation metadata that tells players how to display it. A local player reads that metadata and shows the video correctly. A Telegram client upload may also normalize or preserve that display intent during upload.

But if the bot sends only the raw file and `supports_streaming: true`, Telegram may infer dimensions from the upload differently. For videos with rotation metadata, that can produce a wrong display ratio.

The fix was to stop making Telegram guess. save_it now reads the video metadata itself and sends explicit display dimensions to `sendVideo`.

## The fix

The upload path now has a small preparation step for MP4 files.

First, save_it tries to remux the video without re-encoding:

```sh
ffmpeg -c copy -movflags +faststart
```

This keeps the media streams intact while making the MP4 container friendlier for progressive playback. It avoids the cost and risk of transcoding: no quality loss, no codec decisions, no long CPU-heavy conversion step.

Second, save_it probes the video with `ffprobe` and extracts:

- width
- height
- duration
- rotation metadata

If the rotation is 90 or 270 degrees, the code swaps width and height to get the display dimensions rather than the raw encoded dimensions.

Then `sendVideo` receives the important values explicitly:

```elixir
[
  supports_streaming: true,
  width: display_width,
  height: display_height,
  duration: duration
]
```

The fallback behavior matters just as much as the happy path:

- If faststart remuxing succeeds but probing fails, save_it still sends the prepared video without dimensions.
- If remuxing fails, save_it falls back to the original file and still tries to probe it.
- If both ffmpeg and ffprobe fail, the bot sends the original file using the previous behavior.

That keeps the user experience resilient. A media metadata failure should not prevent the user from receiving the video.

## Why this issue was worth fixing

The valuable lesson is that the Telegram Bot API is not the Telegram client.

When a user manually uploads a video, the client may do hidden work: inspect metadata, normalize the container, preserve rotation, or prepare the upload in a way Telegram understands well. A bot does not automatically get all of that. If we want reliable media behavior, the bot needs to be explicit.

The save_it video flow is now clearer:

1. Download the MP4.
2. Try to make it faststart-friendly.
3. Read display dimensions and duration.
4. Send those values to Telegram.
5. Fall back gracefully if media preparation fails.

This separates three concerns that were previously blurred together:

- API limits, such as the regular Bot API's 50 MB upload limit.
- Container structure, such as whether the MP4 is suitable for progressive playback.
- Display metadata, such as rotation and the difference between encoded dimensions and display dimensions.

Once those concerns were separated, the fix became straightforward.

## Reusable takeaways

If you send videos through the Telegram Bot API, these are the rules I would keep:

- Design regular Bot API uploads around the 50 MB limit.
- Consider a Local Bot API Server if larger uploads are a real product requirement.
- Pass `supports_streaming`, but do not treat it as an autoplay guarantee.
- Make MP4 uploads faststart-friendly when possible.
- Read display dimensions, not just encoded dimensions.
- Pass width, height, and duration explicitly when the API supports them.
- Treat media preparation as best-effort; failing to optimize should not fail the whole user request.

The final patch was not about finding a magic Telegram parameter. It was about respecting the difference between “this file can be played” and “this file has been prepared and described well enough for a bot upload pipeline.”

That distinction is easy to miss. It is also exactly where many useful engineering fixes live.

## References

- [Telegram Bot API: sendVideo](https://core.telegram.org/bots/api#sendvideo)
- [Telegram Bot API: Using a Local Bot API Server](https://core.telegram.org/bots/api#using-a-local-bot-api-server)
