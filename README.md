# Writer for macOS

A native AppKit Markdown writing app modeled on iA Writer. The browser version lives in [writer-web](https://github.com/sam-b-rose/writer-web).

```sh
./build.sh                      # builds build/Writer.app
open build/Writer.app
swift build --build-system native --product corecheck && .build/debug/corecheck
```

Requires the Xcode Command Line Tools (no Xcode needed). The first launch creates `~/Documents/Writer` with a welcome document; pick another folder with File ▸ Choose Library Folder.

## Install

```sh
brew tap sam-b-rose/writer-mac https://github.com/sam-b-rose/writer-mac
brew install --cask sam-b-rose/writer-mac/writer
```

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

## Releasing

One-time setup:

1. Run `.build/artifacts/sparkle/Sparkle/bin/generate_keys` and paste the printed public key into `SUPublicEDKey` in `Resources/Info.plist`. The private key stays in your login keychain; export it with `generate_keys -x <file>` and store it as the `SPARKLE_PRIVATE_KEY` GitHub secret for CI.

Each release:

```sh
git tag v0.2.0 && git push --tags     # CI builds and publishes, or run locally:
Scripts/release.sh 0.2.0              # writes build/release/{Writer-0.2.0.zip,appcast.xml,writer.rb}
```

Upload the zip and `appcast.xml` to the GitHub release (the app checks `releases/latest/download/appcast.xml`) and copy `writer.rb` to `Casks/writer.rb` and commit it. This repo is its own Homebrew tap.

Builds are ad-hoc signed by default, so a downloaded zip needs System Settings ▸ Privacy & Security ▸ Open Anyway on first launch (the Homebrew cask removes the quarantine flag itself). To sign and notarize, set `DEVELOPER_ID` (for example `Developer ID Application: Name (TEAMID)`) and `NOTARY_PROFILE` (a `notarytool store-credentials` profile). In CI add the secrets `DEVELOPER_ID`, `CERTIFICATE_P12`, `CERTIFICATE_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD`.
