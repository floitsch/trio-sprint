# Trio Sprint

**[Play in the browser](https://trio-sprint.floitsch.workers.dev/)** ·
**[Download for Android](https://github.com/floitsch/trio-sprint/releases/latest/download/trio-sprint.apk)**

A Flutter pattern game: find **five sets** with a two-second countdown before
cards appear and the stopwatch starts. Each round has a fresh 12-card board.
For every feature — number, shape, color, fill — the three cards must be all the
same or all different. Wrong trios count as mistakes while the clock continues.
Leaving the app does not pause the stopwatch.

- **Seeds:** every sprint uses a versioned seed, such as `s1-1234abcd`. Share a
  link or paste a seed/link into **Run a seed**. Everyone gets the same five
  boards, independent of the sets they choose. Seed algorithm versions are
  permanent; changing the algorithm requires a new prefix.
- **High scores:** fastest 100 runs, across all seeds or for one seed. Toggle
  **Only each player’s best** to hide additional runs from the same player ID.
  Nicknames and random player IDs are remembered on each device, without login.
  First-attempt personal bests also persist locally.
- **First attempts only:** starting a seed consumes its eligibility, including
  abandoned runs and countdown restarts. Replays are practice. Browser Web Locks
  serialize claims across tabs, and local storage remembers them across visits.
  Android uses persistent preferences. Storage failures make runs practice-only.
  After a first attempt finishes, players can opt into submitting it and confirm
  that they have never run that seed before, including on another device.
  The server validates all five solutions and allows only one score per player
  and seed; retries of the same submission are safe. This is an honor system:
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
- **1 vs 1:** share a room link/code, ready up, and race through the same five
  boards. A Cloudflare room validates claims and chooses the winner. Reconnect
  with the same device to resume; leaving forfeits a started race. Rooms expire
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
