# Historical Android integration tests

These tests describe the pre-0.10 unofficial YouTube player/search implementation.
They are preserved for historical reference, outside the active integration_test
directory. They must not be used to validate the current official-YouTube build.
Current device tests cover Facebook playback/orientation/quality, system-edge
gestures, and rejection of native YouTube extraction/playback/download access.
Run scripts/test-android.sh for the current smoke suite and
scripts/test-orientation.sh for generated local-fixture rotation stress tests.
