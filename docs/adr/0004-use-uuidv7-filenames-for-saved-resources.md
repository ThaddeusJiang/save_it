# Use UUIDv7 Filenames for Saved Resources

## Context and Problem Statement

`save_it` saves downloaded media, HLS outputs, and generated video preview files to local storage and optional Google Drive uploads. Filename generation previously varied by source: ordinary URL downloads used URL-derived hashes, Cobalt tunnel downloads could keep upstream filenames, HLS downloads used another hash, and generated video covers derived names from the source video.

We need one filename policy that avoids source-specific branching while keeping file extensions meaningful for Telegram media routing, local storage, and user inspection.

## Considered Options

* Keep source-specific filename rules
* Use URL hash basenames with original extensions
* Use UUIDv7 basenames with original extensions

## Decision Outcome

Chosen option: "Use UUIDv7 basenames with original extensions", because it gives every saved resource the same naming rule, avoids leaking or depending on upstream basenames, and preserves the extension needed to decide whether a file should be handled as a photo, video, animation, or document.

### Consequences

* Good, because downloaded media, HLS outputs, and generated preview files follow one filename invariant.
* Good, because filenames no longer depend on external URLs, upstream filename quality, or provider-specific response behavior.
* Good, because preserving the original extension keeps media handling simple and visible in local files.
* Bad, because filenames are no longer deterministic from the resource URL; cache lookup must continue to rely on the existing URL-to-file mapping.
* Bad, because repeated uncached downloads of the same resource can produce different filenames.
