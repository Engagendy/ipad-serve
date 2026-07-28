# HTML Serve App Store Submission

## App Information

- App name: HTML Serve
- Bundle ID: com.engagendy.iPadServe
- SKU: ipad-serve-ios
- Primary category: Utilities
- Content rights: No third-party content included by the app
- Encryption: None of the algorithms mentioned / no non-exempt encryption
- Price: Free
- Platform: Tablet
- Version: 1.1.0
- Build: 8
- Support URL: https://github.com/Engagendy/ipad-serve/issues
- Marketing URL: https://github.com/Engagendy/ipad-serve
- Privacy Policy URL: https://github.com/Engagendy/ipad-serve/blob/main/PRIVACY.md

## Promotional Text

Run interactive HTML projects fully offline. New: favorites, open a project at launch, Home Screen shortcuts, Wi-Fi sharing with QR codes, and Turkish support.

## What's New in 1.1.0

This update is packed with features requested by teachers and presenters:

- Favorites: star your most-used projects for quick access
- Open at Launch: pick a project that starts automatically when the app opens
- Resume: Run now returns to the last page you viewed in each project
- Home button in the browser toolbar to jump straight back to your projects
- Home Screen shortcuts: long-press the app icon to open a favorite, or add a project to your Home Screen with the Shortcuts app
- Link Folder in Place: use large projects without copying them into the app
- Share on Local Network: people on the same Wi-Fi can scan a QR code to open your project on their own devices (off by default)
- Rename projects, search your library, and pull to refresh
- Keyboard shortcuts, faster page loads, and lower memory use for large files
- Full Turkish localization

## Keywords

html,local server,ipad,web preview,static site,files,offline,developer,classroom,qr

## Subtitle

Local HTML project runner

## Description

HTML Serve lets users import static HTML project folders from the Files app and run them locally on device.

The app creates a local project library, scans folders, shows HTML pages and supporting files, and previews projects through an embedded browser powered by an on-device loopback server. It is designed for static projects that include HTML, CSS, JavaScript, images, PDFs, video, audio, and other local assets.

Key features:

- Import full project folders from the Files app
- Browse folders and files inside each imported project
- Run HTML pages locally inside the app
- Serve static assets through a local device-only server
- Support JavaScript interactions such as modals, navigation, charts, and client-side UI
- Preview common assets including images, PDFs, `.mov`, `.mp4`, and other files
- Use fullscreen mode for presentation and review
- Work offline after importing a project
- Mark projects as favorites and open a default project at launch
- Resume the last page you viewed in each project
- Open projects from Home Screen quick actions, the Shortcuts app, or htmlserve:// links
- Link folders in place instead of copying them to save storage
- Optionally share a project over local Wi-Fi with a scannable QR code
- Rename projects, search your library, and use keyboard shortcuts
- Available in English and Turkish

HTML Serve is built for users who need to review static HTML deliverables, prototypes, reports, dashboards, and local web projects directly on device without an external server.

## App Review Notes

No login is required. No account, subscription, purchase, user-generated content, analytics, tracking, or remote backend service is required for the app's core functionality.

To test the app:

1. Launch the app.
2. Tap the folder import button.
3. In the Files picker, choose a folder containing static HTML files and assets.
4. Select the imported project.
5. Tap an HTML file such as `index.html`.
6. Use the top controls to return to Files, navigate back/forward, reload, or enter fullscreen.
7. Open folders and preview supporting files such as images, PDFs, or video.

Sample project:

Any folder containing an `index.html` file can be used. A minimal test folder can contain:

- `index.html`
- `style.css`
- `script.js`
- `assets/image.png`

Important sandbox note:

HTML Serve only accesses folders selected by the user through the Files picker. It does not scan system storage, private app containers, other apps, Photos library content, Messages attachments, Mail storage, browser caches, or operating system caches.

External services:

None are required by the app. Static project files are served locally on device. Imported HTML content may reference external scripts, fonts, or links; those references belong to the imported project.

Local network usage:

The embedded server binds to 127.0.0.1 only. If the user explicitly enables "Share on Local Network", the server accepts connections from devices on the same Wi-Fi so they can view the user's own project; this is why the app declares NSLocalNetworkUsageDescription. Sharing is off by default, is clearly indicated in the UI, and serves only folders the user imported. No data leaves the local network and nothing is collected.

Regional differences:

None. The app functions consistently across all regions.

Regulated industry or protected third-party material:

Not applicable. Users import and run their own local files.

Suggested test device:

- Tablet device running the latest available OS

## Privacy

Suggested App Privacy answer: Data Not Collected.

The app does not collect analytics, account information, contact information, location, identifiers, diagnostics, usage data, or user content. Imported folders are stored locally inside the app and are not uploaded.
