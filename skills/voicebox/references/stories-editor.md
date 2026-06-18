# Stories Editor

Multi-track timeline for composing audio with multiple voice profiles.

## Use Cases

- Podcasts with multiple hosts
- Audiobook narration with character voices
- Game dialogue scenes
- Explainer videos with narrator + character tracks

## Getting Started

Stories tab → + New Story

Each story has:
- **Tracks** — one per voice/character
- **Clips** — audio segments on a track
- **Timeline** — scrubable playback with per-track volume

## Creating Tracks

+ Add Track → name the track → assign a voice profile.

Track inherits the profile's voice for all clips. Switch profile at any time — existing clips re-render on next export.

## Adding Clips

Two methods:

1. **Generate in-place:** click on timeline → type text → Generate. Clip placed at click position with track's assigned profile.
2. **Drag existing audio:** drag .wav or .mp3 from file manager onto the track.

Click a clip to: edit text, regenerate, trim start/end, adjust volume.

## Editing the Timeline

- Drag clips left/right to adjust timing
- Overlap clips for crossfade (linear, -3dB)
- Trim handles on clip edges
- Scrub playhead to preview any point

## Rendering

Stories → Render → choose .wav or .mp3.

Mixes all tracks at timeline positions into a single stereo file. All local, no upload.

## Current Limits

- Max tracks: 16
- Max story length: 60 minutes
- No automation lanes (volume/pan over time) yet
- No MIDI or tempo sync

## Planned

- Per-clip effects chain
- Automation lanes
- Stem exports (one file per track)
- XML/DAW project export
