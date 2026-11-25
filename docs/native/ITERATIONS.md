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
