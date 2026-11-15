import Foundation
import WriterCore

var failures = 0
func check(_ condition: Bool, _ label: String) {
    if !condition {
        failures += 1
        print("FAIL: \(label)")
    }
}

let body = "Hello **world**.\nSecond line."
let ranges = [AuthorRange(range: NSRange(location: 0, length: 5), author: Author.ai), AuthorRange(range: NSRange(location: 6, length: 4), author: Author.named("Sam"))]
let file = Annotations.join(body: body, ranges: ranges)
let parsed = Annotations.split(file)
check(parsed.body == body, "annotation body roundtrip")
check(parsed.ranges.count == 2 && parsed.ranges.contains(ranges[0]) && parsed.ranges.contains(ranges[1]), "annotation ranges roundtrip")
check(Annotations.split(file.replacingOccurrences(of: "Hello", with: "Hallo")).ranges.isEmpty, "annotation hash mismatch drops ranges")
check(Annotations.split("plain").body == "plain", "no annotations")

check(Stats.count(.words, in: "# Title\n\nOne two-three four.") == 4, "word count \(Stats.count(.words, in: "# Title\n\nOne two-three four."))")
check(Stats.count(.sentences, in: "One. Two! Three?") == 3, "sentences")
check(Stats.count(.paragraphs, in: "a\n\nb\nc\n\n\nd") == 3, "paragraphs")
check(Stats.format(.tasks, document: "- [x] a\n- [ ] b", selection: "") == "1 of 2 Tasks", "tasks")

let checker = StyleChecker(enabled: [.fillers, .cliches, .custom], custom: ["synergy"])
let found = checker.matches(in: "It is actually fine at the end of the day, with Synergy and future plans.")
check(found.map(\.category).sorted { $0.rawValue < $1.rawValue } == [.cliches, .custom, .fillers], "style check \(found.map(\.category))")

let tagger = PartOfSpeechTagger()
let tags = tagger.tags(in: "The quick fox quickly jumps and runs.")
check(tags.contains { $0.1 == .adjectives } && tags.contains { $0.1 == .adverbs } && tags.contains { $0.1 == .verbs } && tags.contains { $0.1 == .nouns } && tags.contains { $0.1 == .conjunctions }, "pos tags \(tags)")

let text = "First one. Second one here. Third.\n\nNext paragraph." as NSString
check(text.substring(with: TextScopes.sentence(in: text, at: 14)).hasPrefix("Second one here."), "sentence scope '\(text.substring(with: TextScopes.sentence(in: text, at: 14)))'")
check(text.substring(with: TextScopes.paragraph(in: text, at: 3)) == "First one. Second one here. Third.\n", "paragraph scope")

let scan = SyntaxScanner.scan("# Head\n\nSome **bold** and *it* with `co*de*` #tag [[Wiki]] [a](http://x_y_z)\n\n```\n**not**\n```\n- item\n" as NSString)
func has(_ kind: SpanKind, _ s: String) -> Bool {
    scan.spans.contains { $0.kind == kind && ("# Head\n\nSome **bold** and *it* with `co*de*` #tag [[Wiki]] [a](http://x_y_z)\n\n```\n**not**\n```\n- item\n" as NSString).substring(with: $0.range) == s }
}
check(has(.strong, "bold"), "scan strong")
check(has(.emphasis, "it"), "scan emphasis")
check(!has(.emphasis, "de"), "no emphasis in code")
check(!has(.strong, "not"), "no strong in fence")
check(has(.hashtag, "#tag"), "scan hashtag")
check(has(.wikilink, "Wiki"), "scan wikilink")
check(has(.heading(hang: 2), "# Head"), "scan heading")
check(has(.hanging(indent: 2), "- item\n"), "scan list")
check(SyntaxScanner.scan("##" as NSString).spans.contains { $0.kind == .heading(hang: 3) }, "scan bare heading marker")
check(!scan.spans.contains { $0.kind == .emphasis && $0.range.location > 60 && $0.range.location < 75 }, "no emphasis in url")
check(SyntaxScanner.hashtags(in: "# Heading\n#one and #Two/three, issue #12 a#b") == ["one", "two/three"], "hashtags \(SyntaxScanner.hashtags(in: "# Heading\n#one and #Two/three, issue #12 a#b"))")

var table = MarkdownTable(lines: ["| a | b |", "|---|:-:|", "| 1 | 2 |", "| 30 | 4 |"])!
check(table.rows == [["a", "b"], ["1", "2"], ["30", "4"]], "table parse")
table.sort(column: 0, ascending: false)
check(table.rows[1][0] == "30", "table sort")
table.insertColumn(at: 1)
table.rows[0][1] = "new"
check(table.render() == "| a   | new |  b  |\n| --- | --- | :-: |\n| 30  |     |  4  |\n| 1   |     |  2  |", "table render\n\(table.render())")
let doc = "x\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\ny" as NSString
let location = MarkdownTable.locate(in: doc, at: doc.range(of: "2 |").location)
check(location?.row == 1 && location?.column == 1, "table locate \(String(describing: location?.row)) \(String(describing: location?.column))")
check(location.map { doc.substring(with: $0.range) } == "| a | b |\n|---|---|\n| 1 | 2 |", "table range")
check(MarkdownTable.locate(in: doc, at: 0) == nil, "no table")

var options = RenderOptions()
options.loadBlock = { path in
    switch path {
    case "other.md": return .markdown("Embedded *text*")
    case "data.csv": return .csv("name,qty\n\"Apple, red\",3")
    case "pic.png": return .image(source: "pic.png")
    default: return nil
    }
}
let html = MarkdownRenderer.html("""
# Title

{{TOC}}

## Sub *one*

Text with ==mark==, [[Other Note|label]], $a_1 + b_2$ and `==code==`.[^1]

> [!NOTE]
> Careful.

| a | b |
|---|---|
| 1 | 2 |

- [x] done

/other.md
/data.csv
/pic.png "Caption"
/missing.md

+++

$$
x^2
$$

```
[[raw]] $x$
```

[^1]: Footnote text.
""", options: options)
for needle in [
    "<h1 id=\"title\">", "<h2 id=\"sub-one\">", "<nav class=\"toc\">", "href=\"#sub-one\"", "<mark>mark</mark>",
    "<a href=\"writer://open/Other%20Note\">label</a>", "<span class=\"math inline\">a_1 + b_2</span>",
    "<code>==code==</code>", "callout callout-note", "<table>", "type=\"checkbox\"", "Embedded <em>text</em>",
    "<td>Apple, red</td>", "<figcaption>Caption</figcaption>", "/missing.md", "class=\"page-break\"",
    "<span class=\"math display\">", "[[raw]] $x$", "class=\"footnotes\"",
] {
    check(html.contains(needle), "html contains \(needle)")
}
let fmDoc = "---\ntitle: **Hi** #tag\ntags:\n  - a\n---\nBody text\n"
check(Frontmatter.range(in: fmDoc as NSString) == NSRange(location: 0, length: 39), "frontmatter range \(String(describing: Frontmatter.range(in: fmDoc as NSString)))")
check(Frontmatter.range(in: "---\na: 1\n...\nx" as NSString)?.length == 13, "frontmatter dots close")
check(Frontmatter.range(in: "---\na: 1\nno close\n" as NSString) == nil, "frontmatter unclosed")
check(Frontmatter.range(in: "\n---\na: 1\n---\n" as NSString) == nil, "frontmatter not at start")
check(Frontmatter.range(in: "Intro\n---\na\n---\n" as NSString) == nil, "frontmatter after text")
check(Frontmatter.range(in: "" as NSString) == nil, "frontmatter empty doc")
check(Frontmatter.range(in: "----\na\n---\n" as NSString) == nil, "frontmatter needs exact opener")
check(Frontmatter.strip(fmDoc) == "Body text\n", "frontmatter strip")
check(Frontmatter.strip("No front") == "No front", "frontmatter strip noop")

let fmScan = SyntaxScanner.scan(fmDoc as NSString)
check(fmScan.spans.contains { $0.kind == .markup && $0.range == NSRange(location: 0, length: 39) }, "scan frontmatter markup")
check(fmScan.spans.filter { $0.range.location < 39 }.count == 1, "scan nothing else in frontmatter \(fmScan.spans.filter { $0.range.location < 39 }.map(\.kind))")
check(SyntaxScanner.hashtags(in: fmDoc + "#real").sorted() == ["real"], "hashtags skip frontmatter")
check(SyntaxScanner.fencedBlocks(in: "---\na: ```\n---\n```\nx\n```\n" as NSString).blocks == [NSRange(location: 15, length: 10)], "fences start after frontmatter")

let fmHTML = MarkdownRenderer.html(fmDoc + "/inner.md\n", options: {
    var o = RenderOptions()
    o.loadBlock = { $0 == "inner.md" ? .markdown("---\nsecret: 1\n---\nInner *text*") : nil }
    return o
}())
check(fmHTML == "<p>Body text</p>\n<p>Inner <em>text</em></p>\n", "render hides frontmatter\n\(fmHTML)")
check(MarkdownRenderer.html("Intro\n---\n").contains("<h2"), "render setext without frontmatter")

check(Stats.count(.words, in: fmDoc) == 2, "stats skip frontmatter words \(Stats.count(.words, in: fmDoc))")
check(Stats.count(.characters, in: fmDoc) == 9, "stats skip frontmatter chars")
check(Stats.format(.words, document: "---\na b c\n---\none", selection: "") == "1 Word", "stats format frontmatter")

let outlined = SyntaxScanner.outline("# Title\n\nText\n#\n\n```\n# not\n```\n### Deep  \n" as NSString)
check(outlined.map { "\($0.level) \($0.title) \($0.location)" } == ["1 Title 0", "3 Deep 31"], "outline \(outlined)")

let combinedRoot = LibraryIndex().scan([URL(fileURLWithPath: "/var/empty"), URL(fileURLWithPath: "/var/empty/missing")], sort: .name)
check(combinedRoot.children.count == 2 && combinedRoot.children.allSatisfy(\.isFolder), "scan several roots")
if failures > 0 { print(html) }
print(failures == 0 ? "all core checks passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
