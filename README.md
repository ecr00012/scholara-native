# Scholara for macOS

A native, local-first PDF and EPUB reading and study application. SwiftUI and AppKit replace the entire Tauri/React application; PDFKit renders PDFs and TextKit lays out EPUB text without a WebView. Requires macOS 14 or later.

## Build and run

```sh
swift build --product Scholara
swift run ScholaraChecks
scripts/build-app.sh
open build/Scholara.app
# Optional installer image:
scripts/build-dmg.sh
```

A current Swift 6 toolchain is required (Xcode or Apple Command Line Tools). The checks use a small executable runner so full Xcode/XCTest is not required. The only third-party runtime dependency is ZIPFoundation, pinned in Package.resolved. Open Package.swift in Xcode to work in the IDE.

The packaging script creates both `build/Scholara.app` and `build/Scholara-macOS.zip`, signing in temporary staging outside cloud-synced folders. It signs locally with an ad-hoc identity. Set `SIGNING_IDENTITY` to a Developer ID identity for distribution signing. The local build is not notarized. `scripts/build-dmg.sh` also creates a compressed, mount-verified DMG with an Applications shortcut and SHA-256 checksum. The package is built for the host architecture; the supplied build is for Apple silicon.

## Reading and study

- Import PDFs and EPUBs through the native file picker, drag and drop, or Finder Open With.
- Open the reader’s top-right three-dot menu → Style for Appearance: Paper (white), Soft (the original cream-and-ink palette), or Dark. Choose EPUB font family and size with a live preview. Appearance is also available in Settings → Reading.
- Choose Scroll or Pages in the reader’s three-dot menu → Reading mode. PDF pagination uses PDFKit; EPUB pagination uses fixed-size TextKit containers. Reading layout is stored per book. Page mode shows Page X of Y across the entire book, recalculated in the background when font or window size changes. Opening a book focuses the reader for immediate keyboard navigation, including across chapter boundaries.
- Select text to highlight it, attach a note, or define a word using the macOS dictionary. Notes and vocabulary are also available across the library. The rounded note editor, insertion point, and saved-note cards follow the selected appearance.
- The rounded Scholar / Notes / Dictionary study panel can be hidden for focused reading. The Scholar button remains available in focus mode.
- The first upload prompts for local embedding consent. “Not Now” does not queue work. Each book has a three-dot **Embed to Enable Agent Scholar** action, progress, cancel, retry, and re-embed controls. Reading never starts embedding automatically.
- Embeddings use Apple's local sentence models, pooled by sentence, stored as binary Float32 vectors. Semantic retrieval is combined with SQLite FTS5. The UI runs only one embedding job at a time.
- Scholar supports streaming OpenRouter responses, multiple conversations, a shield spoiler toggle, book/notes tools, editable study preferences, and local study memory. Recent questions are remembered without extra background AI requests; this can be disabled in Settings.

## OpenRouter configuration

Settings → AI & Models lets you add/edit/remove arbitrary OpenRouter model paths and labels, choose the default, and set whether each model supports tools. Models without tools still receive locally retrieved book context. An optional live catalogue helps discovery but never acts as an allowlist.

The configuration is stored in `models.json` in the native data folder. The UI can reveal, reload, import, and export it. Invalid or duplicate paths are reported without overwriting the saved file. Existing conversations keep their selected paths even when those paths are removed from the picker.

API keys live in the macOS Keychain under service `scholara-native`, account `openrouter_api_key`. The explicit “Copy Key from Original Scholara” action reads the old entry and copies it; the old entry remains unchanged. No API key is included in repository files or request error bodies.

## Discovery

Gutendex supplies the catalogue; Project Gutenberg supplies cover images and EPUB downloads. Successful cover responses and the popular catalogue are cached locally. Pagination follows the API's next link and advances only after success. HTTP 404 can fall back to alternate EPUB editions; maintenance responses respect Retry-After and do not hammer the service. A service notice appears only after an unavailable response and clears after a successful cover/download request. Retry and Refresh explicitly probe recovery, even during automatic backoff; cached data and the current catalogue page are preserved.

## Local data and migration

The native app stores its library in `~/Library/Application Support/ScholaraNative/`. This is separate from the original Tauri app. Settings → Library & Data offers an explicit, read-only import of an old data folder containing `scholara.db`. The import copies books, notes, vocabulary, conversations, preferences, and profiles and is recorded to avoid duplicate imports.

Native annotation ranges and legacy PDF geometry are supported. Legacy EPUB CFIs map to spine sections; exact browser-specific text offsets are not guaranteed to map. Legacy MiniLM embeddings are not reused; each book requires an explicit native embedding action.

Back up the data folder with Scholara closed. Keychain credentials are separate. For development, `SCHOLARA_DATA_DIRECTORY=/absolute/test/folder` runs against an isolated library.

## Compatibility boundaries

EPUBs use native flowing text, headings, emphasis, lists, images, links and navigation. Browser CSS, scripted content, fixed-layout EPUBs, vector SVG illustrations (raster images wrapped in SVG are supported), embedded fonts, and interactive media are not a browser-equivalent rendering target. DRM-encrypted files are unsupported. PDFs with no extractable text need OCR before embedding. Apple sentence-model language availability depends on macOS. Spoiler filtering is page-based for PDFs and spine-section-based for EPUBs; model compliance with prose instructions cannot be guaranteed.

Live paid OpenRouter requests are not part of the automated tests. Signing/notarization for public distribution requires the owner's Apple developer credentials.

## Provenance and iteration notes

The original source snapshot is preserved in the initial commit. The sibling source repository is not modified. See [source provenance](docs/native/ORIGIN.md) and [iteration notes](docs/native/ITERATIONS.md), and [validation report](docs/native/VALIDATION.md).

Primary API references: [Apple NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding), [ZIPFoundation](https://github.com/weichsel/ZIPFoundation), [Gutendex](https://github.com/garethbjohnson/gutendex), [OpenRouter](https://openrouter.ai/docs/api-reference/chat-completion).
