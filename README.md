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

Format: `TAG(assignee, YYYY-MM-DD)!!: text`
Assignee, date and `!` priority are optional.

## Install

Pick one of the three options.

### Option 1: Creator Store (easiest)
1. Open the plugin page: https://create.roblox.com/store/asset/131784033043435
2. Click **Get** / **Install**.
3. Restart Studio, then click **Noted** in the **Luau Dev Tools** toolbar.

### Option 2: Plugin file (`Noted.rbxmx`)
1. Download `Noted.rbxmx`.
2. In Roblox Studio, open the **Plugins** tab and click **Plugins Folder**.
3. Put `Noted.rbxmx` into that folder.
4. Restart Studio.
5. Click **Noted** in the **Luau Dev Tools** toolbar.

### Option 3: Source code (`Noted.luau`)
1. Download `Noted.luau` and copy its contents.
2. In Roblox Studio, insert a new **Script** and paste the code.
3. Right-click the script and choose **Save as Local Plugin**.
4. Click **Noted** in the **Luau Dev Tools** toolbar.

## Feedback

Found a bug or have an idea? Open an issue:
https://github.com/skoloa/Noted/issues

## License

GNU. See [LICENSE](LICENSE).
