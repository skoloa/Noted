# Noted

A Roblox Studio plugin that finds TODO, FIX, HACK and NOTE comments across your whole project and lists them in one panel.

> Status: Beta (v0.1.0)

## Features
- Finds notes in every script, live as you type
- Quick notes: write `-- N: your note`
- Search, tag filters, scope and a show-done toggle
- Hover to preview the code, click to open the script at that line
- Mark notes as done or ignore them
- Export to Output, Markdown or a ServerStorage module
- Alerts for new notes and a customizable tag list
- Dark and light theme

## Writing notes
```lua
-- N: why this design
-- N(alex, 2026-11-07)!: fix before release
```
`N` is short for NOTE. `T`, `F` and `H` work for TODO, FIX and HACK.
Format: `TAG(assignee, YYYY-MM-DD)!!: text` (assignee, date and `!` priority are optional).

## Install
1. Download `Noted.lua`.
2. In Roblox Studio, create a new Script, paste the code and right-click it → **Save as Local Plugin**.
3. Click **Noted** in the **Luau Dev Tools** toolbar.

## Feedback
Found a bug or have an idea? Open an issue: https://github.com/skoloa/Noted/issues

## License
MIT
