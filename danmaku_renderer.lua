local options = {
    fontname = "sans-serif",
    fontsize = 30,
    bold = "true",

    duration = 8,
    transparency = 0x0, -- 0-255 (0 = opaque, 255 = transparent)
    outline = 1,
    shadow = 0,
    displayarea = 0.8 -- Percentage of screen height for display area
}

local utils = require("mp.utils")

local overlay = mp.create_osd_overlay('ass-events')
local timer
local osd_width, osd_height, pause = 0, 0, true
enabled, comments = true, {}

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

    local progress = (pos - event.time) / options.duration

    local current_x = tonumber(x1 + (x2 - x1) * progress)
    local current_y = tonumber(y1 + (y2 - y1) * progress)
    if current_y > displayarea then
        return
    end

    local clean_text = event.text:gsub("\\move%(.-%)", "")
    return string.format("{\\pos(%.1f,%.1f)\\an8}%s", current_x, current_y, clean_text)
end

local function render()
    if #comments == 0 then
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
        if pos >= event.time and pos <= event.time + options.duration then
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

function add_comment(time, text, color)
    local x1 = osd_width * 1.5
    local y1 = math.random(math.floor(osd_height * options.displayarea))

    -- End position
    local x2 = -osd_width / 3
    local y2 = y1 -- Keep same vertical position
    table.insert(comments, {
        text = string.format("{\\move(%.1f,%.1f,%.1f,%.1f)}{\\c%s}%s", x1, y1, x2, y2, color, text),
        time = time
    })
end

local function generate_sample_danmaku()
    local comments = {}
    local sample_texts = {"Hello world!", "Nice video!", "LOL", "This part is amazing!", "What is this?",
                          "Great content!", "I can't believe this", "Too funny 😂", "First time watching",
                          "Love this scene"}

    local num_comments = 1000

    for i = 1, num_comments do
        local time = math.random() * 600
        local text = sample_texts[math.random(#sample_texts)]

        -- For some comments, add movement
        local formatted_text = text
        -- Starting position
        local x1 = osd_width * 1.3
        local y1 = math.random(math.floor(osd_height * options.displayarea))

        -- End position
        local x2 = -osd_width / 3
        local y2 = y1 -- Keep same vertical position

        formatted_text = string.format("\\move(%.1f,%.1f,%.1f,%.1f)%s", x1, y1, x2, y2, text)

        local color = "&HFFFFFF&"
        formatted_text = string.format("{\\c%s}%s", color, formatted_text)

        table.insert(comments, {
            text = formatted_text,
            time = time
        })
    end

    return comments
end

local function show_danmaku_func()
    render()
    if not pause then
        timer:resume()
    end
end

local function hide_danmaku_func()
    timer:kill()
    overlay:remove()
end

mp.observe_property('osd-width', 'number', function(_, value)
    osd_width = value or osd_width
end)
mp.observe_property('osd-height', 'number', function(_, value)
    osd_height = value or osd_height
end)
mp.observe_property('display-fps', 'number', function(_, value)
    if value then
        local interval = 1 / value
        if timer then
            timer:kill()
        end
        timer = mp.add_periodic_timer(interval, render, true)
        if enabled then
            timer:resume()
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
        elseif #comments > 0 then
            timer:resume()
        end
    end
end)

mp.add_hook("on_unload", 50, function()
    mp.unobserve_property('pause')
    comments = {}
    timer:kill()
    overlay:remove()
end)

mp.register_event('playback-restart', function(event)
    if enabled and #comments > 0 then
        render()
    end
end)

mp.add_forced_key_binding("Ctrl+d", "simulate-danmaku", function()
    comments = generate_sample_danmaku()
    enabled = true
    show_danmaku_func()
end)

mp.add_forced_key_binding("s", "hide", function()
    hide_danmaku_func()
end)

mp.add_forced_key_binding("b", "show", function()
    show_danmaku_func()
end)
