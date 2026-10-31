# Google / official YouTube migration QA — 0.10.0+19

Date: 2026-10-31. Device: Samsung Galaxy S10+, Android 12.

## Completed

- Flutter analysis: no issues. Flutter unit/widget suite: 47 passing tests.
- Native JVM suite: 13 tests, zero failures/errors (playback policy, reliability,
  and captions/chapter parsing).
- Device integration: native resolve/resolveFull/search/related/charts reject
  unofficial YouTube calls with OFFICIAL_YOUTUBE. Player rejects YouTube IDs,
  Google CDN streams mislabeled as Facebook, and offline YouTube access with
  specific expected errors. The test waits for the real service before asserting.
- Device orientation reliability: 100 cycles across landscape/portrait fixtures,
  playback/surface handoff and enhancement modes, passing. Fixtures use local
  media with Facebook IDs, so this test isolates playback/orientation from network.
- Google sign-in with the correctly signed package and actual user consent:
  subscriptions, owned playlists and liked videos each displayed real data.
- Cancel app disclosure and cancel Google account picker: clean return and retry.
- API tests: authenticated pagination, repeated-token protection, safe 401/403/500
  handling, missing configuration. Official URL routing does not open untrusted
  destinations; unknown input is an encoded official YouTube search query.
- Account layout: short landscape viewport, scrollable consent, large text.
- Public homepage/privacy/terms deployed to HTTPS GitHub Pages; Search Console
  Domain-property ownership verified using DuckDNS TXT; branding URLs and authorized domain saved in Google Cloud. HTTPS certificate issued; HTTPS enforcement enabled; the custom-domain homepage loads successfully.

- Signed release smoke test: supplied Facebook reel resolves and plays at Auto
  1078p on Wi-Fi. Version 0.10.0 / code 19 is installed without clearing app data.
- Google refresh: transitions through busy state then enables controls again with
  no error; the connected account remains displayed.
- Official YouTube routing opens `com.google.android.youtube` on the real device.
- Account switch cancellation on the Google picker: returns to a logged-out page,
  clears the previous account, and displays “Đã hủy đăng nhập.”

- Final Facebook UI integration: all 20 full-screen cycles passed, including
  explicit portrait/landscape switches and Back. The initial Wi-Fi source is
  the highest compatible available quality. Strong enhancement ran for five
  minutes; final diagnostics reported 7,120 rendered frames and zero dropped
  frames, with no playback error. This is one S10+ run, not a guarantee for every
  device, temperature, source or network.
- Historical pre-0.10 YouTube tests are archived outside integration_test. The
  device smoke runner now selects the supported tests and restores the normal
  app on exit, including failures.

- Branding for diutup.duckdns.org is verified and published.

## Remaining manual checks / external prerequisites
- Capture an accurate final consent/feature demonstration for Google review.
- Complete sensitive-scope verification. Production status alone
  does not constitute approval or remove Google's unverified-user cap.
- An account with no YouTube channel, a second independent account, offline revoke,
  and actual expired-token renewal have not all been exercised on real devices;
  automated error handling/generation fencing do not replace these checks.

Do not publish private account lists, tokens, raw consent captures or keystores in
QA artifacts. Prior fixes and limits are recorded in VIDEO_QUALITY_0.9_QA.md.
