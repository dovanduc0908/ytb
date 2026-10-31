# Video quality and rotation — 0.9.0 (17)

Test device: Samsung Galaxy S10+ SM-G975U1, Android 12. Date: 2026-10-31.

## Changes

Facebook parsing now retains compatible video-only formats with separate audio instead of selecting the first muxed SD URL. Unknown dimensions stay unknown in labels. Format ID, dimensions, frame rate and bitrate are retained; DRM and unsupported codecs are excluded. Public links are canonicalized for history/queue and hashed for offline filenames.

Auto starts at the highest compatible source on Wi-Fi. Cellular prefers the highest available height <=480; if none exists, it uses the lowest available source. A default-network change resets manual quality to Auto while preserving playback position and play/pause. Buffer-based recovery remains possible when bitrate metadata is missing. Adaptive manifests also receive a cellular height cap.

Fullscreen enters landscape explicitly, with portrait/landscape/follow-video selection and a shared lock state. Size events cannot overwrite a manual choice. PlayerView transfers its existing player to the new surface; disposing the old view cannot clear the new target. PiP uses the actual video aspect ratio within Android limits.

Enhancement is optional: Off/Auto/Strong. Bounded sharpening and Lanczos upscaling run on the GPU, capped at 1080p output for this implementation. HDR, severe thermal state, frame drops and frame processor failures disable enhancement. This is not AI super-resolution and does not recover missing original detail.

A failed source refreshes once per load, fenced by media ID/generation and user actions. Offline supports progressive separate A/V and muxed video; segmented HLS downloads are intentionally unavailable. TV resolves provider-aware IDs; unsupported remote commands report an error instead of controlling the phone by mistake. Speed controls consistently support .25–4x.

## Automated and physical evidence

- Flutter static analysis: no issues. Flutter tests: 32 passed.
- Kotlin unit tests: 15 passed. They include Facebook separate A/V selection, HD fallback without fake metadata, media identity/URL validation, cellular cap and unknown-bitrate fallback.
- 100/100 physical rotation/surface cycles passed. Alternating portrait/landscape fixtures arrive before/after fullscreen. Every fifth cycle checks lock and explicit portrait/landscape. Assertions cover actual Activity orientation, native surface dimensions, first rendered frame, position preservation and clean Flutter layout.
- 20/20 actual watch-UI fullscreen cycles passed using `https://web.facebook.com/reel/28955594210740984`, with explicit portrait/landscape and Back transitions.
- The Facebook sample exposes heights 358, 538, 720, 1078. Wi-Fi selected 1876×1078 with AAC audio. The sample has no exact 480p source.
- Real Wi-Fi → SIM → Wi-Fi passed: 1078 → 358 → 1078. Manual quality was reset to Auto, position advanced from 31.96s to 38.012s. Original Wi-Fi/mobile-data settings were restored.
- Intentionally invalid CDN video URL recovered to the real source at 30.052s, preserving the requested 30s position and audio.
- Five-minute Strong enhancement run on the sample: position .919s → 303.416s; decoder rendered counter 87 → 7125; dropped counter stayed 0; no player error. This was a debug integration build, not a cross-device performance guarantee.
- Short generated-pattern tests passed for Off/Auto/Strong with 0 video frame drops.
- Full UI run found and fixed a 13px overflow in feed cards when dimensions changed.

Raw local evidence is under `/tmp/ytb-qa-20261031`; device tests are committed in `apps/native/integration_test/`. Reproduce fixture stress with `FFMPEG=/path/to/ffmpeg bash scripts/test-orientation.sh SERIAL`. Network test requires coordinated Wi-Fi/SIM switching and restoring the original settings.

## Release and limitations

Version 0.9.0+17 uses the same application ID and signing certificate as installed release 15. Certificate SHA-256: `4c42a9458fca6fb22bb0e3c389c0e02d4e736cdb80223fcd70870cc530a8258e`. Release asset must be the single `Diu-Tup.apk` on tag `build-17` so the existing in-app updater can discover and validate it.

CI runs Flutter analysis/tests and Kotlin tests before signing. With no signing secrets configured it performs checks and explicitly skips publication; it never generates a replacement signing key. When signing is configured, publishing compares the APK certificate to the previous release and uses the build number in pubspec.

Coverage is one physical phone. Android TV changes are compile-checked, not certified on a physical TV. No claim that intermittent faults are mathematically impossible on all devices. Facebook availability and source quality depend on the public formats it serves. AI reconstruction, frame interpolation and offline adaptive-manifest packaging are not included.

Release APK SHA-256: `2c54e75e8fe2b90e41f9462685da2608c5d4803c9eac193516fd7700d9e4bf57`.
