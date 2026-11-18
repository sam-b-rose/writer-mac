cask "writer" do
  version "0.2.0"
  sha256 "b6b42de4c20aa99c40f9c17c200bfd8004598587ce523fea56131f55bf98ee89"

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
