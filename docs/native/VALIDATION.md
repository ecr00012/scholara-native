# Native release validation — November 25, 2026

## Automated checks

`swift run ScholaraChecks`: **31 passed, 0 failed, 0 skipped** on the development Mac. The same 31 checks passed on GitHub's macOS 15 runner. The runner also built, signed, and archived the native app successfully: [verified workflow](https://github.com/ecr00012/scholara-native/actions/runs/45684658213).

Coverage includes arbitrary OpenRouter paths and atomic config validation; owned PDF/EPUB import without automatic embeddings; unsafe archive rejection; native XHTML formatting and EPUB 2 navigation; SQLite study-data persistence and transactional updates; source-preserving legacy import; local Apple embeddings and semantic retrieval; cancellation and interrupted-job recovery; spoiler retrieval limits; SSE stream framing; exact repeated-quote anchors; dictionary field persistence; reading modes and offsets; complete TextKit pagination with oversized images and resize anchors; catalogue deduplication/failed-page preservation; maintenance backoff; successful simulated EPUB fallback/import; and rejection of HTML masquerading as a book.

The expected invalid-PDF test causes a CoreGraphics diagnostic on stderr; it passes by verifying import failure and cleanup.

## Interactive verification

Computer Use exercised an isolated library, without altering the original Tauri library:

- Import consent, Not Now, later per-book embedding through completion, and readable unembedded books.
- Arbitrary model-path editing and saving through Settings.
- Native EPUB rendering, contents links, highlight creation, and exact selection anchors.
- Paper and Soft appearance, reference-style Scholar / Notes / Dictionary tabs, native shield spoiler indicator, rounded dictionary card, and colored saved dictionary fields.
- Long EPUB sections paginated into 25–41 pages depending on the available width/height. Arrow buttons and left/right keys changed pages; resize preserved the character anchor.
- Final release switched page 3 → scrolling → page 3 without losing the reading location.
- PDF single-page mode changed pages through both toolbar buttons and the right-arrow key.
- Recent-book sidebar navigation opened the selected book.
- Live Gutendex catalogue advanced from 32 to 64 books after a timed-out request was retried without skipping a page.

The release archive was extracted to a fresh temporary folder, its strict deep code signature verified, and the app launched and rendered an EPUB there. The test app process was stopped after verification.

## Packaging and optimizations

The Apple silicon release app is approximately **4.9 MB**, compressed to approximately **2.1 MB**. `otool -L` lists Apple frameworks and system libraries; there is no Tauri, WebKit, JavaScript runtime, Rust IPC process, or bundled ONNX model. ZIPFoundation is statically linked; only its runtime privacy resource and required licenses are packaged.

Signing occurs in temporary staging outside iCloud/File Provider folders to avoid automatic Finder metadata races. The signed staging bundle is archived without resource forks or extended attributes. Public HTTP cache data lives under the standard macOS Caches directory; persistent book covers live in the native application data folder.

See ITERATIONS.md for per-iteration optimizations, including bounded networking, native model use, transactional indexing, binary vectors, FTS5/Accelerate retrieval, debounced writes, and a single visible page view.

## External limits and unverified paths

- Project Gutenberg returned HTTP 503 with a maintenance page and Retry-After: 21600 for covers and EPUBs during validation. The app handles this clearly, but cannot restore an unavailable upstream service. Successful download/fallback/import is covered using a controlled URLSession transport; live catalogue pagination was verified separately.
- Live paid OpenRouter responses and real credential copying were not exercised. Streaming/tool parsing and configuration have automated coverage.
- The supplied build is locally ad-hoc signed, **not notarized**, and targets Apple silicon. Public Developer ID distribution needs the owner's signing credentials.
- Native EPUB formatting supports flowing text, common text semantics, raster images, and navigation. CSS/fixed-layout/scripted content, SVG illustrations, embedded fonts, DRM, and OCR are outside this renderer's current compatibility scope. EPUB spoiler retrieval limits operate at spine-section granularity.

## Original source integrity

Original HEAD remains `3acb4d208e4df233f7cc7feb3b81b01cacb879a9`. Original status remains ` M src/agent/models.ts`. That file's SHA-256 is `5386d275c5ab2bf39bd6a0e1cb0b5cc3e5c7f1bdf9d2cb07613a794b529a8635`, matching the initial copied snapshot. The native repository is independent and private under ecr00012; original upstream pushes are disabled.
