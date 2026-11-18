# Releasing

One-time setup:

1. Run `.build/artifacts/sparkle/Sparkle/bin/generate_keys` and paste the printed public key into `SUPublicEDKey` in `Resources/Info.plist`. The private key stays in your login keychain; export it with `generate_keys -x <file>` and store it as the `SPARKLE_PRIVATE_KEY` GitHub secret for CI.

Each release:

```sh
git tag v0.2.0 && git push --tags     # CI builds and publishes, or run locally:
Scripts/release.sh 0.2.0              # writes build/release/{Writer-0.2.0.zip,appcast.xml,writer.rb}
```

CI uploads the zip and `appcast.xml` to the GitHub release (the app checks `releases/latest/download/appcast.xml`), then commits `writer.rb` to `Casks/writer.rb` on main. This repo is its own Homebrew tap. When releasing locally, do both by hand.

Builds are ad-hoc signed by default, so a downloaded zip needs System Settings ▸ Privacy & Security ▸ Open Anyway on first launch (the Homebrew cask removes the quarantine flag itself). To sign and notarize, set `DEVELOPER_ID` (for example `Developer ID Application: Name (TEAMID)`) and `NOTARY_PROFILE` (a `notarytool store-credentials` profile). In CI add the secrets `DEVELOPER_ID`, `CERTIFICATE_P12`, `CERTIFICATE_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD`.
