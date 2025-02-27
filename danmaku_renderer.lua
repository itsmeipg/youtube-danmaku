local options = {
    enabled = true,

    fontname = "sans-serif",
    fontsize = 30,
    bold = "true",

    duration = 8, -- May be innacurate (about third/half of a second) and more so for longer messages
    transparency = 0, -- 0-255 (0 = opaque, 255 = transparent)
    outline = 1,
    shadow = 0,
    displayarea = 0.7 -- Percentage of screen height for display area
}

local utils = require("mp.utils")

local overlay = mp.create_osd_overlay('ass-events')
local width, height = 1920, 1080
local timer
local osd_width, osd_height = 0, 0
comments = {}

local function render()
    if not options.enabled or #comments == 0 then
        overlay:remove()
        return
    end

    local pos = mp.get_property_number('time-pos')
    local ass_events = {}
    for _, comment in ipairs(comments) do
        if pos >= comment.time and pos <= comment.time + options.duration then
            -- Starting position
            local x1 = width
            local y1 = comment.y
            -- End position
            local x2 = 0 - comment.text:len() * options.fontsize
            local y2 = y1

            local progress = (pos - comment.time) / options.duration
            local current_x = tonumber(x1 + (x2 - x1) * progress)
            local current_y = tonumber(y1 + (y2 - y1) * progress)

            if current_y <= tonumber(height * options.displayarea) then
                local clean_text = comment.text:gsub("\\move%(.-%)", "")

                local ass_text = comment.text and
                                     string.format(
                        "{\\rDefault\\an7\\q2\\pos(%.1f,%.1f)\\fn%s\\fs%d\\c&HFFFFFF&\\alpha&H%x\\bord%s\\shad%s\\b%s}%s",
                        current_x, current_y, options.fontname, options.fontsize, options.transparency, options.outline,
                        options.shadow, options.bold == "true" and "1" or "0", comment.text)

                table.insert(ass_events, ass_text)
            end

        end
    end

    overlay.res_x = width
    overlay.res_y = height
    overlay.data = table.concat(ass_events, '\n')
    overlay:update()
end

function add_comment(time, text, color)
    table.insert(comments, {
        text = text,
        time = time,
        y = math.random(math.floor(osd_height * options.displayarea))
    })
end

local function generate_sample_danmaku()
    local comments = {}
    local sample_texts = {"Hello world!", "Nice video!", "LOL", "This part is amazing!", "What is this?",
                          "Great content!", "I can't believe this", "Too funny 😂", "First time watching",
                          "Love this scene"}

    local duration = mp.get_property_native("duration")
    local density = 5

    for i = 1, duration * density do
        local time = math.random() * duration
        local text = sample_texts[math.random(#sample_texts)]

        table.insert(comments, {
            text = text,
            time = time,
            y = math.random(math.floor(osd_height * options.displayarea))
        })
    end

    return comments
end

local function toggle_danmaku()
    options.enabled  = not options.enabled
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
        timer = mp.add_periodic_timer(interval, render)
    end
end)

mp.add_hook("on_unload", 50, function()
    comments = {}
end)

mp.add_forced_key_binding("Ctrl+d", "simulate-comments", function()
    comments = generate_sample_danmaku()
end)

mp.add_forced_key_binding("s", "toggle-danmaku", toggle_danmaku)
