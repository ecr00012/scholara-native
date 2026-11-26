# Conversion iterations

## 1. Isolation and native foundation

Copied the original working tree into a sibling folder, excluding generated dependency/build directories. Initialized a fresh Git history, preserved the source snapshot, created a private repository on ecr00012, recorded upstream, and disabled upstream pushes.

Optimization: remove Tauri, React, Vite, Rust IPC, PDF.js, epub.js, JavaScript workers and ONNX from the active build. Use system frameworks plus ZIPFoundation. The original model-list working-tree change remains in the initial snapshot.

## 2. Storage, reading and Scholar

Implemented SQLite/WAL persistence, PDFKit, native EPUB extraction/layout, notes, exact quote anchors, vocabulary, conversations, read-only legacy migration, Keychain, streaming OpenRouter, editable model configuration, and explicit embedding consent.

Optimizations: one utility-priority embedding job at a time; pooled local sentence vectors; binary vector storage; FTS5 plus Accelerate cosine similarity; transactional index publication; throttled streaming UI updates; debounced position writes; per-section EPUB rendering; cover thumbnails; local study memory without extra model calls. Interrupted jobs become retryable; cancellation never publishes a partial index.

Validation: executable regression checks passed on this Mac, including real Apple embedding and semantic retrieval, import/SQLite persistence, cascade deletion, source-preserving migration, model config validation, archive traversal rejection, SSE parsing and spoiler filtering. CUA verified first-import consent, deferral, later per-book embedding through completion, arbitrary model-path save, EPUB highlight creation, and native PDF rendering in an isolated test library.

## 3. UI and service refinement

User requested Paper/Soft light palettes, paged/scrolling modes, reference-style study tabs and definition card, semantic dictionary colors, original-style shield spoiler indicator, and Gutenberg repairs.

Implemented palette tokens using the original #FAFAF7 / #1F1B16 / #C8702C values for Soft; Paper uses white. Native TextKit page containers support EPUB page turns, resize anchors and native selection. PDFKit switches single-page/continuous layouts. Native reading mode and page anchors persist per book.

Dictionary values retain structured part of speech, pronunciation and origin, including compatibility with old `(part of speech)` strings. Popups and saved vocabulary share the same renderer. Repeat quotations resolve through stored UTF-16 ranges before text fallback. Sidebar navigation uses typed destinations, correcting inaccessible recent-book activation.

Discovery investigation on November 25, 2026: direct Project Gutenberg cover and EPUB URLs returned HTTP 503 and an explicit maintenance page, with Retry-After: 21600. Gutendex's canonical nonempty queries returned successful first and second pages. The app also advanced its page counter before network success. The repair follows validated next URLs, commits cursor changes only on success, omits empty search parameters, retains results on error, deduplicates book IDs, caches successful covers, limits concurrent requests to four, respects maintenance backoff, validates EPUB bodies, and tries alternative editions only for 404 responses. External maintenance cannot be repaired in client code.

Further verification and measured package details are recorded in VALIDATION.md at delivery.

## 4. Native layout and delivery verification

Interactive checks exposed native page-background drawing beyond its bounds and a scroll restoration race at initial text width. Clip native page drawing; restore scrolling only after layout establishes the container width. Page mode creates only the visible NSTextView while retaining the section's TextKit containers. Fit copied image attachments to both page dimensions, preserve character anchors through resizing, and retain the current passage when changing modes. PDF search now advances through matches within the same page. EPUB 2 nested NCX labels are supported alongside EPUB 3 navigation.

Optimizations: no offscreen page views; cover requests share a bounded pool and maintenance backoff; retry preserves whether a request replaces or appends results; package only the runtime resource bundle. Rebuild packaging from a clean generated bundle, normalize copied resource permissions/metadata, and verify the code signature. The original Lucide shield outline is adapted to a native Path, with its ISC license included.

Validation: 31 local regression checks pass, zero skips. New checks cover pagination continuity with oversized illustrations, resize anchors, reading-mode persistence, dictionary fields, EPUB 2 navigation, successful Gutenberg fallback/import without embedding, rejected HTML responses, atomic/deduplicated catalogue pagination, and maintenance backoff. The real embedding test now uses English prose because OS language detectors classified the old lorem-ipsum fixture differently in CI. Interactive testing verified EPUB page-button and keyboard turns, PDF single-page keyboard turns, Paper/Soft changes, dictionary card colors, and live catalogue growth from 32 to 64 after a retained-page retry.

Final packaging refinement: sign in a temporary directory outside File Provider-managed Documents, then create the portable archive from that signed bundle. Move URLSession's disk cache to macOS Caches instead of the working directory. The release bundle is about 4.9 MB (2.1 MB compressed), and both local and hosted checks passed.

## 5. Downloadable disk image

At the owner’s request, publish the native build as a GitHub release DMG. Add a repeatable packaging script that extracts the verified app archive into temporary staging, includes an Applications shortcut and installation notes, creates a compressed read-only image, verifies its checksum, mounts it, verifies the app signature and executable bytes, and ejects it. Publish a separate SHA-256 checksum. CI now packages both ZIP and DMG.

Optimization: use built-in hdiutil and ditto without a packaging dependency or Finder automation; retain temporary staging outside File Provider folders. The app remains ad-hoc signed, not notarized.


## 6. Reader style, front matter, and uninterrupted navigation

Version 0.2.1 adds Appearance with Paper, Soft, and Dark. The reader’s three-dot menu now holds Scroll/Pages and a centered native Style panel with native font selection, size, and live preview. Library EPUB covers fill a 2:3 portrait container. Notes and highlights share vocabulary’s rounded cards, serif headings, fine outlines, and semantic accents, both inside the reader and across the library.

The blank first page in Middlemarch came from a raster cover wrapped in an SVG image element. Render safe local image references in these wrappers; derive missing contents labels from cover metadata, semantic front matter, and headings instead of filenames. Skip genuinely empty sections when opening/navigating without renumbering the spine, preserving existing annotation and bookmark IDs.

Preserve the native text view’s first-responder status when replacing it at chapter boundaries. Reject obsolete deferred page callbacks so rapid page turns cannot save a stale anchor. Gutenberg notices now report actual service-unavailable responses instead of assuming maintenance, clear on successful remote requests, and offer a deliberate recovery probe through Retry/Refresh. Local cover cache hits do not falsely announce service recovery.

Optimizations: retain the existing single visible page view; use revision tokens instead of extra layout passes; resolve fallback titles only for sections missing navigation labels; keep cached covers and the bounded request pool during explicit recovery attempts; reuse note-card presentation across screens.

Validation: 36 regression checks pass with zero failures/skips. New checks cover SVG-wrapped covers and unsafe image URLs, readable first-section selection with stable chapter IDs, font-family changes preserving text and emphasis, and successful recovery before Retry-After expires. Interactive checks in an isolated library confirmed Middlemarch’s full cover on first open, “Cover” in Contents, forward and backward chapter-boundary arrow turns followed by further keyboard turns, Paper/Soft/Dark, the Style font picker, note-card styling, and failure-triggered Gutenberg Retry. The upstream still returned 503 during the live check; successful recovery is tested with controlled transport.

The follow-up adds a native note editor whose placeholder and insertion point share the same TextKit origin and font. Rounded input borders, text, caret, and saved-note backgrounds now track all three appearances. Opening EPUBs and PDFs establishes reader focus once; subsequent chapter replacements preserve it without interrupting note entry. The position label uses Chapter X and Page X of Y across the whole EPUB, rather than restarting page numbers at each chapter.

Optimization: count whole-book pages on a cancellable utility task, debounce resize work, release each chapter’s text/layout after counting, and retain only compact counts for up to four layout variants. Appearance-only changes reuse counts. Two regression checks exercise global offsets across empty chapters and background pagination at different font sizes. Interactive checks confirmed immediate arrow navigation after opening, Page 5 of 7 → Page 6 of 7 across a chapter boundary, background counting of Middlemarch, aligned note placeholders/carets, and input/cards in Paper, Soft, and Dark.
