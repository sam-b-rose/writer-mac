cask "writer" do
  version "0.3.2"
  sha256 "0525d3313407cf1b7ecb64e8fdb666747a10158663ac7f8fae44d17c70845377"

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
