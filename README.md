# Writer for macOS

A native AppKit Markdown writing app modeled on iA Writer. The browser version lives separately in `../writer-clone`.

```sh
./build.sh                      # builds build/Writer.app
open build/Writer.app
swift build --build-system native --product corecheck && .build/debug/corecheck
```

Requires the Xcode Command Line Tools (no Xcode needed). The first launch creates `~/Documents/Writer` with a welcome document; pick another folder with File ▸ Choose Library Folder.

## Layout

- `Sources/WriterCore`: logic with no UI. Markdown scanning and rendering (cmark-gfm), tables, authorship annotations, stats, Style Check, parts of speech (NaturalLanguage), library index.
- `Sources/Writer`: the AppKit app. Editor (TextKit 1), library sidebar, WebKit preview, menus, export.
- `Sources/corecheck`: assertions for the core.
- `Resources`: fonts (iA Writer Mono/Duo/Quattro, SIL OFL), KaTeX (MIT), preview templates.

`build/Writer.app/Contents/MacOS/Writer --snapshot <dir> --library <dir>` runs a hidden self-test that writes screenshots and sample exports.

## Customizing

- Preview templates: drop a `.css` file into `~/Library/Application Support/Writer/Templates`; it appears under View ▸ Template.
- Style Check: View ▸ Style Check ▸ Edit Custom Patterns, one phrase per line.
- Authorship is stored in a footer block at the end of each file (`Annotations:` with a SHA-256 of the text). If the text is changed elsewhere the block is ignored.
