local utils = require("mp.utils")
local msg = require("mp.msg")

local function icon_font()
  local fonts = (os.getenv("WINDIR") or "C:\\Windows") .. "\\Fonts\\"
  for _, f in ipairs({ { "SegoeIcons.ttf", "Segoe Fluent Icons" }, { "segmdl2.ttf", "Segoe MDL2 Assets" } }) do
    local h = io.open(fonts .. f[1], "rb")
    if h then h:close(); return f[2] end
  end
  return "Segoe MDL2 Assets"
end

local T = {
  font = "Segoe UI",
  font_semibold = "Segoe UI Semibold",
  icons = icon_font(),
  white = "FFFFFF",
  dim = "C8C8C8",
  muted = "8C8C8C",
  accent = "FF636C",
  accent_soft = "FF8A92",
  panel = "1A1414",
  panel_hi = "3A2E2E",
  danger = "5A5AFF",
}

local L = {
  back = "Back", seek_back = "Back {n}s", seek_forward = "Forward {n}s", play = "Play", pause = "Pause",
  audio = "Audio", subtitles = "Subtitles", chapters = "Chapters", next_episode = "Next episode", settings = "Settings",
  full_screen = "Full screen", off = "Off", chapter = "Chapter {n}", version = "Version",
  aspect_original = "Original", aspect_original_detail = "As the video says", aspect_flat = "Flat", aspect_scope = "Scope",
  aspect_zoom = "Zoom to fill", aspect_zoom_detail = "Crops the picture to fill the screen",
  aspect_stretch = "Stretch to fill", aspect_stretch_detail = "Distorts the picture",
  aspect_ratio = "Aspect ratio", aspect_toast = "Aspect ratio: {n}", playback_speed = "Playback speed",
  subtitle_delay = "Subtitle delay", audio_delay = "Audio delay", subtitle_size = "Subtitle size",
  search_subtitles = "Search subtitles", searching = "Searching…", no_subtitles_found = "No subtitles found",
  playback_info = "Playback info", playback_info_detail = "Codecs, bitrate, dropped frames",
  hdr_on = "HDR ON", tone_mapped = "TONE-MAPPED", muted = "Muted", press_back = "Press Back to return",
  skip_intro = "Skip intro", up_next = "Up next", starts_in = "Starts in {n} s", intro_skipped = "Intro skipped",
  play_now = "Play now", keep_watching = "Keep watching",
  mute = "Mute", unmute = "Unmute",
}

local function tr(key, n)
  local s = L[key] or key
  if n ~= nil then s = s:gsub("{n}", (tostring(n):gsub("%%", "%%%%"))) end
  return s
end

local ICON = {
  play = "\238\157\168",
  pause = "\238\157\169",
  rewind = "\238\174\158",
  forward = "\238\174\157",
  audio = "\238\163\150",
  subs = "\238\159\176",
  next = "\238\162\147",
  info = "\238\165\134",
  fullscreen = "\238\157\128",
  unfullscreen = "\238\156\191",
  check = "\238\156\190",
  back = "\238\156\171",
  settings = "\238\156\147",
  chapters = "\238\163\189",
  volume = "\238\157\167",
  mute = "\238\157\143",
  channels = "\238\159\180",
  swap = "\238\163\171",
}

local S = {
  phase = "loading", title = "", subtitle = "", message = "",
  visible = false, area = "buttons", btn = "play",
  panel = nil,
  hide_at = 0,
  tracks = { audio = {}, subs = {} },
  versions = {},
  versions_title = nil,
  sub_search = false, sub_languages = {}, sub_results = nil,
  seg = {}, intro_skipped = false, chapters = {},
  next_up = nil, next_elapsed = 0, next_last = nil, next_cancelled = false, next_choice = 1, next_img = nil,
  scrub = nil, scrub_commit_at = 0, scrub_repeat = 0, scrub_last = 0,
  mini_until = 0,
  toast = nil, toast_until = 0,
  vol_until = 0,
  flash_icon = nil, flash_until = 0,
  seek_step = 10, auto_skip_intro = false,
  video = nil, aspect = "auto",
  hits = {},
  pointer = false, hover = nil, mouse_x = 0,
}

local W, H = 1920, 1080
local overlay = mp.create_osd_overlay("ass-events")
local AUTOHIDE = 5

local function now() return mp.get_time() end
local function prop(name, def) local v = mp.get_property_native(name); if v == nil then return def end; return v end

local function chapter_list()
  if #S.chapters > 0 then return S.chapters end
  return prop("chapter-list", {})
end
local function send(...) mp.commandv("script-message", "zerk-event", ...) end

local function esc(s)
  s = tostring(s or "")
  return (s:gsub("\\", "\\\226\129\160"):gsub("{", "\\{"):gsub("\n", "\\N"))
end

local function fmt_time(sec)
  if not sec or sec < 0 then sec = 0 end
  sec = math.floor(sec + 0.5)
  local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%d:%02d", m, s)
end

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function R(v) return math.floor(v + 0.5) end

local function ev(tags, body) return "{\\bord0\\shad0\\an7" .. tags .. "}" .. body end

local function rrect(x, y, w, h, r, color, alpha, extra)
  x, y, w, h = R(x), R(y), R(w), R(h)
  r = R(math.min(r, w / 2, h / 2))
  local k = R(r * 0.4477)
  local x2, y2 = x + w, y + h
  local p = string.format(
    "m %d %d l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d",
    x + r, y, x2 - r, y, x2 - k, y, x2, y + k, x2, y + r, x2, y2 - r, x2, y2 - k, x2 - k, y2, x2 - r, y2,
    x + r, y2, x + k, y2, x, y2 - k, x, y2 - r, x, y + r, x, y + k, x + k, y, x + r, y)
  return ev(string.format("\\pos(0,0)\\1c&H%s&\\1a&H%s&%s\\p1", color, alpha or "00", extra or ""), p)
end

local function circle(cx, cy, r, color, alpha)
  return rrect(cx - r, cy - r, 2 * r, 2 * r, r, color, alpha)
end

local function text(x, y, an, size, color, body, opts)
  opts = opts or {}
  return string.format("{\\bord0\\shad0\\an%d\\pos(%d,%d)\\fn%s\\fs%d\\1c&H%s&\\1a&H%s&%s}%s",
    an, R(x), R(y), opts.font or T.font, size, color, opts.alpha or "00", opts.extra or "", body)
end

local function icon(x, y, size, color, glyph, alpha)
  return text(x, y, 5, size, color, glyph, { font = T.icons, alpha = alpha })
end

local function scrim(y1, y2, alpha, blur)
  return ev(string.format("\\pos(0,0)\\1c&H000000&\\1a&H%02X&\\blur%d\\p1", alpha, blur),
    string.format("m %d %d l %d %d l %d %d l %d %d", -200, R(y1), W + 200, R(y1), W + 200, R(y2), -200, R(y2)))
end

local function add_hit(x1, y1, x2, y2, fn, key) S.hits[#S.hits + 1] = { x1, y1, x2, y2, fn, key = key } end

local function hit_at(x, y)
  for i = #S.hits, 1, -1 do
    local h = S.hits[i]
    if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then return h end
  end
  return nil
end

local function lit(key, kb)
  if S.pointer then return S.hover == key end
  return kb
end

local function position() return S.scrub or prop("time-pos", 0) end
local function duration() return prop("duration", 0) end

local function in_intro(pos)
  local a, b = S.seg.introStart, S.seg.introEnd
  return a and b and b > a and pos >= a - 0.5 and pos < b - 1
end

local function skip_intro()
  if S.seg.introEnd then
    S.intro_skipped = true
    mp.commandv("seek", S.seg.introEnd, "absolute+exact")
  end
end

local function next_visible(pos)
  if not S.next_up or S.next_cancelled then return false end
  local dur = duration()
  local start = S.seg.creditsStart or (dur > 120 and dur - 30) or nil
  return start ~= nil and pos >= start
end

local activate_button

local function card_action(pos)
  if in_intro(pos) and not S.intro_skipped then skip_intro(); return true end
  if next_visible(pos) then send("next"); return true end
  return false
end

local function buttons()
  local paused = prop("pause", false)
  local muted = prop("mute", false)
  local list = {
    { id = "rewind", glyph = ICON.rewind, label = tr("seek_back", S.seek_step) },
    { id = "play", glyph = paused and ICON.play or ICON.pause, label = paused and tr("play") or tr("pause"), big = true },
    { id = "forward", glyph = ICON.forward, label = tr("seek_forward", S.seek_step) },
    { id = "volume", glyph = muted and ICON.mute or ICON.volume, label = muted and tr("unmute") or tr("mute") },
  }
  local right = {
    { id = "audio", glyph = ICON.audio, label = tr("audio") },
    { id = "subs", glyph = ICON.subs, label = tr("subtitles") },
  }
  if #chapter_list() > 1 then right[#right + 1] = { id = "chapters", glyph = ICON.chapters, label = tr("chapters") } end
  if S.next_up then right[#right + 1] = { id = "next", glyph = ICON.next, label = tr("next_episode") } end
  if S.versions_title and #S.versions > 1 then
    right[#right + 1] = { id = "versions", glyph = ICON.channels, label = S.versions_title }
  end
  right[#right + 1] = { id = "settings", glyph = ICON.settings, label = tr("settings") }
  right[#right + 1] = { id = "fullscreen", glyph = ICON.fullscreen, label = tr("full_screen") }
  for _, b in ipairs(right) do b.right = true; list[#list + 1] = b end
  return list
end

local function button_index(list, id)
  for i, b in ipairs(list) do if b.id == id then return i end end
  return 2
end

local open_panel

local function percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

local function track_items(kind)
  local items = {}
  if kind == "subs" then
    if S.sub_search then items[#items + 1] = { id = "subsearch", label = tr("search_subtitles"), submenu = true } end
    items[#items + 1] = { id = "subsize", label = tr("subtitle_size"), detail = percent(prop("sub-scale", 1)), submenu = true }
    local any = false
    for _, t in ipairs(S.tracks.subs) do if t.selected then any = true end end
    items[#items + 1] = { id = -1, label = tr("off"), selected = not any }
  end
  for _, t in ipairs(S.tracks[kind]) do
    items[#items + 1] = { id = t.id, label = t.label, detail = t.detail, selected = t.selected }
  end
  return items
end

local function chapter_items()
  local items, list, pos, cur = {}, chapter_list(), prop("time-pos", 0), 0
  for i, c in ipairs(list) do
    if c.time <= pos + 0.5 then cur = i end
  end
  for i, c in ipairs(list) do
    items[#items + 1] = { id = c.time, label = (c.title and c.title ~= "") and c.title or tr("chapter", i),
      detail = fmt_time(c.time), selected = i == cur }
  end
  return items
end

local speeds = { 0.5, 0.75, 1.0, 1.25, 1.5, 2.0 }

local ASPECTS = {
  { id = "auto", label = "aspect_original", detail = "aspect_original_detail" },
  { id = "16:9" },
  { id = "4:3" },
  { id = "1.85:1", detail = "aspect_flat" },
  { id = "2.35:1", detail = "aspect_scope" },
  { id = "2.39:1", detail = "aspect_scope" },
  { id = "zoom", label = "aspect_zoom", detail = "aspect_zoom_detail" },
  { id = "stretch", label = "aspect_stretch", detail = "aspect_stretch_detail" },
}

local function aspect_text(a)
  return a.label and tr(a.label) or a.id, a.detail and tr(a.detail) or nil
end

local function aspect_label(id)
  for _, a in ipairs(ASPECTS) do if a.id == id then return (aspect_text(a)) end end
  return id
end

local function set_aspect(id)
  S.aspect = id
  local override = "-1"
  if id ~= "auto" and id ~= "zoom" and id ~= "stretch" then override = id:gsub(":1$", "") end
  mp.set_property("video-aspect-override", override)
  mp.set_property_number("panscan", id == "zoom" and 1.0 or 0.0)
  mp.set_property("keepaspect", id == "stretch" and "no" or "yes")
end

local function settings_items()
  local speed = prop("speed", 1)
  local items = {}
  if #S.versions > 1 then
    local current = "?"
    for _, v in ipairs(S.versions) do if v.selected then current = v.label end end
    items[#items + 1] = { id = "version", label = tr("version"), detail = current, submenu = true }
  end
  for _, it in ipairs({
    { id = "aspect", label = tr("aspect_ratio"), detail = aspect_label(S.aspect), submenu = true },
    { id = "speed", label = tr("playback_speed"), detail = string.format("%gx", speed), submenu = true },
    { id = "subdelay", label = tr("subtitle_delay"), detail = string.format("%+.1fs", prop("sub-delay", 0)), submenu = true },
    { id = "subsize", label = tr("subtitle_size"), detail = percent(prop("sub-scale", 1)), submenu = true },
    { id = "audiodelay", label = tr("audio_delay"), detail = string.format("%+.2fs", prop("audio-delay", 0)), submenu = true },
    { id = "stats", label = tr("playback_info"), detail = tr("playback_info_detail") },
  }) do items[#items + 1] = it end
  return items
end

local function delay_items(p, step, unit)
  local cur = prop(p, 0)
  local items = {}
  for i = -10, 10 do
    local v = i * step
    items[#items + 1] = { id = v, label = string.format("%+." .. unit .. "fs", v), selected = math.abs(v - cur) < step / 2 }
  end
  return items
end

local function panel_cursor(items)
  for i, it in ipairs(items) do if it.selected then return i end end
  return 1
end

open_panel = function(kind)
  local p = { kind = kind }
  if kind == "audio" then p.title, p.items = tr("audio"), track_items("audio")
  elseif kind == "subs" then p.title, p.items = tr("subtitles"), track_items("subs")
  elseif kind == "chapters" then p.title, p.items = tr("chapters"), chapter_items()
  elseif kind == "settings" then p.title, p.items = tr("settings"), settings_items()
  elseif kind == "version" then
    p.title, p.items = S.versions_title or tr("version"), {}
    for _, v in ipairs(S.versions) do
      p.items[#p.items + 1] = { id = v.id, label = v.label, detail = v.detail, selected = v.selected }
    end
  elseif kind == "speed" then
    p.title, p.items = tr("playback_speed"), {}
    for _, s in ipairs(speeds) do p.items[#p.items + 1] = { id = s, label = string.format("%gx", s), selected = math.abs(prop("speed", 1) - s) < 0.01 } end
  elseif kind == "aspect" then
    p.title, p.items = tr("aspect_ratio"), {}
    for _, a in ipairs(ASPECTS) do
      local label, detail = aspect_text(a)
      p.items[#p.items + 1] = { id = a.id, label = label, detail = detail, selected = a.id == S.aspect }
    end
  elseif kind == "subdelay" then p.title, p.items = tr("subtitle_delay"), delay_items("sub-delay", 0.1, "1")
  elseif kind == "audiodelay" then p.title, p.items = tr("audio_delay"), delay_items("audio-delay", 0.05, "2")
  elseif kind == "subsize" then
    local cur = prop("sub-scale", 1)
    p.title, p.items = tr("subtitle_size"), {}
    for i = 0, 20 do
      local v = 0.5 + i * 0.05
      p.items[#p.items + 1] = { id = v, label = percent(v), selected = math.abs(v - cur) < 0.025 }
    end
    p.preview = function(it) mp.set_property_number("sub-scale", it.id) end
    p.revert = function() mp.set_property_number("sub-scale", cur) end
  elseif kind == "sublang" then
    p.title, p.items = tr("search_subtitles"), {}
    for _, l in ipairs(S.sub_languages) do p.items[#p.items + 1] = { id = l.id, label = l.label, submenu = true } end
  elseif kind == "subresults" then
    local r = S.sub_results
    p.title = tr("search_subtitles")
    if not r then p.items = { { label = tr("searching"), inert = true } }
    elseif r.error then p.items = { { label = r.error, inert = true } }
    elseif #(r.results or {}) == 0 then p.items = { { label = tr("no_subtitles_found"), inert = true } }
    else
      p.items = {}
      for _, it in ipairs(r.results) do p.items[#p.items + 1] = { id = it.id, label = it.label, detail = it.detail } end
    end
  end
  if not p.items or #p.items == 0 then return end
  p.cursor = panel_cursor(p.items)
  p.scroll = 1
  S.panel = p
end

local function panel_activate(item)
  local p = S.panel
  if p.kind == "audio" then send("audio", tostring(item.id)); S.panel = nil
  elseif p.kind == "subs" then
    if item.id == "subsize" or item.id == "subsearch" then open_panel(item.id == "subsize" and "subsize" or "sublang")
    else send("sub", tostring(item.id)); S.panel = nil end
  elseif p.kind == "chapters" then mp.commandv("seek", item.id, "absolute+exact"); S.panel = nil
  elseif p.kind == "settings" then
    if item.id == "stats" then mp.commandv("script-binding", "stats/display-stats-toggle"); S.panel = nil; S.visible = false
    else open_panel(item.id) end
  elseif p.kind == "version" then
    if not item.selected then send("version", tostring(item.id)) end
    S.panel = nil
  elseif p.kind == "speed" then mp.set_property_number("speed", item.id); S.panel = nil
  elseif p.kind == "aspect" then
    set_aspect(item.id); S.panel = nil
    S.toast, S.toast_until = tr("aspect_toast", item.label), now() + 2
  elseif p.kind == "subdelay" then mp.set_property_number("sub-delay", item.id); S.panel = nil
  elseif p.kind == "audiodelay" then mp.set_property_number("audio-delay", item.id); S.panel = nil
  elseif p.kind == "sublang" then
    S.sub_results = nil
    send("subsearch", item.id)
    open_panel("subresults")
  elseif p.kind == "subresults" then
    if not item.inert then send("subdownload", item.id); S.panel = nil end
  elseif p.kind == "subsize" then
    p.revert = nil
    mp.set_property_number("sub-scale", item.id)
    send("subscale", string.format("%.2f", item.id))
    S.panel = nil
  end
end

local function close_panel()
  local p = S.panel
  if p and p.revert then p.revert() end
  S.panel = nil
end

local function move_panel_cursor(p, cursor)
  if cursor == p.cursor then return end
  p.cursor = cursor
  if p.preview then p.preview(p.items[cursor]) end
end

local render
local draw_video_badges

local function draw_spinner(cx, cy, r)
  local a = (now() * 360) % 360
  local arc = {}
  local pts = {}
  for i = 0, 18 do
    local t = math.rad(i * 15)
    pts[#pts + 1] = string.format("%d %d", math.floor(r * math.cos(t)), math.floor(r * math.sin(t)))
  end
  local inner = {}
  for i = 18, 0, -1 do
    local t = math.rad(i * 15)
    inner[#inner + 1] = string.format("%d %d", math.floor((r - 6) * math.cos(t)), math.floor((r - 6) * math.sin(t)))
  end
  cx, cy = R(cx), R(cy)
  arc[1] = string.format("{\\bord0\\shad0\\an7\\pos(%d,%d)\\org(%d,%d)\\frz%d\\1c&H%s&\\p1}m %s l %s l %s",
    cx, cy, cx, cy, math.floor(a), T.white, pts[1], table.concat(pts, " ", 2), table.concat(inner, " "))
  return arc[1]
end

local function draw_progress(out, y, focused, mini)
  local m = 80
  local x1, x2 = m, W - m
  local width = x2 - x1
  local dur = duration()
  local pos = position()
  local frac = dur > 0 and clamp(pos / dur, 0, 1) or 0
  local cache = prop("demuxer-cache-time", 0)
  local cfrac = dur > 0 and clamp(cache / dur, 0, 1) or 0
  local h = focused and 10 or 6

  out[#out + 1] = rrect(x1, y - h / 2, width, h, h / 2, T.white, "C0")
  if cfrac > frac then out[#out + 1] = rrect(x1, y - h / 2, width * cfrac, h, h / 2, T.white, "90") end
  if frac > 0 then out[#out + 1] = rrect(x1, y - h / 2, math.max(h, width * frac), h, h / 2, T.accent, "00") end

  for _, c in ipairs(chapter_list()) do
    if dur > 0 and c.time > 1 and c.time < dur - 1 then
      local cx = R(x1 + width * (c.time / dur))
      local top, bottom = R(y - h / 2), R(y + h / 2)
      out[#out + 1] = ev("\\pos(0,0)\\1c&H000000&\\1a&H60&\\p1",
        string.format("m %d %d l %d %d l %d %d l %d %d", cx - 1, top, cx + 1, top, cx + 1, bottom, cx - 1, bottom))
    end
  end

  if focused then
    out[#out + 1] = circle(x1 + width * frac, y, 14, T.white)
    if S.scrub then
      out[#out + 1] = rrect(x1 + width * frac - 70, y - 72, 140, 46, 23, T.panel, "20")
      out[#out + 1] = text(x1 + width * frac, y - 49, 5, 28, T.white, fmt_time(S.scrub), { font = T.font_semibold })
    elseif S.pointer and S.hover == "seek" and dur > 0 then
      local hx = clamp(S.mouse_x, x1, x2)
      out[#out + 1] = rrect(hx - 1, y - h / 2 - 4, 2, h + 8, 1, T.white, "20")
      out[#out + 1] = rrect(hx - 70, y - 72, 140, 46, 23, T.panel, "20")
      out[#out + 1] = text(hx, y - 49, 5, 28, T.white, fmt_time((hx - x1) / width * dur), { font = T.font_semibold })
    end
  end

  local ty = y + 34
  out[#out + 1] = text(x1, ty, 4, 28, T.white, fmt_time(pos), { font = T.font_semibold })
  local remaining = dur - pos
  local right = dur > 0 and ("-" .. fmt_time(remaining)) or "--:--"
  if not mini and dur > 0 then
    local speed = prop("speed", 1)
    local ends = os.time() + math.floor(remaining / speed)
    right = right .. "   \\h·\\h   ends " .. os.date("%H:%M", ends)
  end
  out[#out + 1] = text(x2, ty, 6, 28, T.dim, right)

  add_hit(x1, y - 24, x2, y + 24, function(mx)
    if dur > 0 then mp.commandv("seek", clamp((mx - x1) / width, 0, 1) * dur, "absolute+exact") end
  end, "seek")
end

local function draw_volume_bar(out, x, y)
  local vol, muted = prop("volume", 100), prop("mute", false)
  local bw, bh = 200, 8
  local hover = S.pointer and S.hover == "volbar"
  out[#out + 1] = rrect(x, y - bh / 2, bw, bh, bh / 2, T.white, hover and "90" or "C0")
  local frac = muted and 0 or clamp(vol / 100, 0, 1)
  if frac > 0 then out[#out + 1] = rrect(x, y - bh / 2, math.max(bh, bw * frac), bh, bh / 2, T.white) end
  if hover then out[#out + 1] = circle(x + bw * frac, y, 11, T.white) end
  add_hit(x - 8, y - 24, x + bw + 8, y + 24, function(mx)
    local v = R(clamp((mx - x) / bw, 0, 1) * 100)
    mp.set_property_native("volume", v)
    mp.set_property_bool("mute", v == 0)
    S.vol_until = 0
  end, "volbar")
  return x + bw
end

local function draw_buttons(out, y)
  local list = buttons()
  local focus_area = S.area == "buttons" and not S.panel
  local x = 80
  local gap = 22
  for _, b in ipairs(list) do
    if not b.right then
      local r = b.big and 40 or 32
      local cx = x + r
      local focused = lit("btn:" .. b.id, focus_area and S.btn == b.id)
      if focused then out[#out + 1] = circle(cx, y, r, T.white) end
      out[#out + 1] = icon(cx, y, b.big and 36 or 30, focused and "141414" or T.white, b.glyph)
      if focused then out[#out + 1] = text(cx, y + r + 26, 5, 24, T.white, esc(b.label)) end
      add_hit(cx - r, y - r, cx + r, y + r, function() S.btn = b.id; S.area = "buttons"; activate_button(b.id) end, "btn:" .. b.id)
      x = cx + r + gap
      if b.id == "volume" then x = draw_volume_bar(out, x, y) + gap end
    end
  end
  local rx = W - 80
  for i = #list, 1, -1 do
    local b = list[i]
    if b.right then
      local r = 32
      local cx = rx - r
      local focused = lit("btn:" .. b.id, focus_area and S.btn == b.id)
      local glyph = b.glyph
      if b.id == "fullscreen" and prop("user-data/zerk/fullscreen", "no") == "yes" then glyph = ICON.unfullscreen end
      if focused then out[#out + 1] = circle(cx, y, r, T.white) end
      out[#out + 1] = icon(cx, y, 28, focused and "141414" or T.white, glyph)
      if focused then out[#out + 1] = text(cx, y + r + 26, 5, 24, T.white, esc(b.label)) end
      add_hit(cx - r, y - r, cx + r, y + r, function() S.btn = b.id; S.area = "buttons"; activate_button(b.id) end, "btn:" .. b.id)
      rx = cx - r - gap
    end
  end
end

local function draw_panel(out)
  local p = S.panel
  local pw = 620
  local px = W - pw
  S.hits = {}
  out[#out + 1] = ev(string.format("\\pos(0,0)\\1c&H000000&\\1a&H70&\\p1"), string.format("m 0 0 l %d 0 l %d %d l 0 %d", W, W, H, H))
  out[#out + 1] = ev(string.format("\\pos(0,0)\\1c&H%s&\\1a&H08&\\p1", T.panel), string.format("m %d 0 l %d 0 l %d %d l %d %d", px, W, W, H, px, H))
  out[#out + 1] = text(px + 56, 90, 4, 40, T.white, esc(p.title), { font = T.font_semibold })

  local row_h, top = 84, 160
  local max_rows = math.floor((H - top - 40) / row_h)
  if not p.free_scroll then
    if p.cursor < p.scroll then p.scroll = p.cursor end
    if p.cursor >= p.scroll + max_rows then p.scroll = p.cursor - max_rows + 1 end
  end
  p.scroll = clamp(p.scroll, 1, math.max(1, #p.items - max_rows + 1))

  for i = p.scroll, math.min(#p.items, p.scroll + max_rows - 1) do
    local it = p.items[i]
    local y = top + (i - p.scroll) * row_h
    local focused = lit("row:" .. i, i == p.cursor)
    if focused then out[#out + 1] = rrect(px + 28, y, pw - 56, row_h - 10, 16, T.white) end
    local fg = focused and "141414" or T.white
    local sub = focused and "505050" or T.muted
    local label_y = it.detail and (y + 26) or (y + (row_h - 10) / 2)
    out[#out + 1] = text(px + 64, label_y, 4, 30, fg, esc(it.label), { font = T.font_semibold })
    if it.detail then out[#out + 1] = text(px + 64, y + 56, 4, 22, sub, esc(it.detail)) end
    if it.selected then out[#out + 1] = icon(px + pw - 76, y + (row_h - 10) / 2, 26, focused and T.accent or T.accent_soft, ICON.check) end
    if it.submenu then out[#out + 1] = text(px + pw - 64, y + (row_h - 10) / 2, 6, 28, sub, "›") end
    add_hit(px + 28, y, W - 28, y + row_h - 10, function() p.cursor = i; panel_activate(it) end, "row:" .. i)
  end
  if #p.items > max_rows then
    local track_y, track_h = top, max_rows * row_h - 10
    local thumb_h = math.max(40, track_h * max_rows / #p.items)
    local thumb_y = track_y + (track_h - thumb_h) * (p.scroll - 1) / (#p.items - max_rows)
    out[#out + 1] = rrect(W - 14, track_y, 4, track_h, 2, T.white, "D8")
    out[#out + 1] = rrect(W - 14, thumb_y, 4, thumb_h, 2, T.white, "60")
    out[#out + 1] = text(px + pw / 2, H - 30, 5, 22, T.muted, string.format("%d / %d", p.cursor, #p.items))
  end
  table.insert(S.hits, 1, { px, 0, W, H, function() end, key = "panel" })
end

local function badge(out, x, y, label, fg, bg, bg_alpha)
  local size = 22
  local w = R(#label * size * 0.66 + 32)
  out[#out + 1] = rrect(x - w, y - 20, w, 40, 20, bg, bg_alpha)
  out[#out + 1] = text(x - w / 2, y, 5, size, fg, esc(label), { font = T.font_semibold, extra = "\\fsp1" })
  return x - w
end

draw_video_badges = function(out, x, y)
  local v = S.video
  if not v or not v.format then return end
  local hdr = v.output == "HDR"
  x = badge(out, x, y, hdr and tr("hdr_on") or tr("tone_mapped"), hdr and "141414" or T.white,
    hdr and T.white or T.panel_hi, hdr and "00" or "30") - 12
  local dv = v.format == "Dolby Vision"
  badge(out, x, y, string.upper(v.format), T.white, dv and "000000" or T.accent, dv and "20" or "00")
end

local label_w

local function draw_skip_intro(out, pos)
  local lit_now = not S.visible or (S.pointer and S.hover == "card")
  local a, b = S.seg.introStart, S.seg.introEnd
  local played = clamp((pos - a) / math.max(0.001, b - a), 0, 1)
  local label, left = tr("skip_intro"), fmt_time(math.max(0, b - pos))
  local h = 64
  local w = R(22 + 30 + 12 + label_w(label, 24) + 16 + label_w(left, 22) + 28)
  local x, y = W - 80 - w, H - 330 - h
  local fg = lit_now and "141414" or T.white
  out[#out + 1] = rrect(x - 2, y - 2, w + 4, h + 4, h / 2 + 2, T.white, lit_now and "00" or "C0")
  out[#out + 1] = rrect(x, y, w, h, h / 2, lit_now and T.white or T.panel, lit_now and "00" or "12")
  local band = string.format("\\clip(%d,%d,%d,%d)", R(x + w * played), y, x + w, y + h)
  out[#out + 1] = rrect(x, y, w, h, h / 2, T.accent, lit_now and "E0" or "B8", band)
  out[#out + 1] = icon(x + 22 + 15, y + h / 2, 26, lit_now and T.accent or T.white, ICON.next)
  local lx = x + 22 + 30 + 12
  out[#out + 1] = text(lx, y + h / 2, 4, 24, fg, esc(label), { font = T.font_semibold })
  out[#out + 1] = text(lx + label_w(label, 24) + 16, y + h / 2, 4, 22, fg, left, { font = T.font_semibold, alpha = "70" })
  add_hit(x, y, x + w, y + h, function() card_action(prop("time-pos", 0)) end, "card")
end

local OV_GREY, OV_COLOUR = 61, 62
local ov_key = nil
local function next_still(x, y, w, h, fill)
  local img = S.next_img
  if not img then return end
  local osd_w, osd_h = mp.get_osd_size()
  if not osd_h or osd_h == 0 then return end
  local k = osd_h / H
  local px, py, dw, dh = R(x * k), R(y * k), R(w * k), R(h * k)
  local cw = math.floor(img.w * fill)
  local key = table.concat({ img.grey, px, py, dw, dh, cw }, "|")
  if key == ov_key then return end
  ov_key = key
  mp.commandv("overlay-add", OV_GREY, px, py, img.grey, 0, "bgra", img.w, img.h, img.w * 4, dw, dh)
  if cw > 0 then
    mp.commandv("overlay-add", OV_COLOUR, px, py, img.colour, 0, "bgra", cw, img.h, img.w * 4, R(dw * cw / img.w), dh)
  else
    mp.commandv("overlay-remove", OV_COLOUR)
  end
end

local function hide_still()
  if not ov_key then return end
  ov_key = nil
  mp.commandv("overlay-remove", OV_GREY)
  mp.commandv("overlay-remove", OV_COLOUR)
end

label_w = function(s, size)
  local _, chars = s:gsub("[^\128-\191]", "")
  return chars * size * 0.53
end

local function draw_next_card(out, n, fill, left)
  local cw, ih, pad = 400, S.next_img and 225 or 0, 18
  local ch = ih + 156
  local x, y = W - 80 - cw, H - 330 - ch
  out[#out + 1] = rrect(x, y, cw, ch, 18, T.panel)
  add_hit(x, y, x + cw, y + ch, function() end, "next:card")
  if ih > 0 then next_still(x, y, cw, ih, fill) end
  local ty = y + ih + 14
  local label = (n.autoplay and left > 0) and tr("starts_in", math.ceil(left)) or tr("up_next")
  out[#out + 1] = text(x + pad, ty, 7, 16, T.accent_soft, esc(label), { font = T.font_semibold })
  local clip = string.format("\\q2\\clip(%d,%d,%d,%d)", x, y, x + cw - pad, y + ch)
  out[#out + 1] = text(x + pad, ty + 22, 7, 22, T.white, esc(n.title), { font = T.font_semibold, extra = clip })
  if n.subtitle then out[#out + 1] = text(x + pad, ty + 50, 7, 17, T.dim, esc(n.subtitle), { extra = clip }) end
  local by, bh, gap = ty + 80, 44, 10
  local bw = (cw - 2 * pad - gap) / 2
  local bx = x + pad
  for i, b in ipairs({
    { key = "next:play", label = tr("play_now"), glyph = ICON.play, primary = true, fn = function() send("next") end },
    { key = "next:keep", label = tr("keep_watching"), fn = function() S.next_cancelled = true; send("next-cancel") end },
  }) do
    local on = lit(b.key, not S.visible and S.next_choice == i)
    local bg, fg, alpha = T.panel_hi, T.white, "40"
    if on then bg, fg, alpha = T.white, "141414", "00" elseif b.primary then bg, alpha = T.accent, "00" end
    out[#out + 1] = rrect(bx, by, bw, bh, bh / 2, bg, alpha)
    local glyph_w = b.glyph and 26 or 0
    local size = math.max(12, math.min(18, math.floor(18 * (bw - 16 - glyph_w) / math.max(1, label_w(b.label, 18)))))
    local lx = bx + (bw - glyph_w - label_w(b.label, size)) / 2
    if b.glyph then
      out[#out + 1] = icon(lx + 10, by + bh / 2, 20, fg, b.glyph)
      lx = lx + glyph_w
    end
    local inside = string.format("\\clip(%d,%d,%d,%d)", R(bx + 10), R(by), R(bx + bw - 10), R(by + bh))
    out[#out + 1] = text(lx, by + bh / 2, 4, size, fg, esc(b.label), { font = T.font_semibold, extra = inside })
    add_hit(bx, by, bx + bw, by + bh, b.fn, b.key)
    bx = bx + bw + gap
  end
end

local function draw_volume(out)
  local vol, max = prop("volume", 100), math.max(1, prop("volume-max", 150))
  local muted = prop("mute", false)
  local w, h = 600, 76
  local x, y = W / 2 - w / 2, 56
  local cy = y + h / 2
  out[#out + 1] = rrect(x, y, w, h, h / 2, T.panel, "10")
  out[#out + 1] = icon(x + 48, cy, 30, muted and T.muted or T.white, muted and ICON.mute or ICON.volume)
  local bx, bw, bh = x + 92, w - 92 - 124, 12
  out[#out + 1] = rrect(bx, cy - bh / 2, bw, bh, bh / 2, T.white, "C0")
  local frac = clamp(vol / max, 0, 1)
  if frac > 0 then
    out[#out + 1] = rrect(bx, cy - bh / 2, math.max(bh, bw * frac), bh, bh / 2, muted and T.muted or T.accent)
  end
  if max > 100 then
    local tx = R(bx + bw * 100 / max)
    out[#out + 1] = rrect(tx - 1, cy - 13, 3, 26, 1, T.white, muted and "A0" or "40")
  end
  out[#out + 1] = text(x + w - 36, cy, 6, 28, muted and T.muted or T.white,
    muted and tr("muted") or string.format("%d%%", R(vol)), { font = T.font_semibold })
end

local function draw_digits(out)
  if not S.digits or S.digits == "" then return end
  local w, h = 60 + 44 * #S.digits, 96
  local x, y = W - 72 - w, 56
  out[#out + 1] = rrect(x, y, w, h, 18, "000000", "60")
  out[#out + 1] = text(x + w / 2, y + h / 2, 5, 64, T.white, S.digits, { font = T.font_semibold })
end

local sub_base
local function lift_subtitles(frac)
  if frac > 0 then
    sub_base = sub_base or prop("sub-margin-y", 22)
    local want = math.max(sub_base, R(720 * frac))
    if want ~= S.sub_margin then
      S.sub_margin = want
      mp.set_property_number("sub-margin-y", want)
    end
  elseif sub_base then
    mp.set_property_number("sub-margin-y", sub_base)
    sub_base, S.sub_margin = nil, nil
  end
end

render = function()
  local osd_w, osd_h = mp.get_osd_size()
  if osd_w and osd_h and osd_w > 0 and osd_h > 0 then W = math.floor(H * osd_w / osd_h) end
  local shown = S.phase .. (S.visible and "+controls" or "") .. (S.panel and ("+panel:" .. (S.panel.kind or "?")) or "")
  if shown ~= S.logged_shown then
    S.logged_shown = shown
    msg.info(string.format("osd %s (window %sx%s, layout %dx%d)", shown, tostring(osd_w), tostring(osd_h), W, H))
  end
  overlay.res_x, overlay.res_y = W, H
  S.hits = {}
  local out = {}
  local t = now()

  if S.phase == "loading" or S.phase == "error" then
    lift_subtitles(0)
    hide_still()
    out[#out + 1] = ev("\\pos(0,0)\\1c&H000000&\\p1", string.format("m 0 0 l %d 0 l %d %d l 0 %d", W, W, H, H))
    out[#out + 1] = text(W / 2, H / 2 - 120, 5, 48, T.white, esc(S.title), { font = T.font_semibold })
    if S.subtitle ~= "" then out[#out + 1] = text(W / 2, H / 2 - 66, 5, 28, T.dim, esc(S.subtitle)) end
    if S.phase == "loading" then
      out[#out + 1] = draw_spinner(W / 2, H / 2 + 40, 34)
    else
      out[#out + 1] = text(W / 2, H / 2 + 30, 5, 30, "8C8CFF", esc(S.message))
      out[#out + 1] = text(W / 2, H / 2 + 90, 5, 24, T.muted, tr("press_back"))
    end
    draw_digits(out)
    overlay.data = table.concat(out, "\n")
    overlay:update()
    return
  end

  local pos = position()
  local buffering = prop("paused-for-cache", false)

  lift_subtitles(S.visible and 0.34 or ((t < S.mini_until or S.scrub) and 0.13 or 0))
  if S.visible then
    out[#out + 1] = scrim(H - 330, H + 200, 0x28, 110)
    out[#out + 1] = scrim(-200, 90, 0x50, 70)
    out[#out + 1] = text(80, H - 300, 1, 52, T.white, esc(S.title), { font = T.font_semibold })
    if S.subtitle ~= "" then out[#out + 1] = text(80, H - 248, 1, 30, T.dim, esc(S.subtitle)) end
    out[#out + 1] = text(W - 80, 70, 6, 34, T.white, os.date("%H:%M"), { font = T.font_semibold })
    draw_video_badges(out, W - 80 - 120, 70)
    local back_focused = lit("back", S.area == "top" and not S.panel)
    if back_focused then out[#out + 1] = circle(112, 70, 32, T.white) end
    out[#out + 1] = icon(112, 70, 28, back_focused and "141414" or T.white, ICON.back)
    out[#out + 1] = text(160, 70, 4, 28, T.white, tr("back"), { font = T.font_semibold, alpha = back_focused and "00" or "60" })
    add_hit(72, 30, 260, 110, function() send("back") end, "back")
    draw_progress(out, H - 196, lit("seek", S.area == "seek" and not S.panel), false)
    draw_buttons(out, H - 92)
  elseif t < S.mini_until or S.scrub then
    out[#out + 1] = scrim(H - 150, H + 200, 0x40, 70)
    draw_progress(out, H - 96, true, true)
  end

  local still = false
  if not S.panel then
    if in_intro(pos) and not S.intro_skipped then
      draw_skip_intro(out, pos)
    elseif next_visible(pos) then
      local n = S.next_up
      if S.next_last and not prop("pause", false) then S.next_elapsed = S.next_elapsed + (t - S.next_last) end
      S.next_last = t
      local cd = n.countdown or 10
      local left = math.max(0, cd - S.next_elapsed)
      draw_next_card(out, n, n.autoplay and clamp(S.next_elapsed / cd, 0, 1) or 1, left)
      still = S.next_img ~= nil
      if n.autoplay and left <= 0 and not S.next_fired then
        S.next_fired = true
        send("next")
      end
    else
      S.next_last = nil
    end
  end
  if not still then hide_still() end

  if buffering and not prop("pause", false) then out[#out + 1] = draw_spinner(W / 2, H / 2, 38) end

  if S.flash_icon and t < S.flash_until then
    local fade = math.floor(clamp(1 - (S.flash_until - t) / 0.6, 0, 1) * 255)
    out[#out + 1] = circle(W / 2, H / 2, 72, "000000", string.format("%02X", math.max(0x60, fade)))
    out[#out + 1] = icon(W / 2, H / 2, 56, T.white, S.flash_icon, string.format("%02X", fade))
  end
  draw_digits(out)

  if t < S.vol_until then
    draw_volume(out)
  elseif S.toast and t < S.toast_until then
    out[#out + 1] = rrect(W / 2 - 360, 60, 720, 64, 32, T.panel, "18")
    out[#out + 1] = text(W / 2, 92, 5, 26, T.white, esc(S.toast))
  end

  if S.panel then draw_panel(out) end

  local data = table.concat(out,"\n")
  if data ~= overlay.data or W ~= S.drawn_w then
    overlay.data = data
    S.drawn_w = W
    overlay:update()
  end
end

local tick
local tick_interval = 0

local function wanted_interval()
  local t = now()
  if S.phase == "loading" or t < S.flash_until or prop("paused-for-cache", false) then return 0.033 end
  local pos = prop("time-pos", 0)
  if next_visible(pos) and S.next_up and S.next_up.autoplay then return 0.04 end
  if S.visible or S.panel or S.scrub or t < S.mini_until or t < S.toast_until or t < S.vol_until
    or in_intro(pos) or next_visible(pos) then return 0.25 end
  return nil
end

local function schedule()
  local iv = wanted_interval()
  if iv == nil then
    if tick_interval ~= 0 then tick:kill(); tick_interval = 0 end
  elseif iv ~= tick_interval then
    tick:kill(); tick.timeout = iv; tick:resume(); tick_interval = iv
  end
end

local function refresh() render(); schedule() end

tick = mp.add_periodic_timer(0.25, function()
  local t = now()
  local hovering = S.pointer and S.hover ~= nil
  if S.visible and not S.panel and not hovering and not prop("pause", false) and S.hide_at > 0 and t > S.hide_at then
    S.visible = false
    S.hover = nil
  end
  if S.scrub and t > S.scrub_commit_at then
    mp.commandv("seek", S.scrub, "absolute+exact")
    S.scrub = nil
    S.mini_until = t + 1.5
  end
  refresh()
end)
tick:kill()

local function touch()
  S.hide_at = now() + AUTOHIDE
end

local function show()
  if not S.visible then
    S.area, S.btn = "buttons", "play"
  end
  S.visible = true
  touch()
  refresh()
end

local function flash(glyph)
  S.flash_icon, S.flash_until = glyph, now() + 0.6
end

local function toggle_pause()
  local paused = not prop("pause", false)
  mp.set_property_bool("pause", paused)
  flash(paused and ICON.pause or ICON.play)
  refresh()
end

local function seek_relative(sec)
  mp.commandv("seek", sec, "relative")
  S.mini_until = now() + 1.5
  refresh()
end

activate_button = function(id)
  touch()
  if id == "play" then toggle_pause()
  elseif id == "rewind" then seek_relative(-S.seek_step)
  elseif id == "forward" then seek_relative(S.seek_step)
  elseif id == "audio" or id == "subs" or id == "chapters" or id == "settings" then open_panel(id)
  elseif id == "versions" then open_panel("version")
  elseif id == "next" then send("next")
  elseif id == "fullscreen" then send("fullscreen")
  elseif id == "volume" then mp.commandv("cycle", "mute")
  end
  render()
end

local function scrub(dir)
  local dur = duration()
  if dur <= 0 then return end
  local t = now()
  if t - S.scrub_last < 0.35 then S.scrub_repeat = S.scrub_repeat + 1 else S.scrub_repeat = 0 end
  S.scrub_last = t
  local step = S.seek_step
  if S.scrub_repeat > 24 then step = 120 elseif S.scrub_repeat > 12 then step = 60 elseif S.scrub_repeat > 5 then step = 30 end
  S.scrub = clamp((S.scrub or prop("time-pos", 0)) + dir * step, 0, dur - 1)
  S.scrub_commit_at = t + 0.9
  touch()
  refresh()
end

local function commit_scrub()
  if S.scrub then
    mp.commandv("seek", S.scrub, "absolute+exact")
    S.scrub = nil
  end
end

local function on_key(name)
  return function(info)
    if info and info.event == "up" then return end
    msg.verbose("key " .. name .. " (phase " .. S.phase .. ", controls " .. tostring(S.visible) .. ")")
    if S.zap and not S.panel and not S.visible and (name == "up" or name == "down") then
      send("channel", name == "up" and "+1" or "-1")
      return
    end
    local pos = prop("time-pos", 0)
    if S.phase ~= "playing" then
      if name == "back" then send("back") end
      return
    end
    S.pointer = false

    if S.panel then
      local p = S.panel
      p.free_scroll = false
      if name == "up" then move_panel_cursor(p, math.max(1, p.cursor - 1))
      elseif name == "down" then move_panel_cursor(p, math.min(#p.items, p.cursor + 1))
      elseif name == "ok" or name == "right" then panel_activate(p.items[p.cursor])
      elseif name == "back" or name == "left" then close_panel()
      end
      touch(); refresh()
      return
    end

    if not S.visible then
      local next_up = next_visible(pos) and not (in_intro(pos) and not S.intro_skipped)
      if next_up and (name == "left" or name == "right") then S.next_choice = name == "left" and 1 or 2
      elseif name == "left" then seek_relative(-S.seek_step)
      elseif name == "right" then seek_relative(S.seek_step)
      elseif next_up and name == "ok" then
        if S.next_choice == 1 then send("next") else S.next_cancelled = true; send("next-cancel") end
      elseif name == "ok" and S.zap then
        open_panel("version")
        touch()
      elseif name == "ok" then
        if not card_action(pos) then show() end
      elseif name == "up" or name == "down" then show()
      elseif name == "back" then
        if next_visible(pos) then S.next_cancelled = true; send("next-cancel")
        else send("back") end
      end
      refresh()
      return
    end

    touch()
    if S.area == "top" then
      if name == "ok" then send("back")
      elseif name == "down" then S.area = "seek"
      elseif name == "back" then S.visible = false
      end
    elseif S.area == "seek" then
      if name == "left" then scrub(-1)
      elseif name == "right" then scrub(1)
      elseif name == "ok" then commit_scrub()
      elseif name == "down" then commit_scrub(); S.area = "buttons"
      elseif name == "up" then commit_scrub(); S.area = "top"
      elseif name == "back" then
        if S.scrub then S.scrub = nil else S.visible = false end
      end
    else
      local list = buttons()
      local i = button_index(list, S.btn)
      if name == "left" then S.btn = list[math.max(1, i - 1)].id
      elseif name == "right" then S.btn = list[math.min(#list, i + 1)].id
      elseif name == "up" then S.area = "seek"
      elseif name == "ok" then activate_button(S.btn)
      elseif name == "back" then S.visible = false
      elseif name == "down" then
      end
    end
    refresh()
  end
end

local bindings = {
  up = { "UP", "GAMEPAD_DPAD_UP", "KP8" },
  down = { "DOWN", "GAMEPAD_DPAD_DOWN", "KP2" },
  left = { "LEFT", "GAMEPAD_DPAD_LEFT", "KP4" },
  right = { "RIGHT", "GAMEPAD_DPAD_RIGHT", "KP6" },
  ok = { "ENTER", "KP_ENTER", "GAMEPAD_ACTION_DOWN" },
  back = { "ESC", "BS", "GAMEPAD_ACTION_RIGHT", "GAMEPAD_BACK", "MBTN_BACK" },
}
for name, keys in pairs(bindings) do
  for i, key in ipairs(keys) do
    mp.add_forced_key_binding(key, "zerk-" .. name .. i, on_key(name), { repeatable = true, complex = true })
  end
end

local function simple(keys, fn)
  for i, key in ipairs(keys) do mp.add_forced_key_binding(key, "zerk-s-" .. key .. i, fn, { repeatable = true }) end
end

simple({ "SPACE", "p", "PLAYPAUSE", "GAMEPAD_START" }, function() if S.phase == "playing" then toggle_pause() end end)
simple({ "PLAY" }, function() mp.set_property_bool("pause", false); flash(ICON.play) end)
simple({ "PAUSE" }, function() mp.set_property_bool("pause", true); flash(ICON.pause) end)
simple({ "STOP" }, function() send("back") end)

simple({ "PGUP" }, function() if S.zap then send("channel", "+1") end end)
simple({ "PGDWN" }, function() if S.zap then send("channel", "-1") end end)
S.digits = ""
local digits_timer
local function type_digit(d)
  if not S.zap then return end
  if digits_timer then digits_timer:kill() end
  S.digits = S.digits .. d
  local function commit()
    if S.digits ~= "" then send("channel", "n:" .. S.digits) end
    S.digits = ""
    refresh()
  end
  if #S.digits >= 4 then commit() else digits_timer = mp.add_timeout(1.5, commit) end
  refresh()
end
for d = 0, 9 do
  simple({ tostring(d), "KP" .. d }, function() type_digit(tostring(d)) end)
end
simple({ "FORWARD", "GAMEPAD_RIGHT_SHOULDER", "ctrl+RIGHT" }, function() seek_relative(30) end)
simple({ "REWIND", "GAMEPAD_LEFT_SHOULDER", "ctrl+LEFT" }, function() seek_relative(-30) end)
simple({ "NEXT" }, function() if S.next_up then send("next") end end)
simple({ "f", "F11" }, function() send("fullscreen") end)
local function show_volume()
  S.vol_until = now() + 1.5
  S.toast_until = 0
  refresh()
end
simple({ "m", "MUTE" }, function()
  mp.commandv("cycle", "mute")
  show_volume()
end)
local function volume(delta)
  if delta > 0 and prop("mute", false) then mp.set_property_bool("mute", false) end
  mp.commandv("add", "volume", delta)
  show_volume()
end
simple({ "+", "=", "VOLUME_UP" }, function() volume(5) end)
simple({ "-", "VOLUME_DOWN" }, function() volume(-5) end)
simple({ "a" }, function() if S.phase == "playing" then show(); open_panel("audio"); render() end end)
simple({ "s", "c" }, function() if S.phase == "playing" then show(); open_panel("subs"); render() end end)
simple({ "i" }, function() mp.commandv("script-binding", "stats/display-stats-toggle") end)

local function mouse_virtual()
  local mx, my = mp.get_mouse_pos()
  local osd_w, osd_h = mp.get_osd_size()
  if not osd_w or osd_w == 0 then return mx, my end
  return mx * W / osd_w, my * H / osd_h
end

local function update_hover()
  local x, y = mouse_virtual()
  local moved = x ~= S.mouse_x
  S.mouse_x = x
  local h = hit_at(x, y)
  local key = h and h.key or nil
  local changed = key ~= S.hover
  S.hover = key
  if key then
    local btn = key:match("^btn:(.+)$")
    local row = key:match("^row:(%d+)$")
    if key == "next:play" then S.next_choice = 1
    elseif key == "next:keep" then S.next_choice = 2
    elseif btn then S.btn, S.area = btn, "buttons"
    elseif row and S.panel then move_panel_cursor(S.panel, tonumber(row))
    elseif key == "back" then S.area = "top"
    elseif key == "seek" then S.area = "seek"
    end
  end
  return changed or (key == "seek" and moved)
end

mp.add_forced_key_binding("MOUSE_MOVE", "zerk-mouse-move", function()
  if S.phase ~= "playing" then return end
  local appeared = not S.visible or not S.pointer
  if not S.visible then
    S.area = "buttons"
  end
  S.visible = true
  S.pointer = true
  touch()
  if appeared then render() end
  if update_hover() or appeared then render() end
  schedule()
end)

mp.add_forced_key_binding("MOUSE_LEAVE", "zerk-mouse-leave", function()
  if S.hover then S.hover = nil; refresh() end
end)

mp.add_forced_key_binding("MBTN_LEFT", "zerk-click", function()
  if S.phase ~= "playing" then return end
  S.pointer = true
  local x, y = mouse_virtual()
  local h = hit_at(x, y)
  if h then
    h[5](x, y)
    touch(); render(); update_hover(); refresh()
    return
  end
  if S.panel then close_panel(); refresh(); return end
  toggle_pause()
end)
mp.add_forced_key_binding("MBTN_LEFT_DBL", "zerk-dblclick", function() send("fullscreen") end)
mp.add_forced_key_binding("MBTN_RIGHT", "zerk-rclick", function()
  if S.panel then close_panel() elseif S.visible then S.visible = false else show() end
  refresh()
end)

local function wheel(dir)
  if S.phase ~= "playing" then return end
  local p = S.panel
  if p then
    S.pointer = true
    p.free_scroll = true
    p.scroll = p.scroll + dir
    touch()
    render()
    if update_hover() then render() end
    schedule()
    return
  end
  volume(-5 * dir)
end
simple({ "WHEEL_UP" }, function() wheel(-1) end)
simple({ "WHEEL_DOWN" }, function() wheel(1) end)

local function json(raw)
  if not raw or raw == "" or raw == "null" then return nil end
  return utils.parse_json(raw)
end

mp.register_script_message("state", function(raw)
  local s = json(raw) or {}
  local was = S.phase
  S.phase = s.phase or S.phase
  S.title = s.title or S.title
  S.subtitle = s.subtitle or S.subtitle
  S.message = s.message or ""
  if S.phase == "playing" and was ~= "playing" then
    S.intro_skipped, S.next_cancelled, S.next_fired = false, false, false
    S.next_elapsed, S.next_last, S.next_choice = 0, nil, 1
    S.panel, S.scrub = nil, nil
    show()
  end
  refresh()
end)

mp.register_script_message("tracks", function(raw)
  local t = json(raw) or {}
  S.tracks = { audio = t.audio or {}, subs = t.subs or {} }
  if S.panel and (S.panel.kind == "audio" or S.panel.kind == "subs") then open_panel(S.panel.kind) end
  render()
end)

mp.register_script_message("versions", function(raw)
  S.versions = json(raw) or {}
end)

mp.register_script_message("chapters", function(raw)
  S.chapters = json(raw) or {}
  if S.panel and S.panel.kind == "chapters" then open_panel("chapters") end
  refresh()
end)

mp.register_script_message("segments", function(raw)
  S.seg = json(raw) or {}
  S.intro_skipped = false
  refresh()
end)

mp.register_script_message("next", function(raw)
  S.next_up = json(raw)
  S.next_elapsed, S.next_last, S.next_fired, S.next_cancelled, S.next_choice = 0, nil, false, false, 1
  S.next_img = nil
  refresh()
end)

mp.register_script_message("next-image", function(raw)
  local img = json(raw)
  if img and S.next_up and S.next_up.image == img.url then
    S.next_img = img
    refresh()
  end
end)

mp.register_script_message("config", function(raw)
  local c = json(raw) or {}
  S.seek_step = c.seekStep or S.seek_step
  S.auto_skip_intro = c.autoSkipIntro or false
  S.versions_title = c.versionsTitle
  S.zap = c.zap or false
  S.sub_search = c.subtitleSearch or false
  S.sub_languages = c.subLanguages or {}
end)

mp.register_script_message("subsearch", function(raw)
  S.sub_results = json(raw) or {}
  if S.panel and S.panel.kind == "subresults" then open_panel("subresults") end
  refresh()
end)

mp.register_script_message("video", function(raw)
  S.video = json(raw)
  render()
end)

mp.register_script_message("strings", function(raw)
  for k, v in pairs(json(raw) or {}) do L[k] = v end
  render()
end)

mp.register_script_message("toast", function(msg)
  S.toast, S.toast_until = msg, now() + 2.5
  refresh()
end)

local last_pos_render = 0
mp.observe_property("time-pos", "number", function(_, pos)
  if not pos then return end
  if S.auto_skip_intro and not S.intro_skipped and in_intro(pos) then
    skip_intro()
    S.toast, S.toast_until = tr("intro_skipped"), now() + 2
  end
  if now() - last_pos_render > 0.5 then
    last_pos_render = now()
    schedule()
  end
end)
mp.observe_property("pause", "bool", function() if S.visible then touch() end; refresh() end)
mp.observe_property("paused-for-cache", "bool", function() refresh() end)
mp.observe_property("osd-dimensions", "native", function() render() end)
mp.observe_property("user-data/zerk/fullscreen", "native", function() render() end)

msg.info("osd loaded; icon font: " .. T.icons)
render()
send("ready")
