# iPad Serve

iPad Serve is a native iPadOS app for running static HTML projects fully on iPad, offline, without a Mac server.

## What It Supports

- Import a whole folder from the iPad Files app
- Store imported projects inside the app
- Detect and list `.html` / `.htm` pages
- Serve local assets through an embedded HTTP server
- Run pages in an embedded `WKWebView`
- Normal JavaScript interactions, including DOM modals, tabs, buttons, charts, and client-side UI
- Static assets such as CSS, JS, JSON, PDF, images, `.mov`, `.mp4`, `.m4v`, audio, SVG, and Arabic filenames
- Byte-range requests for video playback and seeking

## Current Limits

This app is for static frontend projects. It does not run Node, Vite dev servers, PHP, Python, databases, or backend APIs inside iPadOS.

If a page calls an external API, that API still needs to be reachable from the iPad. If the project is pure HTML/CSS/JS/assets like `GPRC`, it can run offline.

## Build

Open:

```sh
open iPadServe.xcodeproj
```

Select an iPad destination, then build and run.

The project is generated from `project.yml` using XcodeGen:

```sh
xcodegen generate
```

## Use On iPad

1. Install the app on iPad.
2. Copy a project folder to iPad using Files, AirDrop, iCloud Drive, or USB-C storage.
3. Open iPad Serve.
4. Tap the folder import button.
5. Choose the project folder.
6. Tap `index.html` or any detected HTML page.

The app starts a local server and opens the page using a local URL like:

```text
http://127.0.0.1:<port>/file/<project>/<page>
```
