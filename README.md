# HTML Serve

HTML Serve is a native app for running static HTML projects fully on device, offline, without a desktop server.

## What It Supports

- Import a whole folder from the system Files app
- Store imported projects inside the app
- Detect and list `.html` / `.htm` pages
- Serve local assets through an embedded HTTP server
- Run pages in an embedded `WKWebView`
- Normal JavaScript interactions, including DOM modals, tabs, buttons, charts, and client-side UI
- Static assets such as CSS, JS, JSON, PDF, images, `.mov`, `.mp4`, `.m4v`, audio, SVG, and Arabic filenames
- Byte-range requests for video playback and seeking

## Current Limits

This app is for static frontend projects. It does not run Node, Vite dev servers, PHP, Python, databases, or backend APIs inside the app.

If a page calls an external API, that API still needs to be reachable from the device. If the project is pure HTML/CSS/JS/assets like `GPRC`, it can run offline.

## Build

Open:

```sh
open iPadServe.xcodeproj
```

Select a device destination, then build and run.

The project is generated from `project.yml` using XcodeGen:

```sh
xcodegen generate
```

## Release (Xcode Cloud)

There is no CI pipeline in this repo (no GitHub Actions). Builds run on
**Xcode Cloud**, which is configured in App Store Connect, not in git.
GitHub only hosts the source; Apple pulls from it.

Where to see builds:

- App Store Connect → the app → **Xcode Cloud** tab, or
- Xcode → Report Navigator (⌘9) → **Cloud** tab

### Release checklist

1. Bump the version in `project.yml` (`MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION`). Always bump it there, **not** in the
   `.pbxproj` — `xcodegen generate` overwrites the pbxproj and would
   silently revert a version bumped only in Xcode.
2. Run `xcodegen generate` and build to verify.
3. Commit and push to `main`.
4. Start the build: App Store Connect → Xcode Cloud → **Start Build**,
   pick the workflow and branch `main`. (Pushes do not currently
   trigger builds automatically — see below.)
5. When the build finishes processing, submit it for review from
   App Store Connect and update the "What's New" notes.

### Making pushes trigger builds automatically (optional)

App Store Connect → Xcode Cloud → **Manage Workflows** → open the
workflow → **Start Conditions** → add a **Branch Changes** condition
for `main`. Also confirm the Archive action delivers to TestFlight or
App Store, otherwise the build goes nowhere.

## Use On Device

1. Install the app on device.
2. Copy a project folder using Files, AirDrop, iCloud Drive, or USB-C storage.
3. Open HTML Serve.
4. Tap the folder import button.
5. Choose the project folder.
6. Tap `index.html` or any detected HTML page.

The app starts a local server and opens the page using a local URL like:

```text
http://127.0.0.1:<port>/file/<project>/<page>
```
