local utils = require("mp.utils")
local msg = require("mp.msg")

local WINDOWS = package.config:sub(1, 1) == "\\"

local function icon_font()
  if not WINDOWS then return "Material Icons" end
  local fonts = (os.getenv("WINDIR") or "C:\\Windows") .. "\\Fonts\\"
  for _, f in ipairs({ { "SegoeIcons.ttf", "Segoe Fluent Icons" }, { "segmdl2.ttf", "Segoe MDL2 Assets" } }) do
    local h = io.open(fonts .. f[1], "rb")
    if h then h:close(); return f[2] end
  end
  return "Segoe MDL2 Assets"
end

local T = {
  font = WINDOWS and "Segoe UI" or "Noto Sans",
  font_semibold = WINDOWS and "Segoe UI Semibold" or "Noto Sans Medium",
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
  full_screen = "Full screen", off = "Off", chapter = "Chapter {n}", version = "Version", quality = "Quality",
  aspect_original = "Original", aspect_original_detail = "As the video says", aspect_flat = "Flat", aspect_scope = "Scope",
  aspect_zoom = "Zoom to fill", aspect_zoom_detail = "Crops the picture to fill the screen",
  aspect_stretch = "Stretch to fill", aspect_stretch_detail = "Distorts the picture",
  aspect_ratio = "Aspect ratio", aspect_toast = "Aspect ratio: {n}", playback_speed = "Playback speed",
  subtitle_delay = "Subtitle delay", audio_delay = "Audio delay", subtitle_size = "Subtitle size", slider_hint = "Left and right change it. OK keeps it, Back cancels.",
  search_subtitles = "Search subtitles", searching = "Searching…", no_subtitles_found = "No subtitles found",
  playback_info = "Playback info", playback_info_detail = "Codecs, bitrate, dropped frames",
  info_stream = "Received stream", info_video_decoder = "Video decoder", info_dropped = "Dropped frames",
  info_buffer_ahead = "Buffered ahead", info_audio_output = "Audio output", info_bitstream = "Bitstream",
  info_decoded = "Decoded", info_hardware = "Hardware", info_software = "Software",
  hdr_on = "HDR ON", tone_mapped = "TONE-MAPPED", muted = "Muted", press_back = "Press Back to return",
  skip_intro = "Skip intro", skip_credits = "Skip credits", up_next = "Up next", starts_in = "Starts in {n} s", intro_skipped = "Intro skipped",
  play_now = "Play now", keep_watching = "Keep watching",
  mute = "Mute", unmute = "Unmute",
  stereo_downmix = "Stereo downmix", stereo_downmix_detail = "Clearer voices on TV speakers", on = "On",
}

local function tr(key, n)
  local s = L[key] or key
  if n ~= nil then s = s:gsub("{n}", (tostring(n):gsub("%%", "%%%%"))) end
  return s
end

local ICON = WINDOWS and {
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
} or {
  play = "\238\147\139",
  pause = "\238\145\188",
  rewind = "\238\137\153",
  forward = "\238\137\152",
  audio = "\238\130\182",
  subs = "\238\133\172",
  next = "\238\150\189",
  info = "\238\140\188",
  fullscreen = "\238\139\139",
  unfullscreen = "\238\139\140",
  check = "\238\133\150",
  back = "\238\130\146",
  settings = "\238\149\191",
  chapters = "\238\142\132",
  volume = "\238\155\133",
  mute = "\238\155\132",
  channels = "\238\154\165",
  swap = "\238\152\165",
}

local S = {
  phase = "loading", title = "", subtitle = "", message = "",
  visible = false, area = "buttons", btn = "play",
  panel = nil,
  hide_at = 0,
  tracks = { audio = {}, subs = {} },
  versions = {},
  info = nil,
  versions_title = nil,
  quality = nil,
  downmix = nil,
  trick = nil, trick_img = nil, trick_req = nil,
  trick_filmstrip = false, trick_size = 17, trick_distance = 10, trick_follow = true, trick_pause = false,
  scrub_paused = false,
  sub_search = false, sub_languages = {}, sub_results = nil,
  seg = {}, intro_skipped = false, chapters = {},
  next_up = nil, next_elapsed = 0, next_last = nil, next_cancelled = false, next_choice = 1, next_img = nil,
  scrub = nil, scrub_commit_at = 0, scrub_repeat = 0, scrub_last = 0,
  mini_until = 0,
  toast = nil, toast_until = 0, toast_img = nil,
  vol_until = 0,
  flash_icon = nil, flash_until = 0,
  seek_fwd = 10, seek_back = 10, skip_intro = "button", skip_credits = "button", credits_done = false,
  video = nil, aspect = "auto", default_aspect = "auto",
  scope = 0, anamorphic = 1, autocrop = false, crop = nil, margin = 0, crop_box = nil, full_ratio = nil,
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

local function intro_visible(pos)
  return S.skip_intro == "button" and in_intro(pos) and not S.intro_skipped
end

local function credits_start()
  if S.skip_credits == "off" then return nil end
  return S.seg.creditsStart
end

local function in_credits(pos)
  local start, dur = credits_start(), duration()
  return start ~= nil and dur > 0 and pos >= start and pos < dur - 2
end

local function credits_visible(pos)
  return S.skip_credits == "button" and not S.next_up and not S.credits_done and in_credits(pos)
end

local function skip_credits()
  S.credits_done = true
  send("credits")
end

local function next_visible(pos)
  if not S.next_up or S.next_cancelled then return false end
  local dur = duration()
  local start = credits_start() or (dur > 120 and dur - 30) or nil
  return start ~= nil and pos >= start
end

local activate_button

local function card_action(pos)
  if intro_visible(pos) then skip_intro(); return true end
  if credits_visible(pos) then skip_credits(); return true end
  if next_visible(pos) then send("next"); return true end
  return false
end

local function buttons()
  local paused = prop("pause", false)
  local muted = prop("mute", false)
  local list = {
    { id = "rewind", glyph = ICON.rewind, label = tr("seek_back", S.seek_back) },
    { id = "play", glyph = paused and ICON.play or ICON.pause, label = paused and tr("play") or tr("pause"), big = true },
    { id = "forward", glyph = ICON.forward, label = tr("seek_forward", S.seek_fwd) },
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

local function has_filter(label)
  for _, f in ipairs(mp.get_property_native("af", {})) do
    if f.label == label then return true end
  end
  return false
end

local function on_off(on) return on and tr("on") or tr("off") end

local function set_downmix(on)
  local d = S.downmix
  d.on = on
  local label = "@" .. d.label
  if on then
    mp.set_property("audio-spdif", "")
    mp.set_property("audio-channels", "stereo")
    if not has_filter(d.label) then mp.commandv("af", "add", label .. ":" .. d.af) end
  else
    if has_filter(d.label) then mp.commandv("af", "remove", label) end
    mp.set_property("audio-channels", "auto")
    mp.set_property("audio-spdif", d.spdif)
  end
  msg.info("stereo downmix " .. (on and "on" or "off"))
end

local function track_items(kind)
  local items = {}
  if kind == "subs" then
    if S.sub_search then items[#items + 1] = { id = "subsearch", label = tr("search_subtitles"), submenu = true } end
    items[#items + 1] = { id = "subsize", label = tr("subtitle_size"), detail = percent(prop("sub-scale", 1)), submenu = true }
    items[#items + 1] = { id = "subdelay", label = tr("subtitle_delay"), detail = string.format("%+.1fs", prop("sub-delay", 0)), submenu = true }
    local any = false
    for _, t in ipairs(S.tracks.subs) do if t.selected then any = true end end
    items[#items + 1] = { id = -1, label = tr("off"), selected = not any }
  end
  if kind == "audio" and S.downmix then
    items[#items + 1] = { id = "downmix", label = tr("stereo_downmix"),
      detail = on_off(S.downmix.on) .. "  ·  " .. tr("stereo_downmix_detail") }
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

local apply_crop

local function plain_override(id)
  if id == "stretch" then return "-1" end
  local a, b = id:match("^([%d%.]+):([%d%.]+)$")
  local ratio = a and tonumber(a) / tonumber(b) or nil
  if S.anamorphic > 1 then
    local base = ratio or prop("video-dec-params/aspect", nil)
    if base then return string.format("%.4f", base / S.anamorphic) end
  end
  return ratio and string.format("%.4f", ratio) or "-1"
end

local function set_aspect(id)
  S.aspect = id
  mp.set_property("keepaspect", id == "stretch" and "no" or "yes")
  apply_crop()
end

local band_f, band_oy = 1, 0

local function update_band()
  local ow, oh = mp.get_osd_size()
  local f = 1
  if S.scope > 0 and S.anamorphic <= 1 and ow and oh and oh > 0 then
    local win = ow / oh
    if S.scope > win + 0.01 then f = win / S.scope end
  end
  band_f = f
  local m = (1 - f) / 2
  if math.abs(m - S.margin) > 0.0005 then
    S.margin = m
    mp.set_property_number("video-margin-ratio-top", m)
    mp.set_property_number("video-margin-ratio-bottom", m)
    mp.set_property("sub-use-margins", m > 0 and "no" or "yes")
    msg.info(string.format("screen area %.3f of the window height (scope %.2f)", f, S.scope))
  end
end

local function shift_y(data, oy)
  if oy == 0 then return data end
  data = data:gsub("\\pos%(([%-%d%.]+),([%-%d%.]+)%)", function(x, y)
    return string.format("\\pos(%s,%d)", x, R(tonumber(y) + oy))
  end)
  return (data:gsub("\\clip%(([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)%)", function(a, b, c, d)
    return string.format("\\clip(%s,%d,%s,%d)", a, R(tonumber(b) + oy), c, R(tonumber(d) + oy))
  end))
end

local CROP = { threshold = 24, samples = 40 }

local GPU = { path = nil, loaded = false, failed = false, opts = {}, props = {}, epoch = 0, played = 0, timer = nil }
local FREEZE_AFTER = 180

do
  local source = debug.getinfo(1, "S").source or ""
  if source:sub(1, 1) == "@" then
    local path = utils.join_path((utils.split_path(source:sub(2))), "zerk_bars.hook")
    if utils.file_info(path) then GPU.path = path end
  end
end

local function set_once(name, value)
  if GPU.props[name] == value then return end
  GPU.props[name] = value
  mp.set_property(name, value)
end

local function shader_opt(key, value)
  local entry = key .. "=" .. value
  if GPU.opts[key] == entry then return end
  GPU.opts[key] = entry
  mp.commandv("change-list", "glsl-shader-opts", "add", entry)
end

local function gpu_bars()
  return S.autocrop and GPU.path ~= nil and not GPU.failed and prop("current-vo", "") == "gpu-next"
    and (S.aspect == "auto" or S.aspect == "zoom")
end

local function bars_shader(on)
  if on == GPU.loaded then return end
  GPU.loaded = on
  if on then
    if GPU.played >= FREEZE_AFTER then GPU.played = FREEZE_AFTER - 10 end
    shader_opt("zb_freeze", "0")
    mp.commandv("change-list", "glsl-shaders", "append", GPU.path)
    msg.info("black bars: detecting on the GPU")
  else
    mp.commandv("change-list", "glsl-shaders", "remove", GPU.path)
    msg.info("black bars: GPU detection off")
  end
end

local function bars_tick()
  if not GPU.loaded or S.autocrop_mode ~= "start" or S.phase ~= "playing" then return end
  if prop("pause", false) or prop("paused-for-cache", false) or GPU.played >= FREEZE_AFTER then return end
  GPU.played = GPU.played + 1
  if GPU.played >= FREEZE_AFTER then
    shader_opt("zb_freeze", "1")
    msg.info("black bars: keeping the crop found at the start")
  end
end

local function bars_new_file()
  GPU.played = 0
  if not GPU.loaded then return end
  GPU.epoch = GPU.epoch + 1
  shader_opt("zb_epoch", tostring(GPU.epoch))
  shader_opt("zb_freeze", "0")
end

local function apply_gpu_crop()
  if S.crop_applied then mp.set_property("video-crop", ""); S.crop_applied = nil; S.crop_box = nil end
  local ow, oh = mp.get_osd_size()
  local dar = prop("video-dec-params/aspect", 0)
  if not ow or not oh or ow <= 0 or oh <= 0 or dar <= 0 then return end
  update_band()
  local view = ow / (oh * band_f)
  shader_opt("zb_view", string.format("%.6f", view))
  shader_opt("zb_dar", string.format("%.6f", dar / math.max(S.anamorphic, 1)))
  shader_opt("zb_fill", S.aspect == "zoom" and "1" or "0")
  bars_shader(true)
  set_once("video-aspect-override", string.format("%.6f", view))
  set_once("panscan", "0")
  if not GPU.timer then GPU.timer = mp.add_periodic_timer(1, bars_tick) end
end

apply_crop = function()
  if gpu_bars() then return apply_gpu_crop() end
  bars_shader(false)
  set_once("video-aspect-override", plain_override(S.aspect))
  set_once("panscan", S.aspect == "zoom" and "1" or "0")
  local c = S.crop
  local vw, vh = prop("video-params/w", 0), prop("video-params/h", 0)
  if not S.autocrop or not c or vw == 0 or (S.aspect ~= "auto" and S.aspect ~= "zoom") then
    if S.crop_applied then mp.set_property("video-crop", ""); S.crop_applied = nil; S.crop_box = nil end
    return
  end
  local y, h = R(c.top * vh), R((1 - c.top - c.bottom) * vh)
  h = h - h % 2
  local value = string.format("%dx%d+0+%d", vw, h, y)
  if value ~= S.crop_applied then
    S.crop_applied = value
    S.crop_box = { y = y, h = h, vh = vh }
    mp.set_property("video-crop", value)
    msg.info(string.format("black bars: cropping to %s (%.3f:1)", value, prop("video-params/aspect", 1.78) * vh / h))
  end
end

local function row_black(data, stride, y, w)
  local base = y * stride
  local step = math.max(1, math.floor(w * 0.9 / CROP.samples))
  local x0 = math.floor(w * 0.05)
  for i = 0, CROP.samples - 1 do
    local o = base + (x0 + i * step) * 4 + 1
    local b, g, r = data:byte(o, o + 2)
    if not r then return true end
    if b > CROP.threshold or g > CROP.threshold or r > CROP.threshold then return false end
  end
  return true
end

local function measure_bars(shot)
  if not S.autocrop or S.phase ~= "playing" then return end
  if not shot or not shot.data or not shot.w or shot.w == 0 then return end
  local w, h, stride, data = shot.w, shot.h, shot.stride, shot.data
  local ratio = w / h
  local box = S.crop_box
  local cropped = false
  if not box then
    if S.aspect == "auto" or S.aspect == "zoom" then S.full_ratio = ratio end
  elseif S.full_ratio and box.h > 0 then
    cropped = ratio > S.full_ratio * (1 + (box.vh / box.h - 1) / 2)
  end
  local limit = math.floor(h * 0.3)
  local top = 0
  while top < limit and row_black(data, stride, top, w) do top = top + 1 end
  local bottom = 0
  while bottom < limit and row_black(data, stride, h - 1 - bottom, w) do bottom = bottom + 1 end
  local dark = top >= limit or bottom >= limit
  local t, b = top / h, bottom / h
  if cropped then
    local scale = box.h / h
    t = (box.y + top * scale) / box.vh
    b = (box.vh - box.y - box.h + bottom * scale) / box.vh
  end
  send("bars", string.format('{"top":%.4f,"bottom":%.4f,"dark":%s,"clip":%s}', t, b, tostring(dark),
    tostring(cropped and top == 0 and bottom == 0)))
end

local capturing = false
local function detect_bars()
  if capturing or not S.autocrop or S.phase ~= "playing" or gpu_bars() then return end
  capturing = true
  mp.command_native_async({ "screenshot-raw", "video", "bgr0" }, function(ok, shot)
    capturing = false
    if ok then measure_bars(shot) end
  end)
end

local crop_timer, crop_interval = nil, nil
local function schedule_crop(interval)
  if interval == crop_interval and crop_timer then return end
  if crop_timer then crop_timer:kill(); crop_timer = nil end
  crop_interval = interval
  if not S.autocrop or not interval or interval <= 0 then return end
  crop_timer = mp.add_periodic_timer(interval, function()
    if not prop("pause", false) and not prop("seeking", false) and not prop("paused-for-cache", false) then
      detect_bars()
    end
  end)
end

local function settings_items()
  local speed = prop("speed", 1)
  local items = {}
  if #S.versions > 1 then
    local current = "?"
    for _, v in ipairs(S.versions) do if v.selected then current = v.label end end
    items[#items + 1] = { id = "version", label = tr("version"), detail = current, submenu = true }
  end
  if S.quality and #S.quality.options > 0 then
    items[#items + 1] = { id = "quality", label = tr("quality"), detail = S.quality.label, submenu = true }
  end
  for _, it in ipairs({
    { id = "aspect", label = tr("aspect_ratio"), detail = aspect_label(S.aspect), submenu = true },
    { id = "speed", label = tr("playback_speed"), detail = string.format("%gx", speed), submenu = true },
    { id = "subdelay", label = tr("subtitle_delay"), detail = string.format("%+.1fs", prop("sub-delay", 0)), submenu = true },
    { id = "subsize", label = tr("subtitle_size"), detail = percent(prop("sub-scale", 1)), submenu = true },
    { id = "audiodelay", label = tr("audio_delay"), detail = string.format("%+.2fs", prop("audio-delay", 0)), submenu = true },
    { id = "info", label = tr("playback_info"), detail = tr("playback_info_detail"), submenu = true },
  }) do items[#items + 1] = it end
  return items
end

local function delay_items(p, step, unit, steps)
  local cur = prop(p, 0)
  local items = {}
  for i = -steps, steps do
    local v = i * step
    items[#items + 1] = { id = v, label = string.format("%+." .. unit .. "fs", v), selected = math.abs(v - cur) < step / 2 }
  end
  return items
end

local function panel_cursor(items)
  for i, it in ipairs(items) do if it.selected then return i end end
  return 1
end

local function middle_ellipsis(text, max)
  if #text <= max then return text end
  local a, b = math.floor(max / 2) - 1, #text - math.floor(max / 2) + 2
  while a > 1 and text:byte(a + 1) and text:byte(a + 1) >= 0x80 and text:byte(a + 1) < 0xC0 do a = a - 1 end
  while b < #text and text:byte(b) >= 0x80 and text:byte(b) < 0xC0 do b = b + 1 end
  return text:sub(1, a) .. "…" .. text:sub(b)
end

local VIDEO_NAMES = { h264 = "H.264", hevc = "HEVC", av1 = "AV1", vp9 = "VP9", mpeg2video = "MPEG-2", vc1 = "VC-1" }

local function info_items()
  local items = {}
  local function add(label, detail)
    if detail and detail ~= "" then
      items[#items + 1] = { id = label, label = label, detail = middle_ellipsis(detail, 44) }
    end
  end
  local info = S.info or {}
  for _, row in ipairs(info.rows or {}) do add(row.label, row.detail) end

  local format = prop("video-format", "")
  if info.transcoding then
    local parts = {}
    if format ~= "" then parts[#parts + 1] = VIDEO_NAMES[format] or string.upper(format) end
    local w, h = prop("video-params/w", 0), prop("video-params/h", 0)
    if w > 0 then parts[#parts + 1] = w .. "×" .. h end
    local audio = prop("audio-codec-name", "")
    if audio ~= "" then parts[#parts + 1] = string.upper(audio) end
    add(tr("info_stream"), table.concat(parts, "  ·  "))
  end
  if format ~= "" then
    local hw = prop("hwdec-current", "")
    if hw == "" or hw == "no" then add(tr("info_video_decoder"), tr("info_software"))
    else add(tr("info_video_decoder"), tr("info_hardware") .. "  ·  " .. hw) end
    add(tr("info_dropped"), tostring(prop("frame-drop-count", 0) + prop("decoder-frame-drop-count", 0)))
  end
  local out = prop("audio-out-params/format", "")
  if out:find("^spdif") then
    add(tr("info_audio_output"), tr("info_bitstream") .. "  ·  " .. string.upper((out:gsub("^spdif%-", ""))))
  elseif out ~= "" then
    add(tr("info_audio_output"), tr("info_decoded") .. "  ·  " .. prop("audio-out-params/hr-channels", ""))
  end
  local buffered = prop("demuxer-cache-duration", nil)
  if type(buffered) == "number" then add(tr("info_buffer_ahead"), string.format("%d s", math.floor(buffered + 0.5))) end
  return items
end

open_panel = function(kind)
  local p = { kind = kind }
  if kind == "audio" then p.title, p.items = tr("audio"), track_items("audio")
  elseif kind == "subs" then p.title, p.items = tr("subtitles"), track_items("subs")
  elseif kind == "chapters" then p.title, p.items = tr("chapters"), chapter_items()
  elseif kind == "settings" then p.title, p.items = tr("settings"), settings_items()
  elseif kind == "info" then p.title, p.items = tr("playback_info"), info_items()
  elseif kind == "version" then
    p.title, p.items = S.versions_title or tr("version"), {}
    for _, v in ipairs(S.versions) do
      p.items[#p.items + 1] = { id = v.id, label = v.label, detail = v.detail, selected = v.selected }
    end
  elseif kind == "quality" then
    p.title, p.items = tr("quality"), {}
    for _, q in ipairs(S.quality.options) do
      p.items[#p.items + 1] = { id = q.id, label = q.label, detail = q.detail, selected = q.selected }
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
  elseif kind == "subdelay" then p.title, p.items = tr("subtitle_delay"), delay_items("sub-delay", 0.1, "1", 50)
  elseif kind == "audiodelay" then p.title, p.items = tr("audio_delay"), delay_items("audio-delay", 0.05, "2", 10)
  elseif kind == "subsize" then
    local cur = prop("sub-scale", 1)
    p.title, p.items = tr("subtitle_size"), { { id = "slider" } }
    p.slider = { value = cur, min = 0.25, max = 1.5, step = 0.05, marks = { 0.25, 0.5, 0.75, 1.0, 1.25, 1.5 } }
    p.revert = function() mp.set_property_number("sub-scale", cur) end
  elseif kind == "sublang" then
    p.title, p.items = tr("search_subtitles"), {}
    for _, l in ipairs(S.sub_languages) do p.items[#p.items + 1] = { id = l.id, label = l.label, submenu = true } end
  elseif kind == "subresults" then
    local r = S.sub_results
    p.title = tr("search_subtitles")
    p.subhead = r and r.file
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
  if p.kind == "audio" then
    if item.id == "downmix" then
      set_downmix(not S.downmix.on)
      S.toast, S.toast_until, S.toast_img = tr("stereo_downmix") .. ": " .. on_off(S.downmix.on), now() + 2, nil
    else send("audio", tostring(item.id)) end
    S.panel = nil
  elseif p.kind == "subs" then
    local sub_panels = { subsize = "subsize", subdelay = "subdelay", subsearch = "sublang" }
    if sub_panels[item.id] then open_panel(sub_panels[item.id])
    else send("sub", tostring(item.id)); S.panel = nil end
  elseif p.kind == "chapters" then mp.commandv("seek", item.id, "absolute+exact"); S.panel = nil
  elseif p.kind == "settings" then
    open_panel(item.id)
  elseif p.kind == "info" then S.panel = nil
  elseif p.kind == "version" then
    if not item.selected then send("version", tostring(item.id)) end
    S.panel = nil
  elseif p.kind == "quality" then
    if not item.selected then send("quality", tostring(item.id)) end
    S.panel = nil
  elseif p.kind == "speed" then mp.set_property_number("speed", item.id); S.panel = nil
  elseif p.kind == "aspect" then
    set_aspect(item.id); S.panel = nil
    S.toast, S.toast_until, S.toast_img = tr("aspect_toast", item.label), now() + 2, nil
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
    send("subscale", string.format("%.2f", p.slider.value))
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

local OV_TRICK, TRICK_GAP, TRICK_SLOTS = 50, 6, 5
local trick_keys, trick_drawn = {}, false

local function trick_reach(tw)
  if not S.trick_filmstrip then return 0 end
  for r = 2, 1, -1 do
    if (2 * r + 1) * tw + 2 * r * TRICK_GAP <= W - 36 then return r end
  end
  return 0
end

local function hide_trick(from)
  for i = from or 1, TRICK_SLOTS do
    if trick_keys[i] then mp.commandv("overlay-remove", OV_TRICK + i - 1) end
    trick_keys[i] = nil
  end
end

local function draw_trick(out, cx, y, t)
  local tp = S.trick
  if not tp then return end
  local tw = R(W * S.trick_size / 100)
  local reach = trick_reach(tw)
  local bucket = math.floor(t / math.max(tp.interval, 0.1)) .. ":" .. reach
  if bucket ~= S.trick_req then
    S.trick_req = bucket
    send("trick", string.format("%.3f|%d", t, reach))
  end
  local img = S.trick_img
  local osd_w, osd_h = mp.get_osd_size()
  if not img or not osd_h or osd_h == 0 then return end
  local first
  for _, f in ipairs(img.frames) do
    if f.path then first = f; break end
  end
  if not first then return end
  local n = #img.frames
  local th = R(tw * first.h / first.w)
  local row = n * tw + (n - 1) * TRICK_GAP
  local mid = S.trick_follow and cx or W / 2
  local left = R(clamp(mid - row / 2, 18, math.max(18, W - 18 - row)))
  local top = R(y - 84 - (S.trick_distance - 10) * H / 200) - th
  out[#out + 1] = rrect(left - 6, top - 6, row + 12, th + 12, 14, T.panel, "20")
  trick_drawn = true
  local k = osd_h * band_f / H
  for i, f in ipairs(img.frames) do
    local x = left + (i - 1) * (tw + TRICK_GAP)
    if f.path then
      if n > 1 and i == reach + 1 then out[#out + 1] = rrect(x - 3, top - 3, tw + 6, th + 6, 10, T.accent, "00") end
      local px, py, dw, dh = R(x * k), R((top + band_oy) * k), R(tw * k), R(th * k)
      local key = table.concat({ f.path, px, py, dw, dh }, "|")
      if trick_keys[i] ~= key then
        trick_keys[i] = key
        mp.commandv("overlay-add", OV_TRICK + i - 1, px, py, f.path, 0, "bgra", f.w, f.h, f.w * 4, dw, dh)
      end
    elseif trick_keys[i] then
      mp.commandv("overlay-remove", OV_TRICK + i - 1)
      trick_keys[i] = nil
    end
  end
  hide_trick(n + 1)
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

  out[#out + 1] = rrect(x1, y - h / 2, width, h, h / 2, T.white, "C8")
  if cfrac > frac then out[#out + 1] = rrect(x1, y - h / 2, width * cfrac, h, h / 2, T.white, "70") end
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
      draw_trick(out, x1 + width * frac, y, S.scrub)
    elseif S.pointer and S.hover == "seek" and dur > 0 then
      local hx = clamp(S.mouse_x, x1, x2)
      out[#out + 1] = rrect(hx - 1, y - h / 2 - 4, 2, h + 8, 1, T.white, "20")
      out[#out + 1] = rrect(hx - 70, y - 72, 140, 46, 23, T.panel, "20")
      out[#out + 1] = text(hx, y - 49, 5, 28, T.white, fmt_time((hx - x1) / width * dur), { font = T.font_semibold })
      draw_trick(out, hx, y, (hx - x1) / width * dur)
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

local function slider_set(p, v)
  local s = p.slider
  v = clamp(math.floor((v - s.min) / s.step + 0.5) * s.step + s.min, s.min, s.max)
  if math.abs(v - s.value) < 1e-6 then return end
  s.value = v
  mp.set_property_number("sub-scale", v)
end

local function draw_slider_panel(out, p)
  local s = p.slider
  local bw, bh = math.min(1100, W - 160), 250
  local bx, by = R((W - bw) / 2), 60
  out[#out + 1] = rrect(bx, by, bw, bh, 28, T.panel, "10")
  out[#out + 1] = text(bx + 48, by + 56, 4, 40, T.white, esc(p.title), { font = T.font_semibold })
  out[#out + 1] = text(bx + bw - 48, by + 56, 6, 40, T.accent_soft, percent(s.value), { font = T.font_semibold })
  out[#out + 1] = text(bx + 48, by + 100, 4, 22, T.muted, esc(tr("slider_hint")))
  local tx, tw, ty = bx + 64, bw - 128, by + 156
  local function at(v) return tx + tw * (v - s.min) / (s.max - s.min) end
  out[#out + 1] = rrect(tx, ty - 3, tw, 6, 3, T.white, "B0")
  out[#out + 1] = rrect(tx, ty - 3, at(s.value) - tx, 6, 3, T.accent)
  local n = R((s.max - s.min) / s.step)
  for i = 0, n do
    local v = s.min + i * s.step
    local major = false
    for _, m in ipairs(s.marks) do if math.abs(m - v) < 1e-6 then major = true end end
    local h = major and 16 or 10
    out[#out + 1] = rrect(at(v) - 1, ty - h / 2, 2, h, 1, v <= s.value + 1e-6 and T.accent or T.white, v <= s.value + 1e-6 and "00" or "B0")
    if major then
      local on = math.abs(v - s.value) < 1e-6
      out[#out + 1] = text(at(v), ty + 34, 5, 20, on and T.white or T.muted, percent(v), on and { font = T.font_semibold } or nil)
    end
  end
  out[#out + 1] = circle(at(s.value), ty, 15, T.accent)
  out[#out + 1] = circle(at(s.value), ty, 11, T.white)
  add_hit(tx - 20, ty - 30, tx + tw + 20, ty + 50, function(x)
    slider_set(p, s.min + clamp((x - tx) / tw, 0, 1) * (s.max - s.min))
  end, "slider")
end

local function draw_panel(out)
  local p = S.panel
  if p.slider then
    S.hits = {}
    draw_slider_panel(out, p)
    return
  end
  local pw = 620
  local px = W - pw
  S.hits = {}
  out[#out + 1] = ev(string.format("\\pos(0,0)\\1c&H000000&\\1a&H70&\\p1"), string.format("m 0 0 l %d 0 l %d %d l 0 %d", W, W, H, H))
  out[#out + 1] = ev(string.format("\\pos(0,0)\\1c&H%s&\\1a&H08&\\p1", T.panel), string.format("m %d 0 l %d 0 l %d %d l %d %d", px, W, W, H, px, H))
  out[#out + 1] = text(px + 56, 90, 4, 40, T.white, esc(p.title), { font = T.font_semibold })
  if p.subhead and p.subhead ~= "" then
    out[#out + 1] = text(px + 56, 136, 4, 22, T.muted, esc(middle_ellipsis(p.subhead, 46)))
  end

  local row_h, top = 84, (p.subhead and p.subhead ~= "") and 176 or 160
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

local function draw_skip_pill(out, pos, label, a, b)
  local lit_now = not S.visible or (S.pointer and S.hover == "card")
  local played = clamp((pos - a) / math.max(0.001, b - a), 0, 1)
  local left = fmt_time(math.max(0, b - pos))
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
  local k = osd_h * band_f / H
  local px, py, dw, dh = R(x * k), R((y + band_oy) * k), R(w * k), R(h * k)
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

local OV_TOAST = 63
local toast_key = nil
local function toast_picture(x, y, size)
  local img = S.toast_img
  local osd_w, osd_h = mp.get_osd_size()
  if not img or not osd_h or osd_h == 0 then return end
  local k = osd_h * band_f / H
  local px, py, d = R(x * k), R((y + band_oy) * k), R(size * k)
  local key = table.concat({ img.image, px, py, d }, "|")
  if key == toast_key then return end
  toast_key = key
  mp.commandv("overlay-add", OV_TOAST, px, py, img.image, 0, "bgra", img.size, img.size, img.size * 4, d, d)
end

local function hide_toast_picture()
  if not toast_key then return end
  toast_key = nil
  mp.commandv("overlay-remove", OV_TOAST)
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
  trick_drawn = false
  update_band()
  if osd_w and osd_h and osd_w > 0 and osd_h > 0 then W = math.floor(H * osd_w / (osd_h * band_f)) end
  band_oy = R((H / band_f - H) / 2)
  local shown = S.phase .. (S.visible and "+controls" or "") .. (S.panel and ("+panel:" .. (S.panel.kind or "?")) or "")
  if shown ~= S.logged_shown then
    S.logged_shown = shown
    msg.info(string.format("osd %s (window %sx%s, layout %dx%d)", shown, tostring(osd_w), tostring(osd_h), W, H))
  end
  overlay.res_x, overlay.res_y = W, R(H / band_f)
  S.hits = {}
  local out = {}
  local t = now()

  if S.phase == "loading" or S.phase == "error" then
    lift_subtitles(0)
    hide_still()
    hide_trick()
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
    overlay.data = shift_y(table.concat(out, "\n"), band_oy)
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
    out[#out + 1] = scrim(-200, 90, 0x50, 70)
    out[#out + 1] = text(W - 80, 70, 6, 34, T.white, os.date("%H:%M"), { font = T.font_semibold })
    draw_progress(out, H - 96, true, true)
  end

  local still = false
  if not S.panel then
    if intro_visible(pos) then
      draw_skip_pill(out, pos, tr("skip_intro"), S.seg.introStart, S.seg.introEnd)
    elseif credits_visible(pos) then
      draw_skip_pill(out, pos, tr("skip_credits"), credits_start(), duration())
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
    if S.toast_img then
      toast_picture(W / 2 - 360 + 10, 68, 48)
      out[#out + 1] = text(W / 2 + 24, 92, 5, 26, T.white, esc(S.toast))
    else
      out[#out + 1] = text(W / 2, 92, 5, 26, T.white, esc(S.toast))
    end
  end
  if not (S.toast_img and S.toast and t < S.toast_until and t >= S.vol_until) then hide_toast_picture() end

  if S.panel then draw_panel(out) end
  if not trick_drawn then hide_trick() end

  local data = shift_y(table.concat(out, "\n"), band_oy)
  if data ~= overlay.data or W ~= S.drawn_w then
    overlay.data = data
    S.drawn_w = W
    overlay:update()
  end
end

local tick
local tick_interval = 0

local function finish_scrub(commit)
  local target = S.scrub
  S.scrub = nil
  if target and commit then mp.commandv("seek", target, "absolute+exact") end
  if S.scrub_paused then
    S.scrub_paused = false
    mp.set_property_bool("pause", false)
  end
end

local function wanted_interval()
  local t = now()
  if S.phase == "loading" or t < S.flash_until or prop("paused-for-cache", false) then return 0.033 end
  local pos = prop("time-pos", 0)
  if next_visible(pos) and S.next_up and S.next_up.autoplay then return 0.04 end
  if S.visible or S.panel or S.scrub or t < S.mini_until or t < S.toast_until or t < S.vol_until
    or intro_visible(pos) or credits_visible(pos) or next_visible(pos) then return 0.25 end
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
  if S.scrub and not S.trick_pause and t > S.scrub_commit_at then
    finish_scrub(true)
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
  if S.scrub_paused then return finish_scrub(true) end
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
  elseif id == "rewind" then seek_relative(-S.seek_back)
  elseif id == "forward" then seek_relative(S.seek_fwd)
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
  local step = dir > 0 and S.seek_fwd or S.seek_back
  if S.scrub_repeat > 24 then step = 120 elseif S.scrub_repeat > 12 then step = 60 elseif S.scrub_repeat > 5 then step = 30 end
  if not S.scrub and S.trick_pause and not prop("pause", false) then
    S.scrub_paused = true
    mp.set_property_bool("pause", true)
  end
  S.scrub = clamp((S.scrub or prop("time-pos", 0)) + dir * step, 0, dur - 1)
  S.scrub_commit_at = t + 0.9
  touch()
  refresh()
end

local function commit_scrub()
  if S.scrub then finish_scrub(true) end
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

    if S.panel and S.panel.slider then
      local p = S.panel
      if name == "left" or name == "right" then slider_set(p, p.slider.value + (name == "left" and -1 or 1) * p.slider.step)
      elseif name == "ok" then panel_activate(p.items[1])
      elseif name == "back" then close_panel()
      end
      touch(); refresh()
      return
    end
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
      local next_up = next_visible(pos) and not intro_visible(pos)
      if next_up and (name == "left" or name == "right") then S.next_choice = name == "left" and 1 or 2
      elseif name == "left" then seek_relative(-S.seek_back)
      elseif name == "right" then seek_relative(S.seek_fwd)
      elseif next_up and name == "ok" then
        if S.next_choice == 1 then send("next") else S.next_cancelled = true; send("next-cancel") end
      elseif name == "ok" and S.zap then
        open_panel("version")
        touch()
      elseif name == "ok" then
        if not card_action(pos) then toggle_pause() end
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
        if S.scrub then finish_scrub(false) else S.visible = false end
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
  return mx * W / osd_w, my * (H / band_f) / osd_h - band_oy
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
  if S.panel and S.panel.slider then panel_activate(S.panel.items[1]); refresh(); return end
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
  if S.phase == "loading" and was ~= "loading" then
    S.crop, S.full_ratio = nil, nil
    bars_new_file()
    apply_crop()
  end
  if S.phase == "playing" and was ~= "playing" then
    crop_interval = nil
    schedule_crop(2)
    S.intro_skipped, S.next_cancelled, S.next_fired, S.credits_done = false, false, false, false
    S.next_elapsed, S.next_last, S.next_choice = 0, nil, 1
    S.panel = nil
    finish_scrub(false)
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

mp.register_script_message("info", function(raw)
  S.info = json(raw)
end)

mp.register_script_message("versions", function(raw)
  S.versions = json(raw) or {}
end)

mp.register_script_message("quality", function(raw)
  S.quality = json(raw)
end)

mp.register_script_message("chapters", function(raw)
  S.chapters = json(raw) or {}
  if S.panel and S.panel.kind == "chapters" then open_panel("chapters") end
  refresh()
end)

mp.register_script_message("trickplay", function(raw)
  S.trick, S.trick_img, S.trick_req = json(raw), nil, nil
  refresh()
end)

mp.register_script_message("trick-image", function(raw)
  local img = json(raw)
  if not img or not img.frames or not S.trick then return end
  S.trick_img = img
  refresh()
end)

mp.register_script_message("cover", function(url)
  if url and url ~= "" then mp.commandv("video-add", url, "select", "cover", "", "yes") end
end)

mp.register_script_message("segments", function(raw)
  S.seg = json(raw) or {}
  S.intro_skipped, S.credits_done = false, false
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

mp.register_script_message("downmix", function(raw)
  S.downmix = json(raw)
end)

mp.register_script_message("config", function(raw)
  local c = json(raw) or {}
  S.seek_fwd = c.seekForward or S.seek_fwd
  S.seek_back = c.seekBack or S.seek_back
  S.skip_intro = c.skipIntro or "button"
  S.skip_credits = c.skipCredits or "button"
  S.versions_title = c.versionsTitle
  S.zap = c.zap or false
  S.sub_search = c.subtitleSearch or false
  S.sub_languages = c.subLanguages or {}
  S.scope = c.scope or 0
  S.trick_filmstrip = c.trickplayMode == "filmstrip"
  S.trick_size = c.trickplaySize or 17
  S.trick_distance = c.trickplayDistance or 10
  S.trick_follow = c.trickplayFollow ~= false
  S.trick_pause = c.trickplayPause == true
  S.anamorphic = c.anamorphic or 1
  S.autocrop = c.autoCrop or false
  S.autocrop_mode = c.autoCropMode or "continuous"
  S.default_aspect = c.defaultAspect or "auto"
  set_aspect(S.default_aspect)
  render()
end)

mp.register_script_message("crop", function(raw)
  local c = json(raw) or {}
  local f = tonumber(c.crop) or 0
  S.crop = f > 0 and { top = f, bottom = f } or nil
  apply_crop()
  schedule_crop(tonumber(c.interval) or 0)
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
  S.toast, S.toast_until, S.toast_img = msg, now() + 2.5, nil
  refresh()
end)

mp.register_script_message("toast-image", function(raw)
  local m = json(raw)
  if not m then return end
  S.toast, S.toast_until, S.toast_img = m.text, now() + 3, m.image and m or nil
  refresh()
end)

local last_pos_render = 0
mp.observe_property("time-pos", "number", function(_, pos)
  if not pos then return end
  if S.skip_intro == "auto" and not S.intro_skipped and in_intro(pos) then
    skip_intro()
    S.toast, S.toast_until = tr("intro_skipped"), now() + 2
  end
  if S.skip_credits == "auto" and not S.credits_done and S.phase == "playing" and in_credits(pos) then
    S.credits_done = true
    if S.next_up then send("next") else send("credits") end
  end
  if now() - last_pos_render > 0.5 then
    last_pos_render = now()
    schedule()
  end
end)
mp.observe_property("pause", "bool", function() if S.visible then touch() end; refresh() end)
mp.observe_property("paused-for-cache", "bool", function() refresh() end)
mp.observe_property("osd-dimensions", "native", function() render(); apply_crop() end)
mp.observe_property("video-dec-params", "native", function() apply_crop() end)
mp.enable_messages("error")
mp.register_event("log-message", function(e)
  if not GPU.loaded or GPU.failed or not e.prefix:find("^vo/gpu%-next") then return end
  if not e.text:find("Failed executing hook") then return end
  GPU.failed = true
  msg.warn("black bars: the GPU shader failed, measuring screenshots instead")
  apply_crop()
  if S.phase == "playing" then
    crop_interval = nil
    schedule_crop(2)
  end
end)
mp.observe_property("user-data/zerk/fullscreen", "native", function() render() end)

msg.info("osd loaded; icon font: " .. T.icons)
render()
send("ready")
