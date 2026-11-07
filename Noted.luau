-- ============================================================
--  Noted | Roblox Studio plugin (Beta)
--  Finds TODO / FIX / HACK / NOTE comments across your project
-- ============================================================

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

-- ============================================================
--  Constants
-- ============================================================

local SETTINGS_KEY = "TodoNotes_v3_Settings"
local DONE_KEY = "TodoNotes_v3_Done"
local IGNORE_KEY = "TodoNotes_v3_Ignored"
local WELCOME_KEY = "Noted_Welcomed_v3"

local APP = {
	name = "Noted",
	version = "0.1.0",
	channel = "Beta",
	seenKey = "Noted_LastSeenVersion",
	announced = false,
	changelog = {
		{
			version = "0.1.0",
			channel = "Beta",
			date = "2026-11-07",
			items = {
				"First development build.",
				"Finds TODO, FIX, HACK and NOTE comments in every script.",
				"Quick notes: write N: and your text.",
				"Tag filters, search, scope and a show-done toggle.",
				"Code preview on hover and one-click open at the line.",
				"Mark notes as done or ignore them.",
				"Export to Output, Markdown or a ServerStorage module.",
				"Alerts for new notes and a customizable tag list.",
				"Animated loading screen while scripts are scanned.",
			},
		},
	},
}

local K = {}
K.PARSE_DEBOUNCE = 0.4
K.SEARCH_DEBOUNCE = 0.2
K.TOAST_TIME = 6
K.Run = game:GetService("RunService")
local PAGE_SIZE = 60
K.MAX_TAGS = 10
local TAG_PATTERN = "^[A-Z]+$"
local LOGO_ID = "rbxassetid://90592146337586"
K.LOGO_FALLBACK_ID = "rbxassetid://88117501552311"

local HEADER_H = 46
K.SEARCH_Y = 54
K.CHIPS_Y = 94
K.CONTROLS_Y = 126
local LIST_Y = 160
local FOOTER_H = 28
local PREVIEW_ROWS = 6
local PREVIEW_ROW_H = 17
local PREVIEW_H = 30 + PREVIEW_ROWS * PREVIEW_ROW_H
K.MIN_HEIGHT_FOR_PREVIEW = 520
local CARD_H = 66

local PRESET_COLORS = {
	{ 56, 150, 255 }, { 255, 99, 99 }, { 255, 176, 64 }, { 110, 207, 140 },
	{ 168, 130, 255 }, { 255, 122, 186 }, { 80, 212, 214 }, { 170, 176, 190 },
}

local DEFAULT_CFG = {
	tags = { "TODO", "FIX", "HACK", "NOTE" },
	colors = {
		TODO = { 56, 150, 255 },
		FIX = { 255, 99, 99 },
		HACK = { 255, 176, 64 },
		NOTE = { 110, 207, 140 },
	},
	alerts = { FIX = true },
	notify = true,
	preview = true,
	allowNoColon = true,
}

local SCOPES = {
	{ name = "All" },
	{ name = "Server", services = { "ServerScriptService", "ServerStorage" } },
	{ name = "Client", services = { "StarterPlayer", "StarterGui", "StarterPack", "ReplicatedFirst" } },
	{ name = "Shared", services = { "ReplicatedStorage", "Workspace", "Lighting" } },
}

local HELP_SECTIONS = {
	{
		title = "Write a note",
		body = "Type N: and your note anywhere in your code:",
		code = "-- N: why this design\n"
			.. "-- N(alex, 2026-11-07)!: fix before release\n\n"
			.. "--[[\nN: block comments work too\n]]",
	},
	{
		title = "Format",
		body = "N(assignee, YYYY-MM-DD)!!: text\n"
			.. "•  N is short for NOTE. T, F and H work too.\n"
			.. "•  Assignee and date are optional.\n"
			.. "•  ! or !! marks priority.",
	},
	{
		title = "Panel",
		body = "•  Click a card to open the script at that line.\n"
			.. "•  Hover a card to preview the code around it.\n"
			.. "•  Right-click for open, copy, done or ignore.\n"
			.. "•  The square on a card marks it done.\n"
			.. "•  Done and ignored notes stay hidden until Show done is on.\n"
			.. "•  Search matches text, file name and @assignee.\n"
			.. "•  Click a tag chip to show or hide that tag.\n"
			.. "•  Scope limits notes to a group of services.\n"
			.. "•  Sync re-reads every script in the place.",
	},
	{
		title = "Export",
		body = "Print to the Output window, copy as Markdown, or save to a ServerStorage module named TodoExport.",
	},
	{
		title = "Alerts",
		body = "A new note whose tag has alerts turned on lights up the footer. Click the footer to jump to it.",
	},
}

-- ============================================================
--  Fonts
-- ============================================================

local function ubuntu(weight)
	local ok, font = pcall(Font.fromName, "Ubuntu", weight)
	if ok and font then
		return font
	end
	return Font.fromEnum(Enum.Font.Gotham)
end

local FONT_REG = ubuntu(Enum.FontWeight.Regular)
local FONT_MED = ubuntu(Enum.FontWeight.Medium)
local FONT_BOLD = ubuntu(Enum.FontWeight.Bold)
local FONT_CODE = Font.fromEnum(Enum.Font.Code)

-- ============================================================
--  Palette (dark / light, follows the Studio theme)
-- ============================================================

local DARK = {
	bg = Color3.fromRGB(14, 16, 22),
	surface = Color3.fromRGB(22, 25, 33),
	surface2 = Color3.fromRGB(30, 34, 44),
	hover = Color3.fromRGB(38, 43, 56),
	border = Color3.fromRGB(44, 50, 64),
	text = Color3.fromRGB(232, 236, 244),
	subtext = Color3.fromRGB(134, 143, 163),
	accent = Color3.fromRGB(56, 150, 255),
	danger = Color3.fromRGB(255, 99, 99),
	white = Color3.new(1, 1, 1),
}
local LIGHT = {
	bg = Color3.fromRGB(246, 247, 250),
	surface = Color3.fromRGB(255, 255, 255),
	surface2 = Color3.fromRGB(234, 237, 244),
	hover = Color3.fromRGB(222, 227, 238),
	border = Color3.fromRGB(210, 215, 226),
	text = Color3.fromRGB(28, 32, 42),
	subtext = Color3.fromRGB(98, 106, 124),
	accent = Color3.fromRGB(0, 122, 214),
	danger = Color3.fromRGB(214, 56, 56),
	white = Color3.new(1, 1, 1),
}

local P = DARK
local themed = {}
local buttons = {}
local WHITE = Color3.new(1, 1, 1)

local function theme(obj, prop, key)
	table.insert(themed, { obj = obj, prop = prop, key = key })
	obj[prop] = P[key]
	return obj
end

-- ============================================================
--  State
-- ============================================================

local cfg
local doneSet, ignoredSet = {}, {}
local activeTags = {}
local index = {}
local watchers = {}
local pending = {}
local pendingToken = 0
local allEntries = {}
local lastShown = {}
local countsCache = {}
local scopeName = "All"
local scopeRoots = nil
local searchText = ""
local searchToken = 0
local showDone = false
local pageLimit = PAGE_SIZE
local initialized = false
local scanning = false
local scanProgress = ""
local scanFrac = 0
local footerStats = ""
local toastActive = false
local toastAction = nil
local toastToken = 0
local currentOverlay = nil

local widget, root, list, footer, footerLabel, progressBar
local previewFrame, previewRows, previewTitle
local chipScroll, searchBox, clearBtn, searchStroke
local chipButtons = {}
local helpOverlay, settingsOverlay, newsOverlay, welcomeOverlay
local popup, popupCatcher, copyModal, copyBox, copyTitle
local scopeBtn, doneBtn, exportBtn, previewToggle, syncBtn

local refreshUI, refreshControls, refreshFooter, render, rebuildAll, layout
local showToast, clearToast, notifyFresh, showPopup, closePopup, showCopy
local buildChips, buildSettings, buildHelp, buildNews, buildWelcome, setOverlay, showPreview, openAt, fullScan
local queueParse, flushPending, reparseAll, runExport, applyTheme
local renameTagFromSettings, removeTagFromSettings

-- ============================================================
--  Helpers
-- ============================================================

local function make(class, props)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function tween(obj, goal, time, style, direction)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
		goal
	)
	t:Play()
	return t
end

local function trim(s)
	return (string.match(s, "^%s*(.-)%s*$"))
end

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = deepCopy(v)
	end
	return out
end

local function hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 4294967296
	end
	return string.format("%08x", math.floor(h))
end

local function decode(raw, default)
	if type(raw) ~= "string" then
		return default
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and type(data) == "table" then
		return data
	end
	return default
end

local function toColor(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function measure(text, size, font, width)
	local ok, v = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(width, 100000))
	if ok then
		return v.Y
	end
	return size * 1.4
end

-- Destroys every child except layout helpers and decorations (corner, stroke, scale)
local function clearChildren(parent)
	for _, c in ipairs(parent:GetChildren()) do
		if not c:IsA("UILayout") and not c:IsA("UIPadding")
			and not c:IsA("UICorner") and not c:IsA("UIStroke") and not c:IsA("UIScale") then
			c:Destroy()
		end
	end
end

local function getSetting(key)
	local ok, value = pcall(plugin.GetSetting, plugin, key)
	if ok then
		return value
	end
	return nil
end

local function setSetting(key, value)
	pcall(plugin.SetSetting, plugin, key, value)
end

-- ============================================================
--  Buttons
-- ============================================================

local function styleButton(b, bg, fg)
	b:SetAttribute("Rest", bg)
	b.BackgroundColor3 = bg
	b.TextColor3 = fg
end

local function bindHover(b)
	local scale = make("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		tween(b, { BackgroundColor3 = b:GetAttribute("Rest"):Lerp(WHITE, 0.1) }, 0.15)
	end)
	b.MouseLeave:Connect(function()
		tween(b, { BackgroundColor3 = b:GetAttribute("Rest") }, 0.2)
	end)
	b.MouseButton1Down:Connect(function()
		tween(scale, { Scale = 0.96 }, 0.08)
	end)
	b.MouseButton1Up:Connect(function()
		tween(scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
	end)
end

local function button(parent, text, size, pos, bg, fg, font)
	local b = make("TextButton", {
		Size = size,
		Position = pos or UDim2.new(),
		BackgroundColor3 = bg,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		FontFace = font or FONT_MED,
		TextSize = 12,
		TextColor3 = fg,
		Parent = parent,
	})
	corner(b, 6)
	b:SetAttribute("Rest", bg)
	bindHover(b)
	return b
end

local function themedButton(parent, text, size, pos, bgKey, fgKey)
	local b = button(parent, text, size, pos, P[bgKey], P[fgKey or "white"])
	table.insert(buttons, { btn = b, bg = bgKey, fg = fgKey or "white" })
	return b
end

-- Segmented pill: one sliding highlight follows the hovered button
APP.segs = {}
APP.intro = {}
APP.group = function(parent, size, pos, defs, delay)
	-- centered anchor so the pop-in scales from the middle
	local pill = theme(make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = size,
		Position = UDim2.new(
			pos.X.Scale + size.X.Scale / 2, pos.X.Offset + size.X.Offset / 2,
			pos.Y.Scale + size.Y.Scale / 2, pos.Y.Offset + size.Y.Offset / 2
		),
		BorderSizePixel = 0,
		Parent = parent,
	}), "BackgroundColor3", "surface2")
	corner(pill, 14)
	local stroke = theme(make("UIStroke", { Thickness = 1, Transparency = 0.5, Parent = pill }), "Color", "border")
	local pscale = make("UIScale", { Parent = pill })

	local indicator = theme(make("Frame", {
		Size = UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = pill,
	}), "BackgroundColor3", "accent")
	corner(indicator, 11)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 210, 236)),
		Rotation = 90,
		Parent = indicator,
	})
	local iscale = make("UIScale", { Parent = indicator })

	-- two soft halo layers behind the highlight
	local glowA = theme(make("Frame", {
		Size = UDim2.new(), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0, Parent = pill,
	}), "BackgroundColor3", "accent")
	corner(glowA, 16)
	local glowB = theme(make("Frame", {
		Size = UDim2.new(), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0, Parent = pill,
	}), "BackgroundColor3", "accent")
	corner(glowB, 20)
	local function pad(u, d)
		return UDim2.new(u.X.Scale, u.X.Offset + d, u.Y.Scale, u.Y.Offset + d)
	end
	local function place(b, animate)
		local goalA = { Position = pad(b.Position, -5), Size = pad(b.Size, 10) }
		local goalB = { Position = pad(b.Position, -9), Size = pad(b.Size, 18) }
		if animate then
			tween(indicator, { Position = b.Position, Size = b.Size }, 0.3, Enum.EasingStyle.Quint)
			tween(glowA, goalA, 0.3, Enum.EasingStyle.Quint)
			tween(glowB, goalB, 0.3, Enum.EasingStyle.Quint)
		else
			indicator.Position, indicator.Size = b.Position, b.Size
			glowA.Position, glowA.Size = goalA.Position, goalA.Size
			glowB.Position, glowB.Size = goalB.Position, goalB.Size
		end
	end

	local shown, token = false, 0
	local out = {}
	for i, d in ipairs(defs) do
		local b = make("TextButton", {
			Size = d.size,
			Position = d.pos,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = d.text,
			FontFace = FONT_BOLD,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 2,
			Parent = pill,
		})
		local sg = { btn = b, key = d.key or "text" }
		table.insert(APP.segs, sg)
		b.TextColor3 = P[sg.key]
		b:SetAttribute("RestText", P[sg.key])

		b.MouseEnter:Connect(function()
			token += 1
			if not shown then
				shown = true
				place(b, false)
				tween(indicator, { BackgroundTransparency = 0 }, 0.2)
				tween(glowA, { BackgroundTransparency = 0.76 }, 0.3)
				tween(glowB, { BackgroundTransparency = 0.9 }, 0.3)
			else
				place(b, true)
			end
			tween(b, { TextColor3 = P.white }, 0.2)
		end)
		b.MouseLeave:Connect(function()
			tween(b, { TextColor3 = b:GetAttribute("RestText") }, 0.25)
			token += 1
			local mine = token
			task.delay(0.1, function()
				if mine == token and shown then
					shown = false
					tween(indicator, { BackgroundTransparency = 1 }, 0.25)
					tween(glowA, { BackgroundTransparency = 1 }, 0.25)
					tween(glowB, { BackgroundTransparency = 1 }, 0.25)
				end
			end)
		end)
		b.MouseButton1Down:Connect(function()
			tween(iscale, { Scale = 0.92 }, 0.08)
		end)
		b.MouseButton1Up:Connect(function()
			tween(iscale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
		end)
		out[i] = b
	end

	table.insert(APP.intro, { pill = pill, scale = pscale, stroke = stroke, buttons = out, delay = delay or 0 })
	return unpack(out)
end

-- Replays the entrance animation: groups pop in, then the tag chips one by one
APP.playIntro = function()
	for _, it in ipairs(APP.intro) do
		if it.pill.Parent then
			it.scale.Scale = 0.85
			it.pill.BackgroundTransparency = 1
			it.stroke.Transparency = 1
			for _, b in ipairs(it.buttons) do
				b.TextTransparency = 1
			end
			task.delay(it.delay, function()
				if not it.pill.Parent then
					return
				end
				tween(it.scale, { Scale = 1 }, 0.65, Enum.EasingStyle.Back)
				tween(it.pill, { BackgroundTransparency = 0 }, 0.4)
				tween(it.stroke, { Transparency = 0.5 }, 0.4)
				for _, b in ipairs(it.buttons) do
					tween(b, { TextTransparency = 0 }, 0.5)
				end
			end)
		end
	end

	for i, tag in ipairs(cfg.tags) do
		local chip = chipButtons[tag]
		if chip and chip.Parent then
			local sc = chip:FindFirstChild("PopScale") or make("UIScale", { Name = "PopScale", Parent = chip })
			sc.Scale = 0.5
			chip.BackgroundTransparency = 1
			chip.TextTransparency = 1
			task.delay(0.2 + i * 0.06, function()
				if not chip.Parent then
					return
				end
				tween(sc, { Scale = 1 }, 0.55, Enum.EasingStyle.Back)
				tween(chip, { BackgroundTransparency = 0, TextTransparency = 0 }, 0.35)
			end)
		end
	end
end

APP.setSegKey = function(btn, key)
	for _, sg in ipairs(APP.segs) do
		if sg.btn == btn then
			sg.key = key
			btn:SetAttribute("RestText", P[key])
			btn.TextColor3 = P[key]
		end
	end
end

-- ============================================================
--  Settings and sets (persistence)
-- ============================================================

cfg = deepCopy(DEFAULT_CFG)
for k, v in pairs(decode(getSetting(SETTINGS_KEY), {})) do
	cfg[k] = v
end
if type(cfg.tags) ~= "table" or #cfg.tags == 0 then
	cfg.tags = deepCopy(DEFAULT_CFG.tags)
end
if type(cfg.colors) ~= "table" then
	cfg.colors = deepCopy(DEFAULT_CFG.colors)
end
if type(cfg.alerts) ~= "table" then
	cfg.alerts = deepCopy(DEFAULT_CFG.alerts)
end

local function saveCfg()
	setSetting(SETTINGS_KEY, HttpService:JSONEncode(cfg))
end

local function loadSet(key)
	local set = {}
	for _, k in ipairs(decode(getSetting(key), {})) do
		set[k] = true
	end
	return set
end

local function saveSet(key, set)
	local arr = {}
	for k in pairs(set) do
		table.insert(arr, k)
	end
	setSetting(key, HttpService:JSONEncode(arr))
end

doneSet = loadSet(DONE_KEY)
ignoredSet = loadSet(IGNORE_KEY)

-- ============================================================
--  Tag helpers
-- ============================================================

local function isTag(tag)
	for _, t in ipairs(cfg.tags) do
		if t == tag then
			return true
		end
	end
	return false
end

local function tagIndex(tag)
	for i, t in ipairs(cfg.tags) do
		if t == tag then
			return i
		end
	end
	return 99
end

local function tagColor(tag)
	local c = cfg.colors[tag]
	if c then
		return toColor(c)
	end
	return Color3.fromRGB(150, 156, 170)
end

local function syncActiveTags()
	for _, t in ipairs(cfg.tags) do
		if activeTags[t] == nil then
			activeTags[t] = true
		end
	end
end
syncActiveTags()

local function ageDays(date)
	local y, m, d = string.match(date, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then
		return nil
	end
	local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
	return math.floor((os.time() - t) / 86400)
end

local function ageText(date)
	local days = ageDays(date)
	if not days then
		return nil
	end
	if days < 0 then
		return "future"
	elseif days == 0 then
		return "today"
	end
	return days .. "d old"
end

-- ============================================================
--  Parsing
-- ============================================================

local function parseTagText(text)
	local tagRaw, rest = string.match(text, "^%s*(%a+)(.*)$")
	if not tagRaw then
		return nil
	end
	local tag = string.upper(tagRaw)
	local short = false
	if not isTag(tag) then
		-- one capital letter + colon is enough: N: -> NOTE, T: -> TODO ...
		local full = nil
		if #tagRaw == 1 and tagRaw == tag then
			for _, t in ipairs(cfg.tags) do
				if string.sub(t, 1, 1) == tag then
					full = t
					break
				end
			end
		end
		if not full then
			return nil
		end
		tag = full
		short = true
	end

	local meta, bangs, body
	meta, bangs, body = string.match(rest, "^%s*%(([^%)]*)%)%s*(!*)%s*:%s*(.-)%s*$")
	if not meta then
		bangs, body = string.match(rest, "^%s*(!*)%s*:%s*(.-)%s*$")
		if bangs then
			meta = ""
		end
	end
	if not meta then
		-- the short form always needs its colon
		if short or not cfg.allowNoColon or tagRaw ~= tag then
			return nil
		end
		meta, bangs, body = string.match(rest, "^%s*%(([^%)]*)%)%s*(!*)%s*(.-)%s*$")
		if not meta then
			meta = ""
			bangs, body = string.match(rest, "^%s*(!*)%s*(.-)%s*$")
		end
	end

	bangs = bangs or ""
	body = body or ""

	local parts = {}
	for part in string.gmatch(meta, "[^,]+") do
		table.insert(parts, trim(part))
	end

	return {
		tag = tag,
		text = body ~= "" and body or "(no description)",
		assignee = parts[1] or "",
		date = parts[2] or "",
		bangs = #bangs,
	}
end

local function commentBodyOf(line)
	local p = string.find(line, "--", 1, true)
	if not p then
		return nil, nil
	end
	local before = string.sub(line, 1, p - 1)
	local _, dq = string.gsub(before, '"', "")
	local _, sq = string.gsub(before, "'", "")
	if dq % 2 == 1 or sq % 2 == 1 then
		return nil, nil
	end
	return p, string.sub(line, p + 2)
end

local function parseSource(script, src)
	local path = script:GetFullName()
	local lines = string.split(src, "\n")
	local out, counter = {}, {}
	local inBlock, closer = false, nil

	for i, raw in ipairs(lines) do
		local line = string.gsub(raw, "\r", "")
		local body = nil

		if inBlock then
			local cpos = string.find(line, closer, 1, true)
			if cpos then
				body = string.sub(line, 1, cpos - 1)
				inBlock = false
			else
				body = line
			end
		else
			local p, after = commentBodyOf(line)
			if p then
				local eqs = string.match(after, "^%[(=*)%[")
				if eqs then
					closer = "]" .. eqs .. "]"
					local content = string.sub(after, #eqs + 3)
					local cpos = string.find(content, closer, 1, true)
					if cpos then
						body = string.sub(content, 1, cpos - 1)
					else
						inBlock = true
						body = content
					end
				else
					body = after
				end
			end
		end

		if body then
			local info = parseTagText(body)
			if info then
				local base = info.tag .. "|" .. info.text
				counter[base] = (counter[base] or 0) + 1
				info.line = i
				info.script = script
				info.path = path
				info.lines = lines
				info.key = path .. "|" .. hash(base .. "#" .. counter[base])
				table.insert(out, info)
			end
		end
	end

	return out
end

-- ============================================================
--  Index: reading scripts
-- ============================================================

local function readSource(script)
	local ok, src = pcall(ScriptEditorService.GetEditorSource, ScriptEditorService, script)
	if ok and type(src) == "string" and src ~= "" then
		return src
	end
	ok, src = pcall(function()
		return script.Source
	end)
	if ok and type(src) == "string" then
		return src
	end
	return nil
end

local function shouldSkip(script)
	return script.Name == "TodoExport" and script.Parent == ServerStorage
end

local function updateScript(script, cachedSrc)
	if not script:IsDescendantOf(game) or shouldSkip(script) then
		index[script] = nil
		return {}
	end

	local src = cachedSrc or readSource(script) or ""
	local old = index[script]
	local oldKeys = {}
	if old then
		for _, e in ipairs(old.entries) do
			oldKeys[e.key] = true
		end
	end

	local entries = {}
	if string.find(src, "--", 1, true) then
		entries = parseSource(script, src)
	end
	index[script] = { entries = entries, src = src }

	local fresh = {}
	for _, e in ipairs(entries) do
		if not oldKeys[e.key] then
			table.insert(fresh, e)
		end
	end
	return fresh
end

reparseAll = function()
	for script, rec in pairs(index) do
		local ok, entries = pcall(parseSource, script, rec.src)
		if ok then
			rec.entries = entries
		end
	end
end

rebuildAll = function()
	table.clear(allEntries)
	for _, rec in pairs(index) do
		for _, e in ipairs(rec.entries) do
			table.insert(allEntries, e)
		end
	end
	table.sort(allEntries, function(a, b)
		local ta, tb = tagIndex(a.tag), tagIndex(b.tag)
		if ta ~= tb then
			return ta < tb
		end
		if a.bangs ~= b.bangs then
			return a.bangs > b.bangs
		end
		if a.path ~= b.path then
			return a.path < b.path
		end
		return a.line < b.line
	end)
end

-- ============================================================
--  Scope
-- ============================================================

local function setScopeName(name)
	scopeName = name
	scopeRoots = nil
	for _, s in ipairs(SCOPES) do
		if s.name == name and s.services then
			scopeRoots = {}
			for _, svcName in ipairs(s.services) do
				local svc = game:FindService(svcName)
				if svc then
					table.insert(scopeRoots, svc)
				end
			end
		end
	end
end
setScopeName("All")

local function inScope(script)
	if not scopeRoots then
		return true
	end
	for _, svc in ipairs(scopeRoots) do
		if script:IsDescendantOf(svc) then
			return true
		end
	end
	return false
end

-- ============================================================
--  Live updates
-- ============================================================

local function watch(script)
	if watchers[script] then
		return
	end
	local ok, conn = pcall(function()
		return script:GetPropertyChangedSignal("Source"):Connect(function()
			queueParse(script)
		end)
	end)
	if ok then
		watchers[script] = conn
	end
end

local function unwatch(script)
	local conn = watchers[script]
	if conn then
		conn:Disconnect()
	end
	watchers[script] = nil
end

queueParse = function(script)
	pending[script] = true
	pendingToken += 1
	local token = pendingToken
	task.delay(K.PARSE_DEBOUNCE, function()
		if token == pendingToken then
			flushPending()
		end
	end)
end

flushPending = function()
	local batch = {}
	for script in pairs(pending) do
		table.insert(batch, script)
	end
	table.clear(pending)

	local fresh = {}
	for _, script in ipairs(batch) do
		local ok, res = pcall(updateScript, script)
		if ok then
			for _, e in ipairs(res) do
				table.insert(fresh, e)
			end
		else
			warn("[Noted] parse failed: " .. tostring(res))
		end
		if not script:IsDescendantOf(game) then
			unwatch(script)
		end
	end

	rebuildAll()
	if #fresh > 0 then
		notifyFresh(fresh)
	end
	refreshUI(false)
end

-- ============================================================
--  Open in editor
-- ============================================================

openAt = function(e)
	local ok, err = pcall(function()
		local doc = ScriptEditorService:OpenScriptDocumentAsync(e.script)
		doc:SetSelection(e.line, 1, e.line, 1)
	end)
	if not ok then
		local ok2 = pcall(plugin.OpenScript, plugin, e.script, e.line)
		if not ok2 then
			warn("[Noted] Could not open " .. e.path .. " (" .. tostring(err) .. ")")
		end
	end
end

notifyFresh = function(fresh)
	if not cfg.notify then
		return
	end
	local alerts = {}
	for _, e in ipairs(fresh) do
		if cfg.alerts[e.tag] then
			table.insert(alerts, e)
		end
	end
	if #alerts == 0 then
		return
	end
	local first = alerts[1]
	local msg
	if #alerts == 1 then
		msg = string.format("New %s in %s : %d   (click to open)", first.tag, first.script.Name, first.line)
	else
		msg = string.format("%d new alerts   (click to open the first)", #alerts)
	end
	showToast(msg, tagColor(first.tag), function()
		openAt(first)
	end)
end

-- ============================================================
--  Full scan (with loading panel)
-- ============================================================

fullScan = function()
	if scanning then
		return
	end
	scanning = true
	initialized = true
	scanFrac = 0
	APP.scan = { seen = 0, total = 0, found = 0 }
	if APP.loader then
		APP.loader.disp = 0
	end
	syncBtn.Text = "..."
	table.clear(pending)
	table.clear(index)
	APP.updateLoader()

	local descendants = game:GetDescendants()
	local total = 0
	for _, d in ipairs(descendants) do
		if d:IsA("LuaSourceContainer") then
			total += 1
		end
	end
	APP.scan.total = total

	local started = os.clock()
	local lastYield = os.clock()
	local seen = 0
	local ok, err = pcall(function()
		for _, desc in ipairs(descendants) do
			if desc:IsA("LuaSourceContainer") then
				watch(desc)
				local ok2, res = pcall(updateScript, desc)
				if ok2 then
					APP.scan.found += #res
				else
					warn("[Noted] scan error in " .. desc.Name .. ": " .. tostring(res))
				end
				seen += 1
				APP.scan.seen = seen
				scanFrac = total > 0 and (seen / total) or 1
				if os.clock() - lastYield > 0.03 then
					scanProgress = string.format("Scanning %d / %d scripts...", seen, total)
					refreshFooter()
					task.wait()
					lastYield = os.clock()
				end
			end
		end
	end)
	if not ok then
		warn("[Noted] scan failed: " .. tostring(err))
	end

	-- keep the loader on screen long enough to be seen
	scanFrac = 1
	while os.clock() - started < 1.1 do
		task.wait()
	end

	scanning = false
	scanProgress = ""
	scanFrac = 0
	syncBtn.Text = "Sync"
	rebuildAll()
	refreshUI(true)
	refreshFooter()
	APP.updateLoader()
end

game.DescendantAdded:Connect(function(desc)
	if desc:IsA("LuaSourceContainer") then
		watch(desc)
		queueParse(desc)
	end
end)

game.DescendantRemoving:Connect(function(desc)
	if desc:IsA("LuaSourceContainer") then
		unwatch(desc)
		queueParse(desc)
	end
end)

-- ============================================================
--  UI: root widget and header
-- ============================================================

local toolbar = plugin:CreateToolbar("Luau Dev Tools")
local toggleBtn = toolbar:CreateButton(
	"Noted",
	"Show TODO / FIX / HACK / NOTE comments in your project",
	LOGO_ID
)

widget = plugin:CreateDockWidgetPluginGui(
	"TodoNotes_v3",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 330, 620, 300, 420)
)
widget.Title = "Noted"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

root = theme(make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = widget,
}), "BackgroundColor3", "bg")

-- Header: fixed-width button group on the right, title takes the rest
local header = make("Frame", {
	Size = UDim2.new(1, 0, 0, HEADER_H),
	BackgroundTransparency = 1,
	Parent = root,
})
local logoBtn = make("ImageButton", {
	Name = "Logo",
	Size = UDim2.fromOffset(38, 38),
	Position = UDim2.fromOffset(10, 4),
	BackgroundTransparency = 1,
	Image = LOGO_ID,
	ScaleType = Enum.ScaleType.Fit,
	AutoButtonColor = false,
	Parent = header,
})
task.spawn(function()
	local waited = 0
	while not logoBtn.IsLoaded and waited < 4 do
		task.wait(0.25)
		waited += 0.25
	end
	if not logoBtn.IsLoaded then
		logoBtn.Image = K.LOGO_FALLBACK_ID
	end
end)
-- The logo itself stays still; clicking it opens What's new with a reveal animation
logoBtn.MouseButton1Click:Connect(function()
	if currentOverlay == "news" then
		setOverlay(nil)
	else
		APP.openNewsFromLogo(logoBtn)
	end
end)

local headerRight = make("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(168, 28),
	BackgroundTransparency = 1,
	Parent = header,
})

local helpBtn, settingsBtn
helpBtn, settingsBtn, syncBtn = APP.group(headerRight, UDim2.fromScale(1, 1), UDim2.new(), {
	{ text = "Help", size = UDim2.fromOffset(44, 22), pos = UDim2.fromOffset(4, 3) },
	{ text = "Settings", size = UDim2.fromOffset(68, 22), pos = UDim2.fromOffset(48, 3) },
	{ text = "Sync", size = UDim2.fromOffset(48, 22), pos = UDim2.fromOffset(116, 3), key = "accent" },
}, 0)

theme(make("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.new(0, 0, 0, HEADER_H - 1),
	BorderSizePixel = 0,
	Parent = root,
}), "BackgroundColor3", "border")

-- Search
local searchFrame = theme(make("Frame", {
	Size = UDim2.new(1, -16, 0, 32),
	Position = UDim2.fromOffset(8, K.SEARCH_Y),
	BorderSizePixel = 0,
	Parent = root,
}), "BackgroundColor3", "surface")
corner(searchFrame, 8)
searchStroke = theme(make("UIStroke", { Thickness = 1, Parent = searchFrame }), "Color", "border")

searchBox = make("TextBox", {
	Size = UDim2.new(1, -44, 1, 0),
	Position = UDim2.fromOffset(12, 0),
	BackgroundTransparency = 1,
	PlaceholderText = "Search text, file or @assignee",
	Text = "",
	FontFace = FONT_REG,
	TextSize = 13,
	ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = searchFrame,
})
theme(searchBox, "TextColor3", "text")
theme(searchBox, "PlaceholderColor3", "subtext")

clearBtn = themedButton(searchFrame, "x", UDim2.fromOffset(20, 20), UDim2.new(1, -28, 0.5, -10), "surface2", "subtext")
clearBtn.Visible = false

searchBox.Focused:Connect(function()
	tween(searchStroke, { Color = P.accent }, 0.2)
end)
searchBox.FocusLost:Connect(function()
	tween(searchStroke, { Color = P.border }, 0.2)
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	clearBtn.Visible = searchBox.Text ~= ""
	searchToken += 1
	local token = searchToken
	task.delay(K.SEARCH_DEBOUNCE, function()
		if token ~= searchToken then
			return
		end
		local q = string.lower(trim(searchBox.Text))
		if string.sub(q, 1, 1) == "@" then
			q = string.sub(q, 2)
		end
		searchText = q
		pageLimit = PAGE_SIZE
		refreshUI(true)
	end)
end)
clearBtn.MouseButton1Click:Connect(function()
	searchBox.Text = ""
end)

-- Tag chips
chipScroll = make("ScrollingFrame", {
	Size = UDim2.new(1, -16, 0, 26),
	Position = UDim2.fromOffset(8, K.CHIPS_Y),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	Parent = root,
})
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = chipScroll,
})

buildChips = function()
	clearChildren(chipScroll)
	table.clear(chipButtons)
	for i, tag in ipairs(cfg.tags) do
		local chip = make("TextButton", {
			Name = tag,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = tag,
			FontFace = FONT_BOLD,
			TextSize = 11,
			TextColor3 = P.white,
			BackgroundColor3 = P.surface2,
			LayoutOrder = i,
			Parent = chipScroll,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11), Parent = chip })
		corner(chip, 12)
		chip.MouseButton1Click:Connect(function()
			activeTags[tag] = not activeTags[tag]
			pageLimit = PAGE_SIZE
			refreshUI(true)
		end)
		chipButtons[tag] = chip
	end
	refreshControls()
end

-- Controls row: three equal buttons with explicit positions, 6px gaps, never overlapping
local function third(col)
	return UDim2.new(1 / 3, -6, 1, -6), UDim2.new((col - 1) / 3, 3, 0, 3)
end
do
	local s1, p1 = third(1)
	local s2, p2 = third(2)
	local s3, p3 = third(3)
	scopeBtn, doneBtn, exportBtn = APP.group(root, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, K.CONTROLS_Y), {
		{ text = "Scope: All", size = s1, pos = p1 },
		{ text = "Show done", size = s2, pos = p2 },
		{ text = "Export", size = s3, pos = p3, key = "accent" },
	}, 0.1)
end

-- Card list
list = theme(make("ScrollingFrame", {
	Position = UDim2.fromOffset(8, LIST_Y),
	Size = UDim2.new(1, -16, 1, -(LIST_Y + FOOTER_H + 6)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = root,
}), "ScrollBarImageColor3", "border")
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4), Parent = list })

-- Preview panel
previewFrame = theme(make("Frame", {
	Size = UDim2.new(1, -16, 0, PREVIEW_H),
	Position = UDim2.new(0, 8, 1, -(FOOTER_H + 6 + PREVIEW_H)),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = root,
}), "BackgroundColor3", "surface")
corner(previewFrame, 8)
theme(make("UIStroke", { Thickness = 1, Parent = previewFrame }), "Color", "border")

previewTitle = theme(make("TextLabel", {
	Size = UDim2.new(1, -44, 0, 22),
	Position = UDim2.fromOffset(10, 2),
	BackgroundTransparency = 1,
	Text = "Hover a note to preview its code",
	FontFace = FONT_MED,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = previewFrame,
}), "TextColor3", "subtext")

local previewClose = themedButton(previewFrame, "x", UDim2.fromOffset(20, 20), UDim2.new(1, -26, 0, 3), "surface2", "subtext")
previewRows = make("Frame", {
	Size = UDim2.new(1, -12, 0, PREVIEW_ROWS * PREVIEW_ROW_H),
	Position = UDim2.fromOffset(6, 26),
	BackgroundTransparency = 1,
	Parent = previewFrame,
})
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = previewRows })

previewClose.MouseButton1Click:Connect(function()
	cfg.preview = false
	saveCfg()
	layout()
	refreshControls()
end)

-- Footer
footer = theme(make("TextButton", {
	Size = UDim2.new(1, 0, 0, FOOTER_H),
	Position = UDim2.new(0, 0, 1, -FOOTER_H),
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Parent = root,
}), "BackgroundColor3", "surface")
theme(make("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	BorderSizePixel = 0,
	Parent = footer,
}), "BackgroundColor3", "border")

-- Thin progress bar along the top edge of the footer (visible while scanning)
progressBar = theme(make("Frame", {
	Size = UDim2.new(0, 0, 0, 2),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 2,
	Parent = footer,
}), "BackgroundColor3", "accent")

footerLabel = theme(make("TextLabel", {
	Size = UDim2.new(1, -92, 1, 0),
	Position = UDim2.fromOffset(10, 0),
	BackgroundTransparency = 1,
	Text = "",
	FontFace = FONT_REG,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = footer,
}), "TextColor3", "subtext")

previewToggle = themedButton(footer, "Preview", UDim2.fromOffset(64, 20), UDim2.new(1, -72, 0.5, -10), "surface2", "text")

layout = function()
	local showPrev = currentOverlay == nil and cfg.preview and root.AbsoluteSize.Y >= K.MIN_HEIGHT_FOR_PREVIEW
	previewFrame.Visible = showPrev
	local bottom = FOOTER_H + 6 + (showPrev and (PREVIEW_H + 6) or 0)
	list.Size = UDim2.new(1, -16, 1, -(LIST_Y + bottom))
end

refreshFooter = function()
	if scanning then
		progressBar.Visible = true
		progressBar.Size = UDim2.new(math.clamp(scanFrac, 0, 1), 0, 0, 2)
	else
		progressBar.Visible = false
	end
	if toastActive then
		return
	end
	if scanning then
		footerLabel.Text = scanProgress ~= "" and scanProgress or "Scanning scripts..."
	else
		footerLabel.Text = footerStats
	end
end

showToast = function(msg, color, action)
	toastAction = action
	toastActive = true
	toastToken += 1
	local token = toastToken
	footerLabel.Text = msg
	footerLabel.TextTransparency = 1
	tween(footerLabel, { TextTransparency = 0 }, 0.3)
	tween(footer, { BackgroundColor3 = color }, 0.3)
	tween(footerLabel, { TextColor3 = P.white }, 0.3)
	task.delay(K.TOAST_TIME, function()
		if token == toastToken then
			clearToast()
		end
	end)
end

clearToast = function()
	toastActive = false
	toastAction = nil
	tween(footer, { BackgroundColor3 = P.surface }, 0.3)
	tween(footerLabel, { TextColor3 = P.subtext }, 0.3)
	refreshFooter()
end

footer.MouseButton1Click:Connect(function()
	if toastActive and toastAction then
		local action = toastAction
		clearToast()
		action()
	end
end)

-- Popup menu
popupCatcher = make("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	ZIndex = 20,
	Visible = false,
	Parent = root,
})

popup = theme(make("Frame", {
	Size = UDim2.fromOffset(190, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BorderSizePixel = 0,
	ZIndex = 21,
	Visible = false,
	Parent = root,
}), "BackgroundColor3", "surface2")
corner(popup, 8)
theme(make("UIStroke", { Thickness = 1, Parent = popup }), "Color", "border")
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = popup })
make("UIPadding", {
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 4),
	Parent = popup,
})

closePopup = function()
	popup.Visible = false
	popupCatcher.Visible = false
end
popupCatcher.MouseButton1Click:Connect(closePopup)
popupCatcher.MouseButton2Click:Connect(closePopup)

showPopup = function(x, y, items)
	clearChildren(popup)
	for i, item in ipairs(items) do
		local b = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = P.hover,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = item.label,
			FontFace = FONT_REG,
			TextSize = 12,
			TextColor3 = item.danger and P.danger or P.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			ZIndex = 21,
			Parent = popup,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = b })
		corner(b, 5)
		b.MouseEnter:Connect(function()
			tween(b, { BackgroundTransparency = 0 }, 0.12)
		end)
		b.MouseLeave:Connect(function()
			tween(b, { BackgroundTransparency = 1 }, 0.15)
		end)
		b.MouseButton1Click:Connect(function()
			closePopup()
			item.fn()
		end)
	end

	local w = 190
	local h = #items * 28 + 8
	local px = math.clamp(x, 4, math.max(4, root.AbsoluteSize.X - w - 4))
	local py = math.clamp(y, 4, math.max(4, root.AbsoluteSize.Y - h - FOOTER_H - 4))
	popup.Position = UDim2.fromOffset(px, py)

	local ps = popup:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = popup })
	ps.Scale = 0.86
	tween(ps, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)

	popupCatcher.Visible = true
	popup.Visible = true
end

local function menuBelow(btn)
	return btn.AbsolutePosition.X - root.AbsolutePosition.X,
		btn.AbsolutePosition.Y - root.AbsolutePosition.Y + btn.AbsoluteSize.Y + 4
end

-- Copy modal (plugins cannot write the clipboard, so the text is selected for Ctrl+C)
copyModal = theme(make("Frame", {
	Size = UDim2.new(1, -24, 0, 176),
	Position = UDim2.new(0, 12, 0.5, -88),
	BorderSizePixel = 0,
	ZIndex = 30,
	Visible = false,
	Parent = root,
}), "BackgroundColor3", "surface")
corner(copyModal, 10)
theme(make("UIStroke", { Thickness = 1, Parent = copyModal }), "Color", "border")

copyTitle = theme(make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 22),
	Position = UDim2.fromOffset(12, 10),
	BackgroundTransparency = 1,
	Text = "Copy",
	FontFace = FONT_BOLD,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 30,
	Parent = copyModal,
}), "TextColor3", "text")

copyBox = theme(make("TextBox", {
	Size = UDim2.new(1, -24, 0, 84),
	Position = UDim2.fromOffset(12, 36),
	BackgroundColor3 = P.surface2,
	BorderSizePixel = 0,
	MultiLine = true,
	TextWrapped = true,
	ClearTextOnFocus = false,
	TextEditable = true,
	FontFace = FONT_CODE,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
	ZIndex = 30,
	Parent = copyModal,
}), "TextColor3", "text")
corner(copyBox, 6)

theme(make("TextLabel", {
	Size = UDim2.new(1, -120, 0, 26),
	Position = UDim2.new(0, 12, 1, -36),
	BackgroundTransparency = 1,
	Text = "Press Ctrl+C to copy, then Close.",
	FontFace = FONT_REG,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	ZIndex = 30,
	Parent = copyModal,
}), "TextColor3", "subtext")

local copyClose = themedButton(copyModal, "Close", UDim2.fromOffset(80, 26), UDim2.new(1, -92, 1, -36), "accent", "white")
copyClose.ZIndex = 30

showCopy = function(title, text)
	closePopup()
	copyTitle.Text = title
	copyBox.Text = text
	copyModal.Visible = true
	copyBox:CaptureFocus()
	copyBox.SelectionStart = 1
	copyBox.CursorPosition = #text + 1
end

copyClose.MouseButton1Click:Connect(function()
	copyBox:ReleaseFocus()
	copyModal.Visible = false
end)

-- ============================================================
--  Overlays (Help and Settings)
--  The main UI is hidden while an overlay is open, so nothing
--  can ever draw on top of the overlay. Content is rebuilt on
--  each open; if building fails, the error shows in the panel.
-- ============================================================

local function makeOverlay(titleText)
	local frame = theme(make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
		ZIndex = 10,
		Parent = root,
	}), "BackgroundColor3", "bg")

	local top = make("Frame", {
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	-- Back button on the LEFT, title next to it
	local back = themedButton(top, "< Back", UDim2.fromOffset(64, 26), UDim2.new(0, 10, 0.5, -13), "accent", "white")
	local title = theme(make("TextLabel", {
		Size = UDim2.new(1, -96, 1, 0),
		Position = UDim2.fromOffset(86, 0),
		BackgroundTransparency = 1,
		Text = titleText,
		FontFace = FONT_BOLD,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = top,
	}), "TextColor3", "text")
	theme(make("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, HEADER_H - 1),
		BorderSizePixel = 0,
		Parent = frame,
	}), "BackgroundColor3", "border")

	local body = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, HEADER_H),
		Size = UDim2.new(1, 0, 1, -HEADER_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = frame,
	})
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 14),
		Parent = body,
	})
	return { frame = frame, body = body, back = back, title = title }
end

helpOverlay = makeOverlay("How to use")
settingsOverlay = makeOverlay("Settings")
newsOverlay = makeOverlay("What's new")
welcomeOverlay = makeOverlay("Welcome")

local function contentWidth()
	local w = root.AbsoluteSize.X
	if w <= 0 then
		w = 330
	end
	return math.max(200, w - 40)
end

local function sectionCard(parent, order)
	local card = theme(make("Frame", {
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}), "BackgroundColor3", "surface")
	corner(card, 8)
	theme(make("UIStroke", { Thickness = 1, Transparency = 0.5, Parent = card }), "Color", "border")
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		Parent = card,
	})
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
	return card
end

buildHelp = function()
	local body = helpOverlay.body
	clearChildren(body)
	local width = contentWidth() - 26

	for i, sec in ipairs(HELP_SECTIONS) do
		local card = sectionCard(body, i)

		theme(make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = string.upper(sec.title),
			FontFace = FONT_BOLD,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			Parent = card,
		}), "TextColor3", "accent")

		local bodyH = measure(sec.body, 13, Enum.Font.Gotham, width)
		theme(make("TextLabel", {
			Size = UDim2.new(1, 0, 0, math.ceil(bodyH) + 4),
			BackgroundTransparency = 1,
			Text = sec.body,
			FontFace = FONT_REG,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 2,
			Parent = card,
		}), "TextColor3", "text")

		if sec.code then
			local codeH = measure(sec.code, 12, Enum.Font.Code, width - 20)
			local codeBox = theme(make("Frame", {
				Size = UDim2.new(1, 0, 0, math.ceil(codeH) + 16),
				BorderSizePixel = 0,
				LayoutOrder = 3,
				Parent = card,
			}), "BackgroundColor3", "surface2")
			corner(codeBox, 6)
			theme(make("TextLabel", {
				Size = UDim2.new(1, -20, 1, -16),
				Position = UDim2.fromOffset(10, 8),
				BackgroundTransparency = 1,
				Text = sec.code,
				FontFace = FONT_CODE,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = codeBox,
			}), "TextColor3", "subtext")
		end
	end
end

buildSettings = function()
	local body = settingsOverlay.body
	clearChildren(body)

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local function sectionTitle(text)
		theme(make("TextLabel", {
			Size = UDim2.new(1, -6, 0, 18),
			BackgroundTransparency = 1,
			Text = string.upper(text),
			FontFace = FONT_BOLD,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextOrder(),
			Parent = body,
		}), "TextColor3", "accent")
	end

	local function row(h)
		local r = theme(make("Frame", {
			Size = UDim2.new(1, -6, 0, h),
			BorderSizePixel = 0,
			LayoutOrder = nextOrder(),
			Parent = body,
		}), "BackgroundColor3", "surface")
		corner(r, 8)
		make("UIStroke", { Color = P.border, Thickness = 1, Transparency = 0.5, Parent = r })
		return r
	end

	-- Switch-style toggle
	local function toggleRow(label, value, onChange)
		local r = row(42)
		theme(make("TextLabel", {
			Size = UDim2.new(1, -74, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			BackgroundTransparency = 1,
			Text = label,
			FontFace = FONT_REG,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = r,
		}), "TextColor3", "text")
		local sw = make("TextButton", {
			Size = UDim2.fromOffset(38, 20),
			Position = UDim2.new(1, -50, 0.5, -10),
			BackgroundColor3 = value and P.accent or P.border,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Parent = r,
		})
		corner(sw, 10)
		local knob = make("Frame", {
			Size = UDim2.fromOffset(14, 14),
			Position = value and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
			BackgroundColor3 = P.white,
			BorderSizePixel = 0,
			Parent = sw,
		})
		corner(knob, 7)
		sw.MouseButton1Click:Connect(function()
			onChange(not value)
			saveCfg()
			buildSettings()
			refreshUI(true)
		end)
	end

	sectionTitle("Tags")
	for _, tag in ipairs(cfg.tags) do
		local r = row(70)

		local nameBox = make("TextBox", {
			Size = UDim2.new(1, -122, 0, 28),
			Position = UDim2.fromOffset(10, 8),
			BackgroundColor3 = P.bg,
			BorderSizePixel = 0,
			Text = tag,
			FontFace = FONT_BOLD,
			TextSize = 12,
			TextColor3 = tagColor(tag),
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			Parent = r,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = nameBox })
		corner(nameBox, 6)
		nameBox.FocusLost:Connect(function()
			renameTagFromSettings(tag, nameBox.Text)
		end)

		local alertOn = cfg.alerts[tag] == true
		local alertBtn = button(
			r, "Alert", UDim2.fromOffset(56, 28), UDim2.new(1, -102, 0, 8),
			alertOn and P.accent or P.surface2, alertOn and P.white or P.subtext
		)
		alertBtn.MouseButton1Click:Connect(function()
			cfg.alerts[tag] = (not cfg.alerts[tag]) and true or nil
			saveCfg()
			buildSettings()
			refreshUI(true)
		end)

		local removeBtn = button(r, "x", UDim2.fromOffset(30, 28), UDim2.new(1, -40, 0, 8), P.surface2, P.danger)
		removeBtn.MouseButton1Click:Connect(function()
			removeTagFromSettings(tag)
		end)

		local current = cfg.colors[tag]
		for j, c in ipairs(PRESET_COLORS) do
			local sw = make("TextButton", {
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.fromOffset(10 + (j - 1) * 26, 44),
				BackgroundColor3 = toColor(c),
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				Parent = r,
			})
			corner(sw, 5)
			if current and current[1] == c[1] and current[2] == c[2] and current[3] == c[3] then
				make("UIStroke", { Color = P.text, Thickness = 2, Parent = sw })
			end
			sw.MouseButton1Click:Connect(function()
				cfg.colors[tag] = { c[1], c[2], c[3] }
				saveCfg()
				buildSettings()
				refreshUI(true)
			end)
		end
	end

	local addRow = row(42)
	local addBox = make("TextBox", {
		Size = UDim2.new(1, -104, 0, 28),
		Position = UDim2.fromOffset(10, 7),
		BackgroundColor3 = P.bg,
		BorderSizePixel = 0,
		PlaceholderText = "New tag, e.g. BUG",
		Text = "",
		FontFace = FONT_REG,
		TextSize = 12,
		TextColor3 = P.text,
		PlaceholderColor3 = P.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = addRow,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = addBox })
	corner(addBox, 6)
	local addBtn = button(addRow, "Add", UDim2.fromOffset(72, 28), UDim2.new(1, -82, 0, 7), P.accent, P.white)
	addBtn.MouseButton1Click:Connect(function()
		local t = string.upper(trim(addBox.Text))
		if t == "" or not string.match(t, TAG_PATTERN) or isTag(t) or #cfg.tags >= K.MAX_TAGS then
			return
		end
		table.insert(cfg.tags, t)
		cfg.colors[t] = deepCopy(PRESET_COLORS[((#cfg.tags - 1) % #PRESET_COLORS) + 1])
		activeTags[t] = true
		saveCfg()
		buildChips()
		buildSettings()
		refreshUI(true)
	end)

	sectionTitle("General")
	toggleRow("Preview panel", cfg.preview, function(v)
		cfg.preview = v
		layout()
	end)
	toggleRow("Alerts for new notes", cfg.notify, function(v)
		cfg.notify = v
	end)
	toggleRow("Accept notes without colon", cfg.allowNoColon, function(v)
		cfg.allowNoColon = v
		reparseAll()
		rebuildAll()
	end)

	sectionTitle("Data")
	local actRow = row(46)
	local resetBtn = button(actRow, "Reset settings", UDim2.new(0.5, -14, 0, 28), UDim2.fromOffset(10, 9), P.surface2, P.text)
	resetBtn.MouseButton1Click:Connect(function()
		cfg.tags = deepCopy(DEFAULT_CFG.tags)
		cfg.colors = deepCopy(DEFAULT_CFG.colors)
		cfg.alerts = deepCopy(DEFAULT_CFG.alerts)
		cfg.notify = DEFAULT_CFG.notify
		cfg.preview = DEFAULT_CFG.preview
		cfg.allowNoColon = DEFAULT_CFG.allowNoColon
		table.clear(activeTags)
		syncActiveTags()
		saveCfg()
		reparseAll()
		rebuildAll()
		buildChips()
		layout()
		buildSettings()
		refreshUI(true)
	end)
	local clearDoneBtn = button(actRow, "Clear done & ignored", UDim2.new(0.5, -14, 0, 28), UDim2.new(0.5, 4, 0, 9), P.surface2, P.text)
	clearDoneBtn.TextTruncate = Enum.TextTruncate.AtEnd
	clearDoneBtn.MouseButton1Click:Connect(function()
		table.clear(doneSet)
		table.clear(ignoredSet)
		saveSet(DONE_KEY, doneSet)
		saveSet(IGNORE_KEY, ignoredSet)
		buildSettings()
		refreshUI(true)
	end)

	sectionTitle("About")
	local aboutText = "Notes update when scripts change. Sync re-reads every script in the place. Right-click a card for more actions."
	local aboutH = measure(aboutText, 12, Enum.Font.Gotham, contentWidth() - 20)
	theme(make("TextLabel", {
		Size = UDim2.new(1, -6, 0, math.ceil(aboutH) + 4),
		BackgroundTransparency = 1,
		Text = aboutText,
		FontFace = FONT_REG,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = nextOrder(),
		Parent = body,
	}), "TextColor3", "subtext")

	local verRow = row(46)
	theme(make("TextLabel", {
		Size = UDim2.new(1, -130, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = APP.name .. "  v" .. APP.version .. " " .. APP.channel,
		FontFace = FONT_MED,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = verRow,
	}), "TextColor3", "text")
	local newsBtn = button(verRow, "What's new", UDim2.fromOffset(100, 28), UDim2.new(1, -110, 0.5, -14), P.accent, P.white)
	newsBtn.MouseButton1Click:Connect(function()
		setOverlay("news")
	end)

	local welcomeRow = row(46)
	theme(make("TextLabel", {
		Size = UDim2.new(1, -130, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = "Welcome screen",
		FontFace = FONT_MED,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = welcomeRow,
	}), "TextColor3", "text")
	local welcomeBtn = button(welcomeRow, "Open", UDim2.fromOffset(100, 28), UDim2.new(1, -110, 0.5, -14), P.surface2, P.text)
	welcomeBtn.MouseButton1Click:Connect(function()
		setOverlay("welcome")
	end)
end

renameTagFromSettings = function(old, new)
	new = string.upper(trim(new))
	if new == old then
		return
	end
	if not string.match(new, TAG_PATTERN) or isTag(new) then
		warn("[Noted] Tag names must be letters only and unique: " .. new)
		buildSettings()
		return
	end
	for i, t in ipairs(cfg.tags) do
		if t == old then
			cfg.tags[i] = new
		end
	end
	cfg.colors[new] = cfg.colors[old]
	cfg.colors[old] = nil
	cfg.alerts[new] = cfg.alerts[old]
	cfg.alerts[old] = nil
	activeTags[new] = activeTags[old]
	activeTags[old] = nil
	saveCfg()
	reparseAll()
	rebuildAll()
	buildChips()
	buildSettings()
	refreshUI(true)
end

removeTagFromSettings = function(tag)
	if #cfg.tags <= 1 then
		return
	end
	for i, t in ipairs(cfg.tags) do
		if t == tag then
			table.remove(cfg.tags, i)
			break
		end
	end
	cfg.colors[tag] = nil
	cfg.alerts[tag] = nil
	activeTags[tag] = nil
	saveCfg()
	reparseAll()
	rebuildAll()
	buildChips()
	buildSettings()
	refreshUI(true)
end

buildNews = function()
	local body = newsOverlay.body
	clearChildren(body)
	local width = contentWidth() - 26

	local notice = sectionCard(body, 0)
	theme(make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = "BETA",
		FontFace = FONT_BOLD,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = notice,
	}), "TextColor3", "accent")
	local noticeText = "Noted is still in beta and has not been released yet. Some things may change or break while it is being tested."
	local nh = measure(noticeText, 13, Enum.Font.Gotham, width)
	theme(make("TextLabel", {
		Size = UDim2.new(1, 0, 0, math.ceil(nh) + 4),
		BackgroundTransparency = 1,
		Text = noticeText,
		FontFace = FONT_REG,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
		Parent = notice,
	}), "TextColor3", "text")

	for i, rel in ipairs(APP.changelog) do
		local card = sectionCard(body, i)
		theme(make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = string.format("v%s  ·  %s  ·  %s", rel.version, rel.channel, rel.date),
			FontFace = FONT_BOLD,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			Parent = card,
		}), "TextColor3", "text")

		local lines = {}
		for _, item in ipairs(rel.items) do
			table.insert(lines, "•  " .. item)
		end
		local text = table.concat(lines, "\n")
		local h = measure(text, 13, Enum.Font.Gotham, width)
		theme(make("TextLabel", {
			Size = UDim2.new(1, 0, 0, math.ceil(h) + 4),
			BackgroundTransparency = 1,
			Text = text,
			FontFace = FONT_REG,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 2,
			Parent = card,
		}), "TextColor3", "subtext")
	end
end

buildWelcome = function()
	local body = welcomeOverlay.body
	clearChildren(body)

	-- Text labels grow with their content, so nothing gets cut off
	local function para(parent, order, text, colorKey, font, size)
		theme(make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = text,
			FontFace = font or FONT_REG,
			TextSize = size or 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = order,
			Parent = parent,
		}), "TextColor3", colorKey or "text")
	end

	-- Frosted card: translucent, soft rounded corners, lifts on hover, pops in on open
	local function glassCard(order)
		local card = theme(make("Frame", {
			Size = UDim2.new(1, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = body,
		}), "BackgroundColor3", "surface")
		corner(card, 14)
		theme(make("UIStroke", { Thickness = 1, Transparency = 0.5, Parent = card }), "Color", "border")
		make("UIPadding", {
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 14),
			Parent = card,
		})
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

		local scale = make("UIScale", { Scale = 0.92, Parent = card })
		task.delay(order * 0.08, function()
			if card.Parent then
				tween(scale, { Scale = 1 }, 0.5, Enum.EasingStyle.Back)
				tween(card, { BackgroundTransparency = 0.12 }, 0.4)
			end
		end)
		card.MouseEnter:Connect(function()
			tween(scale, { Scale = 1.015 }, 0.25)
		end)
		card.MouseLeave:Connect(function()
			tween(scale, { Scale = 1 }, 0.3)
		end)
		return card
	end

	local hero = glassCard(1)
	para(hero, 1, "Noted", "text", FONT_BOLD, 24)
	para(hero, 2, "Collect every TODO, FIX, HACK and NOTE comment in your project in one panel, search them, and jump straight to the code.", "subtext")
	para(hero, 3, "In development  ·  v" .. APP.version, "accent", FONT_MED, 12)

	local oss = glassCard(2)
	para(oss, 1, "OPEN SOURCE", "accent", FONT_BOLD, 11)
	para(oss, 2, "Noted is developed as an open source project. Anyone can read the source code, report bugs, and contribute. Feedback from the community is a key part of making it better.", "subtext")

	local steps = glassCard(3)
	para(steps, 1, "HOW TO START", "accent", FONT_BOLD, 11)
	para(steps, 2, "1.  Write  -- N: description  in any script.\n2.  Click a card to open the script at that line.\n3.  Right-click a card to mark it done or ignore it.", "subtext")

	-- Sliding pill switch (Start / What's new)
	local seg = theme(make("Frame", {
		Size = UDim2.new(1, -6, 0, 42),
		BorderSizePixel = 0,
		LayoutOrder = 4,
		Parent = body,
	}), "BackgroundColor3", "surface2")
	corner(seg, 21)

	local indicator = theme(make("Frame", {
		Size = UDim2.new(0.5, -6, 1, -6),
		Position = UDim2.fromOffset(3, 3),
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = seg,
	}), "BackgroundColor3", "accent")
	corner(indicator, 18)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 210, 236)),
		Rotation = 90,
		Parent = indicator,
	})
	local glowA = theme(make("Frame", {
		Size = UDim2.new(0.5, 4, 1, 4),
		Position = UDim2.fromOffset(-2, -2),
		BackgroundTransparency = 0.76,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = seg,
	}), "BackgroundColor3", "accent")
	corner(glowA, 23)
	local glowB = theme(make("Frame", {
		Size = UDim2.new(0.5, 12, 1, 12),
		Position = UDim2.fromOffset(-6, -6),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = seg,
	}), "BackgroundColor3", "accent")
	corner(glowB, 27)

	local function moveTo(xScale)
		tween(indicator, { Position = UDim2.new(xScale, 3, 0, 3) }, 0.4, Enum.EasingStyle.Quint)
		tween(glowA, { Position = UDim2.new(xScale, -2, 0, -2) }, 0.4, Enum.EasingStyle.Quint)
		tween(glowB, { Position = UDim2.new(xScale, -6, 0, -6) }, 0.4, Enum.EasingStyle.Quint)
	end

	local segToken = 0
	local function segButton(text, xScale, onClick)
		local b = make("TextButton", {
			Size = UDim2.new(0.5, 0, 1, 0),
			Position = UDim2.new(xScale, 0, 0, 0),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = text,
			FontFace = FONT_BOLD,
			TextSize = 13,
			ZIndex = 2,
			Parent = seg,
		})
		theme(b, "TextColor3", "text")
		b.MouseEnter:Connect(function()
			segToken += 1
			moveTo(xScale)
		end)
		b.MouseLeave:Connect(function()
			segToken += 1
			local mine = segToken
			task.delay(0.15, function()
				if mine == segToken then
					moveTo(0)
				end
			end)
		end)
		b.MouseButton1Click:Connect(onClick)
		return b
	end

	segButton("Start", 0, function()
		setOverlay(nil)
	end)
	segButton("What's new", 0.5, function()
		setOverlay("news")
	end)
end

-- Runs a builder; on failure, shows the error inside the panel
local function safeBuild(builder, overlay)
	clearChildren(overlay.body)
	local ok, err = pcall(builder)
	if not ok then
		warn("[Noted] panel build failed: " .. tostring(err))
		theme(make("TextLabel", {
			Size = UDim2.new(1, -6, 0, 80),
			BackgroundTransparency = 1,
			Text = "Could not draw this panel.\n" .. tostring(err),
			FontFace = FONT_REG,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 1,
			Parent = overlay.body,
		}), "TextColor3", "danger")
	end
end

-- Shows or hides every main-UI element so an overlay is never covered
local function setMainVisible(v)
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("GuiObject")
			and c ~= helpOverlay.frame and c ~= settingsOverlay.frame and c ~= newsOverlay.frame and c ~= welcomeOverlay.frame
			and c ~= popup and c ~= popupCatcher and c ~= copyModal
			and c ~= (APP.loader and APP.loader.frame) then
			c.Visible = v
		end
	end
	if v then
		clearBtn.Visible = searchBox.Text ~= ""
		layout()
	end
	APP.updateLoader()
end

-- Cards of an overlay spring in one after another
APP.springIn = function(body)
	local i = 0
	for _, c in ipairs(body:GetChildren()) do
		if c:IsA("GuiObject") then
			i += 1
			local s = make("UIScale", { Scale = 0.9, Parent = c })
			task.delay(0.05 + i * 0.05, function()
				if c.Parent then
					tween(s, { Scale = 1 }, 0.55, Enum.EasingStyle.Back)
				end
			end)
		end
	end
end

setOverlay = function(name)
	APP.resetNewsFrame()
	local leavingWelcome = currentOverlay == "welcome" and name ~= "welcome"
	if leavingWelcome then
		setSetting(WELCOME_KEY, "yes")
	end
	currentOverlay = name
	closePopup()
	setMainVisible(name == nil)
	if leavingWelcome and name == nil then
		APP.playIntro()
	end
	helpOverlay.frame.Visible = name == "help"
	settingsOverlay.frame.Visible = name == "settings"
	newsOverlay.frame.Visible = name == "news"
	welcomeOverlay.frame.Visible = name == "welcome"

	local slide = name == "help" and helpOverlay
		or name == "settings" and settingsOverlay
		or name == "welcome" and welcomeOverlay
		or nil
	if slide then
		slide.frame.Position = UDim2.fromScale(0.12, 0)
		tween(slide.frame, { Position = UDim2.new() }, 0.45, Enum.EasingStyle.Quint)
	end

	if name == "help" then
		safeBuild(buildHelp, helpOverlay)
		APP.springIn(helpOverlay.body)
	elseif name == "settings" then
		safeBuild(buildSettings, settingsOverlay)
		APP.springIn(settingsOverlay.body)
	elseif name == "news" then
		safeBuild(buildNews, newsOverlay)
	elseif name == "welcome" then
		safeBuild(buildWelcome, welcomeOverlay)
	end
end

helpOverlay.back.MouseButton1Click:Connect(function()
	setOverlay(nil)
end)
settingsOverlay.back.MouseButton1Click:Connect(function()
	setOverlay(nil)
end)
newsOverlay.back.MouseButton1Click:Connect(function()
	setOverlay(nil)
end)
welcomeOverlay.back.MouseButton1Click:Connect(function()
	setSetting(APP.seenKey, APP.version)
	setOverlay(nil)
end)

-- ============================================================
--  Notes: filtering, cards, rendering
-- ============================================================

local function isMuted(e)
	return doneSet[e.key] == true or ignoredSet[e.key] == true
end

local function passesBase(e)
	if not inScope(e.script) then
		return false
	end
	if isMuted(e) and not showDone then
		return false
	end
	if searchText ~= "" then
		local hay = string.lower(e.text .. " " .. e.path .. " " .. e.assignee)
		if not string.find(hay, searchText, 1, true) then
			return false
		end
	end
	return true
end

-- Cards spring in and float up with a soft fade
local function fadeIn(card, delay)
	local sc = card:FindFirstChildOfClass("UIScale")
	if sc then
		sc.Scale = 0.92
	end
	local objs = card:GetDescendants()
	table.insert(objs, 1, card)
	local goals = {}
	for _, obj in ipairs(objs) do
		if obj:IsA("GuiObject") then
			goals[obj] = obj.BackgroundTransparency
			obj.BackgroundTransparency = 1
			if obj:IsA("TextLabel") or obj:IsA("TextButton") then
				obj.TextTransparency = 1
			end
		end
	end
	task.delay(delay, function()
		if sc and sc.Parent then
			tween(sc, { Scale = 1 }, 0.55, Enum.EasingStyle.Back)
		end
		for obj, bg in pairs(goals) do
			if obj.Parent then
				tween(obj, { BackgroundTransparency = bg }, 0.3)
				if obj:IsA("TextLabel") or obj:IsA("TextButton") then
					tween(obj, { TextTransparency = 0 }, 0.3)
				end
			end
		end
	end)
end

local function toggleSet(set, key, id)
	if set[id] then
		set[id] = nil
	else
		set[id] = true
	end
	saveSet(key, set)
	refreshUI(false)
end

local function openContext(e, card)
	local x = card.AbsolutePosition.X - root.AbsolutePosition.X + card.AbsoluteSize.X - 170
	local y = card.AbsolutePosition.Y - root.AbsolutePosition.Y + 22
	local done = doneSet[e.key] == true
	local ignored = ignoredSet[e.key] == true
	showPopup(x, y, {
		{ label = "Open in editor", fn = function() openAt(e) end },
		{
			label = "Copy note",
			fn = function()
				showCopy("Copy note", string.format("%s %s:%d  %s", e.tag, e.path, e.line, e.text))
			end,
		},
		{ label = done and "Mark as open" or "Mark as done", fn = function() toggleSet(doneSet, DONE_KEY, e.key) end },
		{ label = ignored and "Stop ignoring" or "Ignore", fn = function() toggleSet(ignoredSet, IGNORE_KEY, e.key) end },
	})
end

showPreview = function(e)
	clearChildren(previewRows)

	local total = #e.lines
	local first = math.max(1, e.line - 2)
	local last = math.min(total, first + PREVIEW_ROWS - 1)
	first = math.max(1, last - PREVIEW_ROWS + 1)

	previewTitle.Text = string.format("%s  :  line %d", e.path, e.line)
	local color = tagColor(e.tag)

	for i = first, last do
		local isTarget = i == e.line
		local rowFrame = make("Frame", {
			Size = UDim2.new(1, 0, 0, PREVIEW_ROW_H),
			BackgroundColor3 = color,
			BackgroundTransparency = isTarget and 0.82 or 1,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = previewRows,
		})
		corner(rowFrame, 3)
		make("TextLabel", {
			Size = UDim2.new(0, 34, 1, 0),
			BackgroundTransparency = 1,
			Text = tostring(i),
			FontFace = FONT_CODE,
			TextSize = 12,
			TextColor3 = isTarget and color or P.subtext,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = rowFrame,
		})
		local raw = string.gsub(e.lines[i] or "", "\r", "")
		local code = make("TextLabel", {
			Position = UDim2.fromOffset(42, 0),
			Size = UDim2.new(1, -46, 1, 0),
			BackgroundTransparency = 1,
			Text = (string.gsub(raw, "\t", "    ")),
			FontFace = FONT_CODE,
			TextSize = 12,
			TextColor3 = isTarget and P.text or P.subtext,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextTransparency = 1,
			Parent = rowFrame,
		})
		tween(code, { TextTransparency = 0 }, 0.25)
	end
end

-- Card layout (CARD_H = 66):
--   row 1 (y=10): tag pill + "file : line"            | check box on the far right
--   row 2 (y=30): note text
--   row 3 (y=48): assignee / date / status           | priority badge on the far right
local function buildCard(e, order)
	local color = tagColor(e.tag)
	local done = doneSet[e.key] == true
	local ignored = ignoredSet[e.key] == true
	local muted = done or ignored

	local card = make("TextButton", {
		Name = "Card",
		Size = UDim2.new(1, -6, 0, CARD_H),
		BackgroundColor3 = P.surface,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = list,
	})
	corner(card, 8)
	local cscale = make("UIScale", { Parent = card })
	card.MouseButton1Down:Connect(function()
		tween(cscale, { Scale = 0.985 }, 0.08)
	end)
	card.MouseButton1Up:Connect(function()
		tween(cscale, { Scale = 1.012 }, 0.25, Enum.EasingStyle.Back)
	end)
	local stroke = make("UIStroke", { Color = P.border, Thickness = 1, Transparency = 0.4, Parent = card })

	local bar = make("Frame", {
		Size = UDim2.new(0, 3, 1, -20),
		Position = UDim2.fromOffset(0, 10),
		BackgroundColor3 = color,
		BackgroundTransparency = muted and 0.5 or 0,
		BorderSizePixel = 0,
		Parent = card,
	})
	corner(bar, 2)

	local pillW = #e.tag * 7 + 18
	local pill = make("TextLabel", {
		Size = UDim2.fromOffset(pillW, 16),
		Position = UDim2.fromOffset(14, 10),
		BackgroundColor3 = color,
		BackgroundTransparency = muted and 0.6 or 0,
		BorderSizePixel = 0,
		Text = e.tag,
		FontFace = FONT_BOLD,
		TextSize = 10,
		TextColor3 = P.white,
		Parent = card,
	})
	corner(pill, 4)

	make("TextLabel", {
		Size = UDim2.new(1, -(14 + pillW + 8 + 40), 0, 16),
		Position = UDim2.fromOffset(14 + pillW + 8, 10),
		BackgroundTransparency = 1,
		Text = string.format("%s : %d", e.script.Name, e.line),
		FontFace = FONT_REG,
		TextSize = 11,
		TextColor3 = P.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -30, 0, 16),
		Position = UDim2.fromOffset(14, 30),
		BackgroundTransparency = 1,
		Text = e.text,
		FontFace = FONT_MED,
		TextSize = 13,
		TextColor3 = muted and P.subtext or P.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})

	local meta = {}
	if e.assignee ~= "" then
		table.insert(meta, "@" .. e.assignee)
	end
	if e.date ~= "" then
		local age = ageText(e.date)
		table.insert(meta, age and (e.date .. " (" .. age .. ")") or e.date)
	end
	if ignored then
		table.insert(meta, "ignored")
	end
	if done then
		table.insert(meta, "done")
	end
	local metaRight = e.bangs > 0 and 56 or 16
	make("TextLabel", {
		Size = UDim2.new(1, -(14 + metaRight), 0, 14),
		Position = UDim2.fromOffset(14, 48),
		BackgroundTransparency = 1,
		Text = table.concat(meta, "  ·  "),
		FontFace = FONT_REG,
		TextSize = 11,
		TextColor3 = P.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})

	if e.bangs > 0 then
		make("TextLabel", {
			Size = UDim2.fromOffset(40, 14),
			Position = UDim2.new(1, -48, 0, 48),
			BackgroundTransparency = 1,
			Text = string.rep("!", math.min(e.bangs, 4)),
			FontFace = FONT_BOLD,
			TextSize = 13,
			TextColor3 = muted and P.subtext or P.danger,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
	end

	local check = make("TextButton", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -28, 0, 9),
		BackgroundColor3 = done and color or P.bg,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = done and "?" or "",
		FontFace = FONT_BOLD,
		TextSize = 12,
		TextColor3 = P.white,
		Parent = card,
	})
	corner(check, 5)
	make("UIStroke", { Color = color, Thickness = 1, Parent = check })
	check.MouseButton1Click:Connect(function()
		toggleSet(doneSet, DONE_KEY, e.key)
	end)

	card.MouseEnter:Connect(function()
		tween(card, { BackgroundColor3 = P.hover }, 0.15)
		tween(stroke, { Color = color, Transparency = 0.2 }, 0.15)
		tween(bar, { Size = UDim2.new(0, 5, 1, -20) }, 0.15)
		tween(cscale, { Scale = 1.012 }, 0.2)
		if cfg.preview and previewFrame.Visible then
			showPreview(e)
		end
	end)
	card.MouseLeave:Connect(function()
		tween(card, { BackgroundColor3 = P.surface }, 0.2)
		tween(stroke, { Color = P.border, Transparency = 0.4 }, 0.2)
		tween(bar, { Size = UDim2.new(0, 3, 1, -20) }, 0.2)
		tween(cscale, { Scale = 1 }, 0.25)
	end)
	card.MouseButton1Click:Connect(function()
		openAt(e)
	end)
	card.MouseButton2Click:Connect(function()
		openContext(e, card)
	end)

	return card
end

local function emptyState(msgTitle, msgHint)
	local box = make("Frame", {
		Size = UDim2.new(1, -6, 0, 120),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = list,
	})
	theme(make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 1,
		Text = msgTitle,
		FontFace = FONT_BOLD,
		TextSize = 14,
		TextWrapped = true,
		Parent = box,
	}), "TextColor3", "text")
	theme(make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.fromOffset(10, 54),
		BackgroundTransparency = 1,
		Text = msgHint,
		FontFace = FONT_REG,
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = box,
	}), "TextColor3", "subtext")
end

render = function(animate)
	local counts = {}
	for _, t in ipairs(cfg.tags) do
		counts[t] = 0
	end

	local shown, files = {}, {}
	local total, open = 0, 0
	for _, e in ipairs(allEntries) do
		if passesBase(e) then
			total += 1
			if counts[e.tag] then
				counts[e.tag] += 1
			end
			if not isMuted(e) then
				open += 1
			end
			if activeTags[e.tag] then
				table.insert(shown, e)
				files[e.path] = true
			end
		end
	end
	lastShown = shown
	countsCache = counts

	clearChildren(list)

	local limit = math.min(#shown, pageLimit)
	for i = 1, limit do
		local card = buildCard(shown[i], i)
		if animate and i <= 25 then
			fadeIn(card, (i - 1) * 0.02)
		end
	end

	if #shown > limit then
		local more = button(
			list, string.format("Show %d more", #shown - limit),
			UDim2.new(1, -6, 0, 30), UDim2.new(), P.surface2, P.text
		)
		more.LayoutOrder = 100000
		more.MouseButton1Click:Connect(function()
			pageLimit += PAGE_SIZE
			refreshUI(true)
		end)
	end

	if #shown == 0 then
		if #allEntries == 0 then
			emptyState("No notes in this project yet", "Write  -- N: something  in any script, then press Sync.")
		elseif total == 0 then
			emptyState("Nothing in this scope", "Change the scope or clear the search to see more notes.")
		elseif not showDone then
			emptyState("No open notes match", "Turn on Show done, or clear the search.")
		else
			emptyState("No notes match", "Try enabling more tags or clearing the search.")
		end
	end

	local fileCount = 0
	for _ in pairs(files) do
		fileCount += 1
	end
	footerStats = string.format("%d shown  ·  %d open  ·  %d files", #shown, open, fileCount)
	refreshFooter()
	widget.Title = string.format("Noted  (%d open)", open)
	refreshControls()
end

refreshUI = function(animate)
	if not widget.Enabled then
		return
	end
	render(animate)
end

refreshControls = function()
	for tag, chip in pairs(chipButtons) do
		local on = activeTags[tag] == true
		chip.Text = string.format("%s  %d", tag, countsCache[tag] or 0)
		tween(chip, {
			BackgroundColor3 = on and tagColor(tag) or P.surface2,
			TextColor3 = on and P.white or P.subtext,
		}, 0.2)
	end
	scopeBtn.Text = "Scope: " .. scopeName
	doneBtn.Text = showDone and "Showing done" or "Show done"
	APP.setSegKey(doneBtn, showDone and "accent" or "text")
	styleButton(previewToggle, cfg.preview and P.accent or P.surface2, cfg.preview and P.white or P.text)
end

-- ============================================================
--  Export
-- ============================================================

local function buildMarkdown(items)
	local out = { "# Noted", "" }
	for _, tag in ipairs(cfg.tags) do
		local section = {}
		for _, e in ipairs(items) do
			if e.tag == tag then
				table.insert(section, e)
			end
		end
		if #section > 0 then
			table.insert(out, string.format("## %s (%d)", tag, #section))
			table.insert(out, "")
			for _, e in ipairs(section) do
				local meta = {}
				if e.assignee ~= "" then
					table.insert(meta, e.assignee)
				end
				if e.date ~= "" then
					table.insert(meta, e.date)
				end
				local metaText = #meta > 0 and (" (" .. table.concat(meta, ", ") .. ")") or ""
				table.insert(out, string.format(
					"- [%s] `%s` line %d%s: %s",
					doneSet[e.key] and "x" or " ", e.path, e.line, metaText, e.text
					))
			end
			table.insert(out, "")
		end
	end
	return table.concat(out, "\n")
end

local function longString(s)
	local eq = ""
	while string.find(s, "]" .. eq .. "]", 1, true) do
		eq = eq .. "="
	end
	return "[" .. eq .. "[\n" .. s .. "\n]" .. eq .. "]"
end

local function writeModule(md)
	return pcall(function()
		local mod = ServerStorage:FindFirstChild("TodoExport")
		if not mod then
			mod = Instance.new("ModuleScript")
			mod.Name = "TodoExport"
			mod.Parent = ServerStorage
		end
		mod.Source = "return " .. longString(md)
	end)
end

runExport = function(which, action)
	local items
	if which == "visible" then
		items = lastShown
	else
		items = {}
		for _, e in ipairs(allEntries) do
			if inScope(e.script) then
				table.insert(items, e)
			end
		end
	end
	local md = buildMarkdown(items)

	if action == "print" then
		print(md)
		showToast(string.format("Printed %d notes to the Output window", #items), P.accent, nil)
	elseif action == "copy" then
		showCopy("Markdown export (" .. #items .. " notes)", md)
	elseif action == "module" then
		local ok, err = writeModule(md)
		if ok then
			showToast(string.format("Saved %d notes to ServerStorage.TodoExport", #items), P.accent, nil)
		else
			warn("[Noted] Could not write ModuleScript: " .. tostring(err))
			showToast("Export failed, see the Output window", P.danger, nil)
		end
	end
end

local function exportMenu(btn)
	local x, y = menuBelow(btn)
	showPopup(x - 110, y, {
		{ label = "Print visible to Output", fn = function() runExport("visible", "print") end },
		{ label = "Print all to Output", fn = function() runExport("all", "print") end },
		{ label = "Copy visible as Markdown", fn = function() runExport("visible", "copy") end },
		{ label = "Save visible to ServerStorage", fn = function() runExport("visible", "module") end },
		{ label = "Save all to ServerStorage", fn = function() runExport("all", "module") end },
	})
end

-- ============================================================
--  Theme
-- ============================================================

applyTheme = function()
	local ok, studioTheme = pcall(function()
		return settings().Studio.Theme
	end)
	if ok and studioTheme then
		local bg = studioTheme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
		P = ((bg.R + bg.G + bg.B) / 3 > 0.5) and LIGHT or DARK
	end

	local alive = {}
	for _, p in ipairs(themed) do
		if p.obj:IsDescendantOf(widget) then
			p.obj[p.prop] = P[p.key]
			table.insert(alive, p)
		end
	end
	themed = alive

	local aliveButtons = {}
	for _, b in ipairs(buttons) do
		if b.btn:IsDescendantOf(widget) then
			styleButton(b.btn, P[b.bg], P[b.fg])
			table.insert(aliveButtons, b)
		end
	end
	buttons = aliveButtons

	for _, sg in ipairs(APP.segs) do
		if sg.btn:IsDescendantOf(widget) then
			sg.btn:SetAttribute("RestText", P[sg.key])
			sg.btn.TextColor3 = P[sg.key]
		end
	end

	refreshControls()
	refreshUI(false)
	if currentOverlay == "settings" then
		safeBuild(buildSettings, settingsOverlay)
	elseif currentOverlay == "help" then
		safeBuild(buildHelp, helpOverlay)
	elseif currentOverlay == "news" then
		safeBuild(buildNews, newsOverlay)
	elseif currentOverlay == "welcome" then
		safeBuild(buildWelcome, welcomeOverlay)
	end
end

-- ============================================================
--  Wiring
-- ============================================================

APP.resetNewsFrame = function()
	local f = newsOverlay.frame
	for _, n in ipairs({ "RevealScale", "RevealCorner", "RevealStroke" }) do
		local o = f:FindFirstChild(n)
		if o then
			o:Destroy()
		end
	end
	f.AnchorPoint = Vector2.new(0, 0)
	f.Position = UDim2.new()
	f.Size = UDim2.fromScale(1, 1)
end

APP.revealToken = 0
APP.openNewsFromLogo = function(logo)
	setOverlay("news")
	local f = newsOverlay.frame
	local W, H = root.AbsoluteSize.X, root.AbsoluteSize.Y
	if W <= 0 or H <= 0 then
		return
	end
	APP.revealToken += 1
	local token = APP.revealToken

	-- keep the main UI visible underneath while the panel grows out of the logo
	setMainVisible(true)

	local cx = logo.AbsolutePosition.X - root.AbsolutePosition.X + logo.AbsoluteSize.X / 2
	local cy = logo.AbsolutePosition.Y - root.AbsolutePosition.Y + logo.AbsoluteSize.Y / 2
	f.AnchorPoint = Vector2.new(cx / W, cy / H)
	f.Position = UDim2.fromScale(cx / W, cy / H)

	local sc = make("UIScale", { Name = "RevealScale", Scale = 0.04, Parent = f })
	local cr = make("UICorner", { Name = "RevealCorner", CornerRadius = UDim.new(0, 140), Parent = f })
	local st = make("UIStroke", { Name = "RevealStroke", Color = P.accent, Thickness = 3, Transparency = 0, Parent = f })
	tween(sc, { Scale = 1 }, 0.65, Enum.EasingStyle.Quint)
	tween(cr, { CornerRadius = UDim.new(0, 0) }, 0.65, Enum.EasingStyle.Quint)
	tween(st, { Transparency = 1 }, 0.8)

	-- cards spring in one after another
	local i = 0
	for _, card in ipairs(newsOverlay.body:GetChildren()) do
		if card:IsA("Frame") then
			i += 1
			local cs = make("UIScale", { Scale = 0.8, Parent = card })
			task.delay(0.3 + i * 0.1, function()
				if card.Parent then
					tween(cs, { Scale = 1 }, 0.6, Enum.EasingStyle.Back)
				end
			end)
		end
	end

	task.delay(0.75, function()
		if token == APP.revealToken and currentOverlay == "news" then
			APP.resetNewsFrame()
			setMainVisible(false)
		end
	end)
end

APP.announce = function()
	if getSetting(WELCOME_KEY) ~= "yes" then
		setSetting(APP.seenKey, APP.version)
		setOverlay("welcome")
		return
	end
	if getSetting(APP.seenKey) == APP.version then
		return
	end
	setSetting(APP.seenKey, APP.version)
	showToast(
		string.format("Noted %s %s  ·  click to see what's new", APP.version, APP.channel),
		P.accent,
		function()
			setOverlay("news")
		end
	)
end

APP.onOpen = function()
	APP.playIntro()
	local ok, err = pcall(APP.announce)
	if not ok then
		warn("[Noted] welcome screen failed: " .. tostring(err))
	end
end

helpBtn.MouseButton1Click:Connect(function()
	setOverlay(currentOverlay == "help" and nil or "help")
end)

settingsBtn.MouseButton1Click:Connect(function()
	setOverlay(currentOverlay == "settings" and nil or "settings")
end)

syncBtn.MouseButton1Click:Connect(function()
	if not scanning then
		task.spawn(fullScan)
	end
end)

scopeBtn.MouseButton1Click:Connect(function()
	local x, y = menuBelow(scopeBtn)
	local items = {}
	for _, s in ipairs(SCOPES) do
		table.insert(items, {
			label = (s.name == scopeName and "?  " or "    ") .. s.name,
			fn = function()
				setScopeName(s.name)
				pageLimit = PAGE_SIZE
				refreshUI(true)
			end,
		})
	end
	showPopup(x, y, items)
end)

doneBtn.MouseButton1Click:Connect(function()
	showDone = not showDone
	pageLimit = PAGE_SIZE
	refreshUI(true)
end)

exportBtn.MouseButton1Click:Connect(function()
	exportMenu(exportBtn)
end)

previewToggle.MouseButton1Click:Connect(function()
	cfg.preview = not cfg.preview
	saveCfg()
	layout()
	refreshControls()
	refreshUI(false)
end)

root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

toggleBtn.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleBtn:SetActive(widget.Enabled)
	if widget.Enabled then
		layout()
		APP.onOpen()
		if initialized then
			refreshUI(true)
		else
			task.spawn(fullScan)
		end
	end
end)

pcall(function()
	settings().Studio.ThemeChanged:Connect(applyTheme)
end)

-- ============================================================
--  Loader panel
-- ============================================================

APP.buildLoader = function()
	local L = { disp = 0, t = 0, on = false, bars = {} }
	APP.loader = L

	L.frame = theme(make("CanvasGroup", {
		Name = "Loader",
		Position = UDim2.fromOffset(0, LIST_Y),
		Size = UDim2.new(1, 0, 1, -(LIST_Y + FOOTER_H)),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 5,
		Visible = false,
		Parent = root,
	}), "BackgroundColor3", "bg")

	-- status card
	local card = theme(make("Frame", {
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -16, 0, 66),
		BorderSizePixel = 0,
		Parent = L.frame,
	}), "BackgroundColor3", "surface")
	corner(card, 10)
	theme(make("UIStroke", { Thickness = 1, Transparency = 0.4, Parent = card }), "Color", "border")

	-- spinner: faint track + rotating gradient arc
	local spin = make("Frame", {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(14, 11),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local track = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = spin })
	corner(track, 17)
	theme(make("UIStroke", { Thickness = 3, Transparency = 0.45, Parent = track }), "Color", "border")
	local arc = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = spin })
	corner(arc, 17)
	local arcStroke = theme(make("UIStroke", { Thickness = 3, Parent = arc }), "Color", "accent")
	L.grad = make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.1),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = arcStroke,
	})

	L.title = theme(make("TextLabel", {
		Position = UDim2.fromOffset(60, 9),
		Size = UDim2.new(1, -130, 0, 18),
		BackgroundTransparency = 1,
		Text = "Scanning scripts",
		FontFace = FONT_BOLD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	}), "TextColor3", "text")
	L.sub = theme(make("TextLabel", {
		Position = UDim2.fromOffset(60, 28),
		Size = UDim2.new(1, -74, 0, 14),
		BackgroundTransparency = 1,
		Text = "",
		FontFace = FONT_REG,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	}), "TextColor3", "subtext")
	L.pct = theme(make("TextLabel", {
		Position = UDim2.new(1, -64, 0, 9),
		Size = UDim2.fromOffset(50, 18),
		BackgroundTransparency = 1,
		Text = "0%",
		FontFace = FONT_BOLD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	}), "TextColor3", "accent")

	local barTrack = theme(make("Frame", {
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.new(1, -28, 0, 4),
		BorderSizePixel = 0,
		Parent = card,
	}), "BackgroundColor3", "surface2")
	corner(barTrack, 2)
	L.fill = theme(make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		Parent = barTrack,
	}), "BackgroundColor3", "accent")
	corner(L.fill, 2)

	-- shimmering skeleton cards
	for i = 1, 6 do
		local sc = theme(make("Frame", {
			Position = UDim2.fromOffset(8, 76 + (i - 1) * 72),
			Size = UDim2.new(1, -16, 0, 66),
			BorderSizePixel = 0,
			Parent = L.frame,
		}), "BackgroundColor3", "surface")
		corner(sc, 8)
		theme(make("UIStroke", { Thickness = 1, Transparency = 0.6, Parent = sc }), "Color", "border")
		local function bar(x, y, w, h)
			local b = theme(make("Frame", {
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.new(w.Scale, w.Offset, 0, h),
				BorderSizePixel = 0,
				Parent = sc,
			}), "BackgroundColor3", "surface2")
			corner(b, 4)
			table.insert(L.bars, { obj = b, phase = i * 0.55 })
		end
		bar(14, 10, UDim.new(0, 44), 16)
		bar(66, 10, UDim.new(0.3, 0), 16)
		bar(14, 33, UDim.new(0.72, 0), 13)
		bar(14, 51, UDim.new(0.38, 0), 9)
	end
end

APP.loaderStart = function()
	local L = APP.loader
	if L.conn then
		return
	end
	L.conn = K.Run.Heartbeat:Connect(function(dt)
		L.t += dt
		-- spinner sweeps faster in the middle of each turn
		L.grad.Rotation = (L.t * 300 + math.sin(L.t * 3) * 40) % 360
		L.disp += (scanFrac - L.disp) * math.min(1, dt * 9)
		L.fill.Size = UDim2.fromScale(math.clamp(L.disp, 0, 1), 1)
		L.pct.Text = string.format("%d%%", math.floor(L.disp * 100 + 0.5))
		L.title.Text = scanFrac >= 1 and "Finishing up" or "Scanning scripts"
		local s = APP.scan
		if s then
			L.sub.Text = string.format("%d / %d scripts  ·  %d notes found", s.seen, s.total, s.found)
		end
		for _, b in ipairs(L.bars) do
			local a = 0.5 + 0.5 * math.sin(L.t * 3.2 - b.phase)
			b.obj.BackgroundTransparency = 0.1 + 0.6 * a
		end
	end)
end

APP.updateLoader = function()
	local L = APP.loader
	if not L then
		return
	end
	local want = scanning and currentOverlay == nil
	if want and not L.on then
		L.on = true
		L.frame.Visible = true
		APP.loaderStart()
		tween(L.frame, { GroupTransparency = 0 }, 0.25)
	elseif not want and L.on then
		L.on = false
		tween(L.frame, { GroupTransparency = 1 }, 0.35)
		task.delay(0.4, function()
			if not L.on then
				L.frame.Visible = false
				if L.conn then
					L.conn:Disconnect()
					L.conn = nil
				end
			end
		end)
	end
end

APP.buildLoader()

-- ============================================================
--  Initial setup
-- ============================================================

buildChips()
applyTheme()
layout()

-- If Studio restored the panel already open, the Enabled signal never fires
task.defer(function()
	if widget.Enabled then
		layout()
		APP.onOpen()
		if not initialized then
			task.spawn(fullScan)
		end
	end
end)