# Markdown Previewer for Godot 4

Live Markdown preview, right inside the Script Editor. Open a `.md` file and
it renders on the spot. Switch back to raw source or a side-by-side split
whenever you need to edit.

Requires **Godot 4.2+**.

---

## Overview

If your project keeps design notes, changelogs, or a `README.md` inside the
`res://` folder, you've probably opened them in the Script Editor and stared
at raw asterisks and pipe characters. This plugin renders that file properly
— headings, tables, checklists, code blocks — without leaving the editor or
reaching for an external app.

- Theme-aware: colors and fonts follow your editor's light/dark theme
- Copy button on every code block
- Comfortable reading width in Preview, full width in Split
- Live-updates as you type in Split view
- Nested lists, tables, task lists, blockquotes, fenced code, images
- Clickable `res://`, `http(s)://`, and `mailto:` links

---

## Installation

1. Copy `addons/markdown_previewer` into your project.
2. **Project → Project Settings → Plugins** → enable **Markdown Previewer**.
3. Open any `.md` file in the Script Editor.

Recognized extensions: `.md`, `.markdown`, `.mdown`, `.mkd`, `.mdwn`.

---

## Usage

`.md` files open in **Preview** by default (configurable below).

A **Markdown** menu appears in the same row as File / Edit / Search / Go To /
Debug whenever a Markdown file is focused:

| Item | What it does |
|---|---|
| Preview | Rendered Markdown, read-only |
| Edit Markdown | Raw source in the normal `CodeEdit` |
| Split View | Source on the left, live preview on the right |

**Shortcuts**

- `Alt+M` — cycle Preview → Edit → Split
- `Alt+Shift+M` — jump straight to Split View

The last mode you used — and the split width, if you were in Split — is
remembered per file for the rest of the editor session (this can be turned
off in settings).

In Split view, type in the left pane and the right pane updates as you go —
no manual refresh, no save required.

---

## Settings

**Project → Project Settings → Markdown Previewer**

| Setting | Default | What it does |
|---|---|---|
| Default view | Preview | View used the first time a Markdown file is opened |
| Remember view per file | On | Restore the last Preview / Edit / Split choice per file (this session) |
| Max content width | 960 | Reading-column width in Preview, in pixels. `0` fills the whole pane. Ignored in Split |
| Live preview | On | Update the preview as you type in Split view |

Settings apply immediately — no editor restart needed.

---

## Supported syntax

### Headings


# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
---
### Emphasis
**bold**, __also bold__
*italic*, _also italic_
***bold italic***
~~strikethrough~~
```md
**bold**, __also bold__
*italic*, _also italic_
***bold italic***
~~strikethrough~~
```
---
### Lists
- unordered
- nested:
  - item
  1. mixed numbering
  2. still works
1. ordered
2. item
```md
- unordered
- nested:
  - item
  1. mixed numbering
  2. still works
1. ordered
2. item
```
A line ending in two spaces inserts a hard line break.  
This line is written after two spaces on previous line.
---
### Task lists
- [ ] open
- [x] done
- [X] also done
```md
- [ ] open
- [x] done
- [X] also done
```
---
### Code
Inline: `node.name`.
```
`node.name`
```
```gdscript
func _ready() -> void:
	print("hi")
```
Fenced blocks show the language label and a one-click copy button. Syntax
highlighting is not applied — this is a documentation preview, not a code
editor.
````md
```gdscript
func _ready() -> void:
	print("hi")
```
````
Fenced blocks show the language label and a one-click copy button. Syntax
highlighting is not applied — this is a documentation preview, not a code
editor.

Tilde fences (`~~~`) work the same way.
---
### Blockquotes
> Quoted text
> can span lines
>
> > and nest

```md
> Quoted text
> can span lines
>
> > and nest
```
---
### Tables
| Name    | Type    | Default |
| ------- | ------- | ------- |
| `speed` | `float` | `200.0` |
| `jump`  | `float` | `400.0` |

```md
| Name    | Type    | Default |
| ------- | ------- | ------- |
| `speed` | `float` | `200.0` |
| `jump`  | `float` | `400.0` |
```

Column alignment (`:---`, `:---:`, `---:`) is parsed but always rendered
left-aligned — `RichTextLabel` tables don't support per-column alignment.
---
### Horizontal rules
```md
---
***
___
```
---

## Links and images

[Link to plugin.cfg](res://addons/markdown_previewer/plugin.cfg)  
[Godot Docs](https://docs.godotengine.org)  
<https://www.godotengine.org>  
![Alt](icon.svg)

```md
[Link to plugin.cfg](res://addons/markdown_previewer/plugin.cfg)  
[Godot Docs](https://docs.godotengine.org)  
<https://www.godotengine.org>  
![Alt](icon.svg "This is an icon")
```

Renders as (the two `res://` examples are placeholders and won't resolve here, but `Docs` and the 
autolink below are live):

- `res://` links jump straight to that file in the editor.
- `http://`, `https://`, and `mailto:` links open in your system browser.
- Local images (`res://`, `user://`, or a path relative to the Markdown file) render inline.
- Remote `http(s)://` images show as clickable links instead of inline images — the editor doesn't 
fetch remote images at edit time.
