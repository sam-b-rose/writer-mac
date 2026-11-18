# Welcome

This is a plain text editor. You can't pick a font, drag a margin or configure a toolbar, because none of those exist. You write and the editor stays out of the way. #welcome

{{TOC}}

## Focus

Press **⌘D** to switch on Focus Mode. Everything except the sentence you are writing fades into the background. Change the scope to a whole paragraph in *View ▸ Focus*.

Typewriter Mode (**⌥⌘T**) keeps the line you are typing in the middle of the window.

One Sentence Per Line (*Writing* menu) starts a new line after each sentence you finish. It is a soft line break, so the paragraph stays one paragraph.

## Syntax and Style Check

Turn on parts of speech in *View ▸ Syntax*. The beautiful old house quietly stood on the hill, and its windows glowed warmly.

Style Check marks fillers, clichés and redundancies. It is actually very useful, and at the end of the day it will basically make your writing really much better. Our future plans include an added bonus.

## Authors

Paste with **⇧⌘V** and Writer marks the text as written by AI and colors it. Characters you type into it become yours. Authorship is saved at the end of the file, so it travels with the document.

## Markdown

- Lists continue when you press Return
- [x] Tasks can be checked with **⌘L**
- [ ] ==Highlights==, ~~strikethrough~~ and `inline code`
- Links to other notes: [[Shortcuts]]

> [!TIP]
> Callouts start with `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]`.

| Feature | Keys |
| ------- | :--: |
| Preview | ⌘R   |
| Library | ⇧⌘L  |

Press Tab inside a table to move between cells. The *Format ▸ Table* menu adds, moves, sorts and aligns rows and columns.

Write math in TeX: $e^{i\pi} + 1 = 0$, or as a block:

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

Footnotes keep asides out of the way.[^1]

## Content blocks

A line that starts with a slash embeds another file in the preview: Markdown, images, CSV tables or code.

/Shortcuts.md

[^1]: Add one with **⌃⌘F**.
