# Google account integration and public verification

Cloud project: `deductive-torus-513303-e2` (Diu Tup YouTube).
YouTube Data API v3 is enabled. OAuth branding, Android and Web clients have
been created. The external audience is now In production, but branding is verified and published; data-access verification is not complete. Google currently shows a lifetime cap of 100 users for unapproved sensitive scopes.
Real-device sign-in succeeded after the account owner granted consent. The
subscriptions, owned playlists and liked videos tabs each displayed real data.

## Required OAuth configuration

- External audience. Use Testing for initial setup; the current project is In production awaiting verification.
- Scope: `https://www.googleapis.com/auth/youtube.readonly`.
- Android OAuth client package: `com.duchaik.ytb`.
- Existing app signing SHA-1: `2C:D6:06:26:95:43:8F:69:C5:B5:51:76:E9:B6:EF:11:84:3C:F4:D2`.
- Web application OAuth client: its **client ID** is the Android Google Sign-In
  SDK's `serverClientId`. Do not put a client secret in the app or Git.
- The public Web client ID is compiled into `YoutubeAccountLogin.clientId` by
  default, including normal and CI builds. Override for a separate project with
  `--dart-define=YTB_GOOGLE_WEB_CLIENT_ID=THE_WEB_CLIENT_ID`. An explicitly empty
  override fails before platform login. An alternate signing certificate also
  needs its own Android OAuth client in the same Google Cloud project.
- Before public rollout, complete Google-required privacy/branding verification
  and production audience review; do not ship an untested login flow as ready.

## Implemented behavior

Settings → Tài khoản YouTube. User explicitly consents before Google authentication.
Only subscriptions, owned playlists and liked videos are read. Every API page is
retrieved; errors do not replace a successful prior snapshot with partial results.
Account data and bearer tokens are in session memory, never shared preferences,
logs or the native extraction service. Closing the page releases its data/client.
Refresh requests authorization again; disconnect clears local data immediately and
attempts to revoke consent. A Google permissions link is available if revocation
fails offline. Results open official YouTube links through the OS.

The 0.10.0 Android app removes unofficial YouTube extraction/search and native YouTube playback/downloads. Native ID/CDN/offline boundaries reject YouTube. This implementation review is not a certification or a guarantee of Google approval.

## Verification still required with configured credentials

1. Successful sign-in with the real signed APK and an allowed test account.
2. Cancel/deny permission, account without a YouTube channel, expired token.
3. Multi-page subscriptions, private owned playlists, liked videos, empty lists.
4. Switch accounts without old data appearing; disconnect during refresh and
   reconnect; offline revoke and later removal through Google permissions.
5. Official video/playlist/channel links open correctly.
6. No secrets in logs/build artifacts/repository. Keep the current signing key.

Local automated tests cover authenticated pagination, repeated-page termination,
HTTP 401/403/500 safe errors, missing client configuration, consent cancellation
and a small landscape layout. All 47 Flutter tests pass; analysis is clean. The account header also scrolls at large text sizes in a short landscape viewport.
On the S10+ (Android 12), canceling the app consent dialog and canceling Google's
account picker both return safely and permit retry. The Android package/signature
and Web client ID successfully open Google Sign-In for the allowed test account.

## Public rollout (user-approved scope, 2026-10-31)

The user requires login for every user's own account, not only test users, and
approved switching YouTube to official playback and removing YouTube downloads.
Keep Facebook's native playback, quality and orientation features. Audit and
remove the unofficial YouTube extraction/search/recommendation paths from the
shipping app before submitting verification. Do not claim that changing one link
or changing Testing to Production by itself constitutes policy approval.

The user chose a separate site instead of changing `hdgame.io.vn`. GitHub Pages
serves `main:/docs` at https://diutup.duckdns.org/ with HTTPS:

- Homepage: https://diutup.duckdns.org/
- Privacy: https://diutup.duckdns.org/privacy.html
- Terms: https://diutup.duckdns.org/terms.html
- Authorized domain: `diutup.duckdns.org`.
- DuckDNS `diutup.duckdns.org` registered in the owner's GitHub-linked account.
  The domain points to GitHub Pages at `185.199.108.153`. Search Console **Domain
  property** verified using DNS TXT. Keep the Google verification TXT in DuckDNS;
  do not replace it with dynamic DNS/ACME automation. The older GitHub URL-prefix
  HTML verification alone was insufficient for OAuth domain review.
- Never put the DuckDNS account token into the app, Git, logs or public artifacts.
- Google branding URLs/domain saved. Data Access declares `openid`,
  `userinfo.email`, `userinfo.profile` and `youtube.readonly`; no write scopes.
- Audience switched to In production. This does not remove the unverified warning
  or the 100-user cap for unapproved sensitive scopes.

Google has verified branding for `diutup.duckdns.org`; branding has been published.
The sensitive YouTube scope still requires data-access verification. Prepare an accurate end-to-end consent/feature demo,
justify readonly use, and submit the required review. Any policy attestation must
be reviewed by the owner. Approval and timing are Google's decision.

Scope justification draft: Diu Túp lets each signed-in user view their own YouTube
subscriptions, owned playlists (including private playlists), and liked videos.
It calls subscriptions.list(mine=true), playlists.list(mine=true), and
videos.list(myRating=like), retrieving all pages. Public unauthenticated data
cannot provide these account-specific lists. youtube.readonly is the least
privileged scope that covers these reads. No data is modified. Selecting an item
opens the official YouTube app/website; there is no native YouTube extraction,
YouTube download, or offline YouTube playback. Account data/tokens remain in
session memory, are not sent to our own server or Facebook, and are cleared when
the account page closes, the user changes accounts, or disconnects. Disconnect
also requests Google authorization revocation. Google Play Services independently
manages sign-in state.
