local options = {
    fontname = "sans-serif",
    fontsize = 25,
    bold = "true",

    transparency = 0x0, -- 0-255 (0 = opaque, 255 = transparent)
    outline = 1,
    shadow = 0,
    displayarea = 0.8, -- Percentage of screen height for display area

    vf_fps = false, -- Whether to use fps filter
    fps = 60 -- Target fps for filter
}

local msg = require('mp.msg')
local utils = require("mp.utils")

local duration = 8
local INTERVAL = 0.016
local osd_width, osd_height, pause = 0, 0, true
local enabled, comments = false, nil

local function parse_comment(event, pos, height)
    local function parse_move_tag(text)
        local x1, y1, x2, y2 = text:match("\\move%((%-?[%d%.]+),%s*(%-?[%d%.]+),%s*(%-?[%d%.]+),%s*(%-?[%d%.]+).*%)")
        if x1 and y1 and x2 and y2 then
            return tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
        end
        return nil
    end

    local x1, y1, x2, y2 = parse_move_tag(event.text)
    local displayarea = tonumber(height * options.displayarea)
    if not x1 then
        local current_x, current_y = event.text:match("\\pos%((%-?[%d%.]+),%s*(%-?[%d%.]+).*%)")
        if tonumber(current_y) > displayarea then
            return
        end
        return string.format("{\\an8}%s", event.text)
    end

    local progress = (pos - event.start_time) / duration

    local current_x = tonumber(x1 + (x2 - x1) * progress)
    local current_y = tonumber(y1 + (y2 - y1) * progress)

    local clean_text = event.text:gsub("\\move%(.-%)", "")
    if current_y > displayarea then
        return
    end
    return string.format("{\\pos(%.1f,%.1f)\\an8}%s", current_x, current_y, clean_text)
end

local overlay = mp.create_osd_overlay('ass-events')

local function render()
    if comments == nil then
        return
    end

    local pos = mp.get_property_number('time-pos')

    local fontname = options.fontname
    local fontsize = options.fontsize

    local width, height = 1920, 1080
    local ratio = osd_width / osd_height
    if width / height < ratio then
        height = width / ratio
        fontsize = options.fontsize - ratio * 2
    end

    local ass_events = {}

    for _, event in ipairs(comments) do
        if pos >= event.start_time and pos <= event.start_time + duration then
            local text = parse_comment(event, pos, height)

            if text and text:match("\\fs%d+") then
                local font_size = text:match("\\fs(%d+)") * 1.5
                text = text:gsub("\\fs%d+", string.format("\\fs%s", font_size))
            end

            local ass_text = text and
                                 string.format(
                    "{\\rDefault\\fn%s\\fs%d\\c&HFFFFFF&\\alpha&H%x\\bord%s\\shad%s\\b%s\\q2}%s", fontname,
                    text:match("{\\b1\\i1}x%d+$") and fontsize + text:match("x(%d+)$") or fontsize,
                    options.transparency, options.outline, options.shadow, options.bold == "true" and "1" or "0", text)

            table.insert(ass_events, ass_text)
        end
    end

    overlay.res_x = width
    overlay.res_y = height
    overlay.data = table.concat(ass_events, '\n')
    overlay:update()
end

local timer = mp.add_periodic_timer(INTERVAL, render, true)

local function filter_state(label, name)
    local filters = mp.get_property_native("vf")
    for _, filter in pairs(filters) do
        if filter.label == label or filter.name == name or filter.params[name] ~= nil then
            return true
        end
    end
    return false
end

function show_danmaku_func()
    render()
    if not pause then
        timer:resume()
    end
    if options.vf_fps then
        local display_fps = mp.get_property_number('display-fps')
        local video_fps = mp.get_property_number('estimated-vf-fps')
        if (display_fps and display_fps < 58) or (video_fps and video_fps > 58) then
            return
        end
        if not filter_state("danmaku", "fps") then
            mp.commandv("vf", "append", string.format("@danmaku:fps=fps=%s", options.fps))
        end
    end
end

function hide_danmaku_func()
    timer:kill()
    overlay:remove()
    if filter_state("danmaku") then
        mp.commandv("vf", "remove", "@danmaku")
    end
end

function generate_sample_danmaku()
    local comments = {}
    local sample_texts = {"Hello world!", "Nice video!", "LOL", "This part is amazing!", "What is this?",
                          "Great content!", "I can't believe this", "Too funny 😂", "First time watching",
                          "Love this scene"}

    local num_comments = 1000

    for i = 1, num_comments do
        local start_time = math.random() * 600
        local text = sample_texts[math.random(#sample_texts)]

        -- For some comments, add movement
        local formatted_text = text
        -- Random starting position (mostly off-screen to the right)
        local x1 = osd_width * 1.5
        local y1 = math.random(math.floor(osd_height * options.displayarea * 0.8))

        -- End position (off-screen to the left)
        local x2 = -100 - math.random(200)
        local y2 = y1 -- Keep same vertical position for simple scrolling

        formatted_text = string.format("\\move(%.1f,%.1f,%.1f,%.1f)%s", x1, y1, x2, y2, text)

        -- Random color for some comments
        if math.random() < 0.3 then
            local colors = {"&HFFFF00&", "&HFF00FF&", "&H00FFFF&", "&H00FF00&", "&HFF0000&", "&H0000FF&"}
            local color = colors[math.random(#colors)]
            formatted_text = string.format("{\\c%s}%s", color, formatted_text)
        end

        table.insert(comments, {
            text = formatted_text,
            start_time = start_time,
        })
    end

    return comments
end

mp.add_forced_key_binding("Ctrl+d", "simulate-danmaku", function()
    comments = generate_sample_danmaku()
    enabled = true
    show_danmaku_func()
end)

mp.observe_property('osd-width', 'number', function(_, value)
    osd_width = value or osd_width
end)
mp.observe_property('osd-height', 'number', function(_, value)
    osd_height = value or osd_height
end)
mp.observe_property('display-fps', 'number', function(_, value)
    if value ~= nil then
        local interval = 1 / value / 10
        if interval > INTERVAL then
            timer:kill()
            timer = mp.add_periodic_timer(interval, render, true)
            if enabled then
                timer:resume()
            end
        else
            timer:kill()
            timer = mp.add_periodic_timer(INTERVAL, render, true)
            if enabled then
                timer:resume()
            end
        end
    end
end)
mp.observe_property('pause', 'bool', function(_, value)
    if value ~= nil then
        pause = value
    end
    if enabled then
        if pause then
            timer:kill()
        elseif comments ~= nil then
            timer:resume()
        end
    end
end)

mp.add_hook("on_unload", 50, function()
    mp.unobserve_property('pause')
    comments = nil
    timer:kill()
    overlay:remove()
    if filter_state("danmaku") then
        mp.commandv("vf", "remove", "@danmaku")
    end
end)

mp.register_event('playback-restart', function(event)
    if event.error then
        return msg.error(event.error)
    end
    if enabled and comments ~= nil then
        render()
    end
end)

mp.add_forced_key_binding("d", "toggle-danmaku", function()
    if not enabled then
        if not comments then
            auto_load_danmaku()
        else
            enabled = true
            show_danmaku_func()
        end
    else
        enabled = false
        hide_danmaku_func()
    end
end)

