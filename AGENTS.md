# Writer for macOS

Native AppKit Markdown editor. Swift package, macOS 14+, built with the Xcode Command Line Tools.

## Layout

- `Sources/WriterCore`: logic with no UI. Markdown scanning and rendering (cmark-gfm), tables, authorship annotations, stats, Style Check, parts of speech (NaturalLanguage), library index.
- `Sources/Writer`: the AppKit app. Editor (TextKit 1), library sidebar, WebKit preview, menus, export.
- `Sources/corecheck`: assertions for the core.
- `Resources`: fonts, KaTeX, preview templates, `Welcome.md`, `Shortcuts.md`.
- `Scripts`: release and icon tooling. `Casks/writer.rb` is the Homebrew cask (this repo is its own tap).

## Commands

```sh
./build.sh
swift build --build-system native --product corecheck && .build/debug/corecheck
build/Writer.app/Contents/MacOS/Writer --snapshot <dir> --library <dir>
```

## Snapshot self-test

`--snapshot` is a hidden self-test that writes screenshots and sample exports.

- It is a GUI app: run it outside any sandbox.
- `--library` must not exist beforehand. The app only copies `Welcome.md` and `Shortcuts.md` into a library folder it creates itself. With an existing folder every check runs against an empty Untitled document.
- Healthy output includes `TYPEWRITER caret ... of ...`, `FOOTNOTE true` and `KATEX 2`.
- Timers within about 0.5s of each other can fire out of order, and the 3.4s step opens the preview and re-wraps the editor, so space out temporary probes.

## README screenshots

`docs/*.png` come from the snapshot run: `01-editor`, `02-focus`, `03-syntax-style-authors` and `06-preview`, resized with `sips -Z 1600` (`-Z 700` for the preview).

## Releasing

See `docs/RELEASING.md`.
