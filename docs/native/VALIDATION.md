# Native release validation — November 25, 2026

## Automated checks

`swift run ScholaraChecks`: **36 passed, 0 failed, 0 skipped** on the development Mac for version 0.2.1. The preceding 31-check release passed on GitHub's macOS 15 runner. The runner also built, signed, and archived the native app successfully: [verified workflow](https://github.com/ecr00012/scholara-native/actions/runs/45684658213).

Coverage includes arbitrary OpenRouter paths and atomic config validation; owned PDF/EPUB import without automatic embeddings; unsafe archive rejection; native XHTML formatting and EPUB 2 navigation; SQLite study-data persistence and transactional updates; source-preserving legacy import; local Apple embeddings and semantic retrieval; cancellation and interrupted-job recovery; spoiler retrieval limits; SSE stream framing; exact repeated-quote anchors; dictionary field persistence; reading modes and offsets; complete TextKit pagination with oversized images and resize anchors; catalogue deduplication/failed-page preservation; maintenance backoff; successful simulated EPUB fallback/import; rejection of HTML masquerading as a book; SVG-wrapped covers and safe image paths; font changes preserving anchors/emphasis; explicit service recovery; and whole-book pagination across chapter boundaries, including background counts at different font sizes.

The expected invalid-PDF test causes a CoreGraphics diagnostic on stderr; it passes by verifying import failure and cleanup.

## Interactive verification

Computer Use exercised an isolated library, without altering the original Tauri library:

- Import consent, Not Now, later per-book embedding through completion, and readable unembedded books.
- Arbitrary model-path editing and saving through Settings.
- Native EPUB rendering, contents links, highlight creation, and exact selection anchors. Version 0.2.1 renders Middlemarch’s SVG-wrapped raster cover on first open and labels its first section “Cover”. Empty sections are skipped without renumbering saved annotations.
- Paper, Soft, and Dark appearance, reader menu Style with font preview, reference-style Scholar / Notes / Dictionary tabs, native shield spoiler indicator, rounded dictionary card, and colored saved dictionary fields.
- Long EPUB sections paginated into 25–41 pages depending on the available width/height. Arrow buttons and left/right keys changed pages; resize preserved the character anchor.
- Final release switched page 3 → scrolling → page 3 without losing the reading location.
- PDF single-page mode changed pages through both toolbar buttons and the right-arrow key.
- Recent-book sidebar navigation opened the selected book. Arrow-key focus remained in the reader across forward and backward chapter boundaries, with subsequent keys continuing to turn pages. Notes/highlights use the same card styling as vocabulary.
- Opening a book immediately focused its native text view; arrow navigation advanced Page 5 of 7 → Page 6 of 7 across a chapter boundary. Middlemarch completed its whole-book count in the background. Chapter labels no longer show Section X of Y.
- Notes input, caret, placeholder, saved cards, and surrounding area were visually verified in Paper, Soft, and Dark. Typed text and the caret align with the placeholder; Style appears as a fully visible centered sheet.
- Live Gutendex catalogue advanced from 32 to 64 books after a timed-out request was retried without skipping a page.

The release archive was extracted to a fresh temporary folder, its strict deep code signature verified, and the app launched and rendered an EPUB there. The test app process was stopped after verification.

## Packaging and optimizations

The Apple silicon release app is approximately **5.2 MB**, compressed to approximately **2.2 MB** as a ZIP or **2.4 MB** as a DMG. `otool -L` lists Apple frameworks and system libraries; there is no Tauri, WebKit, JavaScript runtime, Rust IPC process, or bundled ONNX model. ZIPFoundation is statically linked; only its runtime privacy resource and required licenses are packaged.

Signing occurs in temporary staging outside iCloud/File Provider folders to avoid automatic Finder metadata races. The signed staging bundle is archived without resource forks or extended attributes. Public HTTP cache data lives under the standard macOS Caches directory; persistent book covers live in the native application data folder.

See ITERATIONS.md for per-iteration optimizations, including bounded networking, native model use, transactional indexing, binary vectors, FTS5/Accelerate retrieval, debounced writes, and a single visible page view.

## External limits and unverified paths

- Project Gutenberg returned HTTP 503 with a maintenance page and Retry-After: 21600 for covers and EPUBs during validation. The app handles this clearly, but cannot restore an unavailable upstream service. Successful download/fallback/import is covered using a controlled URLSession transport; live catalogue pagination was verified separately.
- Live paid OpenRouter responses and real credential copying were not exercised. Streaming/tool parsing and configuration have automated coverage.
- The supplied build is locally ad-hoc signed, **not notarized**, and targets Apple silicon. Public Developer ID distribution needs the owner's signing credentials.
- Native EPUB formatting supports flowing text, common text semantics, raster images, and navigation. CSS/fixed-layout/scripted content, vector SVG illustrations, embedded fonts, DRM, and OCR are outside this renderer's current compatibility scope. Raster covers wrapped in SVG are supported. EPUB spoiler retrieval limits operate at spine-section granularity.

## Original source integrity

Original HEAD remains `3acb4d208e4df233f7cc7feb3b81b01cacb879a9`. Original status remains ` M src/agent/models.ts`. That file's SHA-256 is `5386d275c5ab2bf39bd6a0e1cb0b5cc3e5c7f1bdf9d2cb07613a794b529a8635`, matching the initial copied snapshot. The native repository is independent and public under ecr00012 (visibility changed at the owner’s request); original upstream pushes are disabled.

Version 0.2.1 DMG validation: read-only mount, strict deep app signature, packaged executable byte comparison, Applications shortcut, and image checksum all passed. SHA-256: `5fde8589e05ab2ca31352c5789f47ccd6b65231e7160c81227c54c8aba9dab6c`.
