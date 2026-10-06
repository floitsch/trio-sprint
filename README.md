# Trio Sprint

**[Play in the browser](https://trio-sprint.floitsch.workers.dev/)** ·
**[Download for Android](https://github.com/floitsch/trio-sprint/releases/latest/download/trio-sprint.apk)**

A Flutter pattern game: find **five sets** with a two-second countdown before
cards appear and the stopwatch starts. Start with 12 cards; each found set is
replaced by three cards while the other nine stay in place. Abandon returns to
the start screen during either the countdown or play, without restoring seed
eligibility.

The board fits all 12 portrait cards to the available width and height, including
short phone viewports. Compact run controls leave more room for cards; landscape
places the controls beside the board.

For every feature — number, shape, color, fill — the three cards must be all the
same or all different. Wrong trios count as mistakes while the clock continues.
Leaving the app does not pause the stopwatch.

- **Timed runs:** choose **1 min** or **3 min** on the start screen to find as
  many sets as you can before time runs out. Boards keep evolving the same way.
  More sets rank higher; ties go to the earlier last set. Runs without a set
  cannot be submitted. Timed seeds start with `1m-` or `3m-`, so each seed
  belongs to exactly one mode, with its own high scores and personal best. They
  deal by the `s2` rules from a different starting state, so the same digits
  in another mode reveal nothing.

- **Seeds:** every sprint uses a versioned seed, such as `s2-1234abcd`. Share a
  link or paste a seed/link into **Run a seed**. A seed fixes the starting board
  and deck for the entire five-set run. The sets
  you choose affect later boards; replaying the same choices reproduces the run.
  Dealing follows board positions, not tap order. If no set remains, only newly
  dealt positions are changed until the board is solvable. Seed algorithm
  versions are
  permanent; changing the algorithm requires a new prefix. Old `s1` links retain
  their original five-board rules. Their scores are accessible by seed, separate
  from the current leaderboard and personal best. **Restart** starts a fresh
  seed; **Replay seed (practice)** repeats the same one.
- **High scores:** fastest 100 runs (or most sets for timed runs), across
  current seeds of a mode or for one seed. Toggle
  **Only each player’s best** to hide additional runs from the same player ID.
  Tap a score to play its seed or copy its link. Set or change your nickname
  at the top of the high scores; a new name applies to future scores.
  Deployments preserve the D1 database and its existing scores.
  Nicknames and random player IDs are remembered on each device, without login.
  First-attempt personal bests also persist locally.
- **Link devices:** open **Link devices** on your computer and scan its QR code
  with your phone, then tap **Link this device**. Or type the six-character code
  into **Link devices** on the other machine; no cross-device clipboard needed.
  Pairing links open the linking screen with the code already filled in.
  Codes stay the same between visits, and old long codes still work.
  Their existing and future scores
  then count as one player, including for **Only each player’s best**. You can
  link more devices using any already-linked device's code. Original score rows
  are preserved; if both devices submitted a seed, the earliest submission counts.
  Personal bests, nicknames, seed-attempt history and training history stay local.
  This uses the same honor system as scores and does not require a login.
- **First attempts only:** starting a seed consumes its eligibility, including
  abandoned runs and countdown restarts. Replays are practice. Browser Web Locks
  serialize claims across tabs, and local storage remembers them across visits.
  Android uses persistent preferences. Storage failures make runs practice-only.
  Runs of freshly generated seeds are first attempts by construction. For any
  other seed (typed, linked or from the high scores) that this device has not
  started yet, the app asks before the countdown whether it is the player's
  first time, including on other devices. Finished first attempts upload
  automatically once a nickname is set; otherwise the results ask for one.
  The server validates all solutions and allows only one score per player
  (including linked devices) and seed; retries of the same submission are safe. This is an honor system:
  clearing site data or switching devices creates a new identity, and submitted
  solo times are trusted. Identical nicknames do not merge different identities.
- **Training:** choose 1–4 different features, then find sets on full boards or
  complete pairs. Correct answers automatically bring fresh cards until you
  quit. Portrait cards fit the available screen; hints and skipping are available.
  **Cards I was slow on** revisits the 20 hardest of your last 100 saved boards
  from sprints, races and training. Ranking uses active viewing time, plus five
  seconds per mistake and 15 seconds for a hint or skip. Repeated boards keep
  the latest attempt. History stays on this device and works offline; time in
  the background does not affect this practice ranking or pause a sprint score.
- **1 vs 1:** share a room link/code, ready up, and race to find five sets
  from the same starting board and seeded deck. Each player keeps their own
  evolving board; reconnecting on the same device restores their exact choices.
  A Cloudflare room validates claims and chooses the winner. Leaving forfeits a
  started race. Rooms expire
  after one hour. Race boards count as seen seeds and do not award solo scores.

Solo play and training work offline once the app assets have downloaded. High
scores and multiplayer require the Cloudflare backend described below.

Trio Sprint is an unofficial fan project. It is not affiliated with, endorsed
by, or sponsored by PlayMonster or Set Enterprises. SET® is a registered
trademark of its owner.

## Install

- **Android:** download the APK above and open it. Allow your browser or file
  manager to install apps when Android asks.
- **iPhone and iPad:** open the browser version in Safari and choose
  *Share → Add to Home Screen* and enable *Open as Web App* if shown.
- **Android web app:** use **Install app** in the game, or Chrome’s menu →
  *Install app / Add to Home screen*. No app store account is needed.

The offline cache is downloaded on the first visit. Updates wait until existing
app windows close, so a new deployment cannot interrupt an active run.

## Run

The Flutter SDK, Android Studio, Android SDK and build caches live in the ignored
`.tooling/` folder. The launchers configure their paths for this project.

```sh
./toolw flutter run -d chrome
# Or connect an Android phone with USB debugging enabled:
./toolw flutter run
# Open this project in Android Studio:
./studio
```

Select `.tooling/flutter` as the Flutter SDK in the IDE if prompted. The Flutter
IDE plugin can be installed from Android Studio's Plugins settings.

## Check and build

```sh
./toolw flutter analyze
./toolw flutter test
./toolw flutter build apk --debug --target-platform android-arm,android-arm64
./toolw flutter build web --no-web-resources-cdn --dart-define=API_URL=https://YOUR-WORKER.workers.dev
python3 tool/build_web.py
```

The Android debug APK for ARM phones is written to
`build/app/outputs/flutter-apk/app-debug.apk`. Omit `--target-platform` to also
include x86_64 emulator support.
The browser build is written to `build/web/`; serve it over HTTP rather than
opening `index.html` directly.

`lib/game.dart` contains the deck, rules, streak and solvability logic.
`lib/card_view.dart` draws the cards, and `lib/main.dart` contains the screens,
countdown and stopwatch.

## Release

Every push to `main` is checked, built and deployed to Cloudflare.
GitHub Pages serves a redirect that preserves seed and room links. To publish
a new Android APK, bump `version` in `pubspec.yaml` (including the `+build`
number, which Android uses to recognize updates) and push a matching tag:

```sh
git tag v1.0.1
git push origin v1.0.1
```

The release workflow signs the APK with the key in the `ANDROID_KEYSTORE`
(base64-encoded PKCS12, alias `upload`) and `ANDROID_KEYSTORE_PASSWORD`
repository secrets. Android only installs updates signed with the same key, so
keep a backup of it. Without `android/key.properties`, release builds use the
debug keys.

## License

The code is available under the [BSD Zero Clause License](LICENSE). The Roboto
fonts in `assets/fonts/` are under the Apache License 2.0; see
`assets/fonts/LICENSE.txt`.

## Cloudflare backend

Production app and API: **https://trio-sprint.floitsch.workers.dev**. The GitHub
repository variable `API_URL` points to this Worker.

One Cloudflare Worker serves the Flutter assets and API together, with
D1 for scores and a SQLite-backed Durable Object per race room. No secrets go
into the app. `API_URL` is a public base URL without a trailing slash. If omitted,
solo/training still work and online actions explain that they are unconfigured.

To deploy locally, first build Flutter for the root path and generate its offline
worker using the web build commands above. Then run `npm ci` and `npm run deploy`
in `backend/`. This publishes both the website and API in one deployment.
Apply any new D1 migrations with `npx wrangler d1 migrations apply trio-sprint-scores --remote`.

Automatic deployment uses `.github/workflows/cloudflare.yml`. Set the repository
secret `CLOUDFLARE_API_TOKEN` to a token restricted to the personal Cloudflare
account, with Account permissions: Workers Scripts Edit, D1 Edit, and Account
Settings Read. Keep the token in GitHub secrets, never in the repository.
The local Wrangler OAuth login is separate from this CI credential.

For a fresh deployment in another account, update `account_id` in the config,
then run from `backend/`:

```sh
npm ci
npx wrangler login
npx wrangler d1 create trio-sprint-scores
# Copy the returned database_id into backend/wrangler.jsonc.
npx wrangler d1 migrations apply trio-sprint-scores --remote
npm run deploy
```

Set the GitHub repository variable `API_URL` to the deployed Worker URL. The
Cloudflare and Android release workflows pass it to Flutter. Rebuild/deploy the web
app after setting it. For manual Android builds, also pass
`--dart-define=API_URL=https://YOUR-WORKER.workers.dev`.

For local development, from `backend/`:

```sh
mkdir -p ../build/web # Or build the Flutter website first.
npx wrangler d1 migrations apply trio-sprint-scores --local
npm run dev
```

Then run Flutter with `--dart-define=API_URL=http://localhost:8787`. A physical
phone needs the development machine’s reachable address rather than localhost.

Backend checks (integration tests write only to the configured test server;
use a disposable local database):

```sh
cd backend
npm test
# With npm run dev running in another terminal:
npm run test:integration
```

`tool/build_web.py` must run after every production web build. It fingerprints
and precaches that build’s local assets in `sw.js`, including CanvasKit and fonts.
It supports deployment in a subdirectory and offline navigation via seed links.
It does not cache scores or room traffic. The Cloudflare workflow runs it automatically.

`redirect/` is the GitHub Pages site. It forwards old links to Cloudflare,
preserving their query and fragment. Its service worker replaces the old offline
cache so existing installs also redirect. Home-screen shortcuts should be
reinstalled from the Cloudflare address. Browser-local nicknames, personal bests,
and attempt records belong to the old origin and do not move with a redirect;
the first-attempt honor rule still applies across both addresses.
