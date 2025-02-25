local options = {
    -- Font settings
    fontname = "sans-serif",
    fontsize = 25,
    bold = "true",

    -- Display settings
    transparency = 0x0, -- 0-255 (0 = opaque, 255 = transparent)
    outline = 1,
    shadow = 0,
    displayarea = 0.8, -- Percentage of screen height for display area

    -- Video filter settings
    vf_fps = false, -- Whether to use fps filter
    fps = 60, -- Target fps for filter
    scrolltime = 10, -- Default scrolling time in seconds

    -- Message display settings
    message_anlignment = 7, -- Text alignment (7 = bottom left)
    message_x = 10, -- X position for messages
    message_y = 10 -- Y position from bottom
}

local msg = require('mp.msg')
local utils = require("mp.utils")

local INTERVAL = options.vf_fps and 0.01 or 0.001
local osd_width, osd_height, pause = 0, 0, true
enabled, comments, delay = false, nil, 0

local delay_property = string.format("user-data/%s/danmaku-delay", mp.get_script_name())

function time_to_seconds(time_str)
    local h, m, s = time_str:match("(%d+):(%d+):([%d%.]+)")
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
end

local function parse_move_tag(text)
    local x1, y1, x2, y2 = text:match("\\move%((%-?[%d%.]+),%s*(%-?[%d%.]+),%s*(%-?[%d%.]+),%s*(%-?[%d%.]+).*%)")
    if x1 and y1 and x2 and y2 then
        return tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
    end
    return nil
end

local function parse_comment(event, pos, height)
    local x1, y1, x2, y2 = parse_move_tag(event.text)
    local displayarea = tonumber(height * options.displayarea)
    if not x1 then
        local current_x, current_y = event.text:match("\\pos%((%-?[%d%.]+),%s*(%-?[%d%.]+).*%)")
        if tonumber(current_y) > displayarea then
            return
        end
        if event.style ~= "SP" and event.style ~= "MSG" then
            return string.format("{\\an8}%s", event.text)
        else
            return string.format("{\\an7}%s", event.text)
        end
    end

    local duration = event.end_time - event.start_time -- mean: options.scrolltime
    local progress = (pos - event.start_time - delay) / duration -- 移动进度 [0, 1]

    local current_x = tonumber(x1 + (x2 - x1) * progress)
    local current_y = tonumber(y1 + (y2 - y1) * progress)

    local clean_text = event.text:gsub("\\move%(.-%)", "")
    if current_y > displayarea then
        return
    end
    if event.style ~= "SP" and event.style ~= "MSG" then
        return string.format("{\\pos(%.1f,%.1f)\\an8}%s", current_x, current_y, clean_text)
    else
        return string.format("{\\pos(%.1f,%.1f)\\an7}%s", current_x, current_y, clean_text)
    end
end

local overlay = mp.create_osd_overlay('ass-events')

local function render()
    if comments == nil then
        return
    end

    local pos, err = mp.get_property_number('time-pos')
    if err ~= nil then
        return msg.error(err)
    end

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
        if pos >= event.start_time + delay and pos <= event.end_time + delay then
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

local message_overlay = mp.create_osd_overlay('ass-events')
local message_timer = mp.add_timeout(3, function()
    message_overlay:remove()
end, true)

function show_message(text, time)
    message_timer.timeout = time or 3
    message_timer:kill()
    message_overlay:remove()
    local message = string.format("{\\an%d\\pos(%d,%d)}%s", options.message_anlignment, options.message_x,
        options.message_y, text)
    local width, height = 1920, 1080
    local ratio = osd_width / osd_height
    if width / height < ratio then
        height = width / ratio
    end
    message_overlay.res_x = width
    message_overlay.res_y = height
    message_overlay.data = message
    message_overlay:update()
    message_timer:resume()
end

function generate_sample_danmaku(duration, density)
    local comments = {}
    local styles = {"Regular", "SP", "MSG"}
    local sample_texts = {"Hello world!", "Nice video!", "LOL", "This part is amazing!", "What is this?",
                          "Great content!", "I can't believe this", "Too funny 😂", "First time watching",
                          "Love this scene"}

    -- Determine number of comments based on density and duration
    local num_comments = 1000

    for i = 1, num_comments do
        -- Random start time between 0 and duration
        local start_time = math.random() * 600
        local end_time = start_time + 8

        -- Random style
        local style = "Regular"

        -- Random text
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
            end_time = end_time,
            style = style
        })
    end

    return comments
end

-- Function to activate simulation mode
function activate_simulation_mode(duration, density)
    if not density then
        density = 3
    end -- comments per second

    comments = generate_sample_danmaku(duration, density)
    enabled = true
    show_danmaku_func()
    show_message(string.format("Danmaku simulation enabled (%d comments)", #comments))
end

-- Add this key binding for quick simulation
mp.add_forced_key_binding("Ctrl+d", "simulate-danmaku", function()
    local duration = mp.get_property_native("duration")
    activate_simulation_mode(duration)
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
    comments, delay = nil, 0
    timer:kill()
    overlay:remove()
    mp.set_property_native(delay_property, 0)
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

mp.register_script_message("danmaku-delay", function(number)
    local value = tonumber(number)
    if value == nil then
        return msg.error('command danmaku-delay: invalid time')
    end
    delay = delay + value
    if enabled and comments ~= nil then
        render()
    end
    mp.set_property_native(delay_property, delay)
end)

mp.add_forced_key_binding("d", "toggle-danmaku", function()
    if not enabled then
        if not comments then
            auto_load_danmaku()
        else
            enabled = true
            show_danmaku_func()
            show_message("Danmaku enabled")
        end
    else
        enabled = false
        hide_danmaku_func()
        show_message("Danmaku disabled")
    end
end)

