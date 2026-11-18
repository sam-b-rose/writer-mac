cask "writer" do
  version "0.1.0"
  sha256 "935b1e1416fe4e4f861952b3057f0cd7394bc7687b8b821c7baee5f16d460587"

  url "https://github.com/sam-b-rose/writer-mac/releases/download/v#{version}/Writer-#{version}.zip"
  name "Writer"
  desc "Markdown writing app"
  homepage "https://github.com/sam-b-rose/writer-mac"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Writer.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Writer.app"]
  end

  zap trash: [
    "~/Library/Preferences/io.github.sam-b-rose.writer.plist",
    "~/Library/Application Support/Writer",
  ]
end
