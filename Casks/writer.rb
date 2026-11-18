cask "writer" do
  version "0.3.0"
  sha256 "d351e154268dbbbed6f1eb21f1c2385985b7136bacdeaabbcc8a89a0bf96c6d9"

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
