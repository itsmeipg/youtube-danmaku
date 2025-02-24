local options = {
    live_chat_directory = mp.command_native({"expand-path", "~~/live_chat"}),
    chat_hidden = false,
    auto_load = false,
    yt_dlp_path = 'yt-dlp',
    show_author = true,
    author_color = 'random',
    author_border_color = '000000',
    message_color = 'ffffff',
    message_border_color = '000000',
    font = mp.get_property_native('osd-font'),
    font_size = 16,
    border_size = 2,
    message_duration = 10000,
    max_message_line_length = 40,
    message_break_anywhere = false,
    message_gap = 10,
    anchor = 1
}

require("mp.options").read_options(options)
local utils = require("mp.utils")

local messages = {}
local current_filename
local download_finished = false
local last_position = nil
local relative_live_time = nil
local chat_overlay = mp.create_osd_overlay("ass-events")
chat_overlay.z = -1

local function string_to_color(str)
    local hash = 5381
    for i = 1, str:len() do
        hash = (33 * hash + str:byte(i)) % 16777216
    end
    return hash
end

local function swap_color_string(str)
    local r = str:sub(1, 2)
    local g = str:sub(3, 4)
    local b = str:sub(5, 6)
    return b .. g .. r
end

local function split_string(input)
    local splits = {}

    local delimiter_pattern = " %.,%-!%?"
    for input in string.gmatch(input, "[^" .. delimiter_pattern .. "]+[" .. delimiter_pattern .. "]*") do
        table.insert(splits, input)
    end

    return splits
end

local function break_message(message, initial_length)
    local max_line_length = options.max_message_line_length
    if max_line_length <= 0 then
        return message
    end

    local current_length = initial_length
    local result = ''

    if options.message_break_anywhere then
        local lines = {}
        while #message > 0 do
            local newline = message:sub(1, max_line_length)
            table.insert(lines, newline)
            message = message:sub(max_line_length, #message)
        end
        result = table.concat(lines, '\n')
    else
        for _, v in ipairs(split_string(message)) do
            current_length = current_length + #v

            if current_length > max_line_length then
                result = result .. '\n' .. v
                current_length = #v
            else
                result = result .. v
            end
        end
    end

    return result
end

local function chat_message_to_string(message)
    if message.type == 0 then
        if options.show_author then
            if options.author_color == 'random' then
                return string.format('{\\1c&H%06x&}{\\3c&H%s&}%s{\\1c&H%s&}{\\3c&H%s&}: %s', message.author_color,
                    swap_color_string(options.author_border_color), message.author,
                    swap_color_string(options.message_color), swap_color_string(options.message_border_color),
                    break_message(message.contents, message.author:len() + 2))
            elseif options.author_color == 'none' then
                return string.format('{\\3c&H%s&}%s{\\1c&H%s&}{\\3c&H%s&}: %s',
                    swap_color_string(options.author_border_color), message.author,
                    swap_color_string(options.message_color), swap_color_string(options.message_border_color),
                    break_message(message.contents, message.author:len() + 2))
            else
                return string.format('{\\1c&H%s&}{\\3c&H%s&}%s{\\1c&H%s&}{\\3c&H%s&}: %s',
                    swap_color_string(options.author_color), swap_color_string(options.author_border_color),
                    message.author, swap_color_string(options.message_color),
                    swap_color_string(options.message_border_color),
                    break_message(message.contents, message.author:len() + 2))
            end
        else
            return break_message(message.contents, 0)
        end
    elseif message.type == 1 then
        if message.contents then
            return string.format('%s %s: %s', message.author, message.money,
                break_message(message.contents, message.author:len() + message.money:len()))
        else
            return string.format('%s %s', message.author, message.money)
        end
    end
end

local function format_message(message)
    local message_string = chat_message_to_string(message)
    local result = nil
    local lines = message_string:gmatch("([^\n]*)\n?")

    for line in lines do
        local formatting = '{\\an' .. options.anchor .. '}' .. '{\\fs' .. options.font_size .. '}' .. '{\\fn' ..
                               options.font .. '}' .. '{\\bord' .. options.border_size .. '}' ..
                               string.format('{\\1c&H%s&}', swap_color_string(options.message_color)) ..
                               string.format('{\\3c&H%s&}', swap_color_string(options.message_border_color))
        if message.type == 1 then
            formatting = formatting ..
                             string.format('{\\1c&H%s&}{\\3c&%s&}',
                    swap_color_string(string.format('%06x', message.text_color)),
                    swap_color_string(string.format('%06x', message.border_color)))
        end
        local message_string = formatting .. line
        if result == nil then
            result = message_string
        else
            if options.anchor <= 3 then
                result = message_string .. '\n' .. result
            else
                result = result .. '\n' .. message_string
            end
        end
    end
    return result or ''
end

local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        f:close()
        return true
    else
        return false
    end
end

local function parse_message_runs(runs)
    local message = ""
    for _, data in ipairs(runs) do
        if data.text then
            message = message .. data.text
        elseif data.emoji then
            if data.emoji.isCustomEmoji then
                message = message .. data.emoji.shortcuts[1]
            else
                message = message .. data.emoji.emojiId
            end
        end
    end
    return message
end

local function parse_text_message(renderer)
    local id = renderer.authorExternalChannelId
    local color = string_to_color(id)

    local author = renderer.authorName and renderer.authorName.simpleText or '-'

    local message = parse_message_runs(renderer.message.runs)

    return {
        type = 0,
        author = author,
        author_color = color,
        contents = message,
        time = nil -- Will be set by caller
    }
end

local function parse_superchat_message(renderer)
    local border_color = renderer.bodyBackgroundColor - 0xff000000
    local text_color = renderer.bodyTextColor - 0xff000000
    local money = renderer.purchaseAmountText.simpleText

    local author = renderer.authorName and renderer.authorName.simpleText or '-'

    local message = nil
    if renderer.message then
        message = parse_message_runs(renderer.message.runs)
    end

    return {
        type = 1,
        author = author,
        money = money,
        border_color = border_color,
        text_color = text_color,
        contents = message,
        time = nil -- Will be set by caller
    }
end

local function parse_chat_action(action, time)
    if not action.addChatItemAction then
        return nil
    end

    local item = action.addChatItemAction.item
    local message = nil

    if item.liveChatTextMessageRenderer then
        message = parse_text_message(item.liveChatTextMessageRenderer)
    elseif item.liveChatPaidMessageRenderer then
        message = parse_superchat_message(item.liveChatPaidMessageRenderer)
    end

    if message then
        message.time = time
    end

    return message
end

local function generate_messages(live_chat_json)
    local result = {}
    for line in io.lines(live_chat_json) do
        local entry = utils.parse_json(line)
        if entry.replayChatItemAction then
            local time = tonumber(entry.videoOffsetTimeMsec or entry.replayChatItemAction.videoOffsetTimeMsec)
            for _, action in ipairs(entry.replayChatItemAction.actions) do
                local message = parse_chat_action(action, time)
                if message then
                    table.insert(result, message)
                end
            end
        end
    end
    return result
end

local function read_new_live_messages(filename)
    local file = io.open(filename, "r")
    if not file then
        return nil
    end

    if not last_position then
        print("fail")
        local last_line = nil
        while true do
            local line = file:read("*l")
            if not line then
                break
            end
            last_position = file:seek()
        end

        file:close()
        return
    end

    file:seek("set", last_position)
    local new_messages = {}
    while true do
        local line = file:read("*l")
        last_position = file:seek()
        if not line then
            break
        end

        if line:match("%S") then
            local entry = utils.parse_json(line)
            if entry and entry.replayChatItemAction then
                local time = tonumber(entry.videoOffsetTimeMsec or entry.replayChatItemAction.videoOffsetTimeMsec)
                if not relative_live_time then
                    relative_live_time = time
                end
                for _, action in ipairs(entry.replayChatItemAction.actions) do
                    local message = parse_chat_action(action, entry.isLive and
                        math.max(0, mp.get_property_native("duration") - 10) * 1000 + (time - relative_live_time) or
                        time)
                    if message then
                        table.insert(new_messages, message)
                    end
                end
            end
        end
    end

    file:close()
    return new_messages
end

local function update_chat_overlay(time)
    if current_filename then
        if file_exists(current_filename) then
            if download_finished == false then
                download_finished = true
                messages = generate_messages(current_filename)
            end
        elseif file_exists(current_filename .. ".part") then
            local new_messages = read_new_live_messages(current_filename .. ".part")
            if new_messages then
                for _, msg in ipairs(new_messages) do
                    table.insert(messages, msg)
                end
            end
        end
    end

    if options.chat_hidden or chat_overlay == nil or messages == nil or time == nil then
        return
    end

    local msec = time * 1000

    chat_overlay.data = ''
    for i = 1, #messages do
        local message = messages[i]
        if message.time > msec then
            break
        elseif msec <= message.time + options.message_duration then
            local message_string = format_message(message)

            if options.anchor <= 3 then
                chat_overlay.data = message_string .. '\n' .. '{\\fscy' .. options.message_gap ..
                                        '}{\\fscx0}\\h{\fscy\fscx}' .. chat_overlay.data

            else
                chat_overlay.data =
                    chat_overlay.data .. '{\\fscy' .. options.message_gap .. '}{\\fscx0}\\h{\fscy\fscx}' .. '\n' ..
                        message_string
            end
        end
    end
    chat_overlay:update()
end

local function download_live_chat(url, filename)
    if file_exists(filename) then
        return
    end
    mp.command_native_async({
        name = "subprocess",
        args = {'yt-dlp', '--skip-download', '--sub-langs=live_chat', url, '--write-sub', '-o', '%(id)s', '-P',
                options.live_chat_directory}
    })
end

local function load_live_chat(filename)
    local function live_chat_exists_remote(url)
        local result = mp.command_native({
            name = "subprocess",
            capture_stdout = true,
            args = {'yt-dlp', url, '--list-subs', '--quiet'}
        })
        if result.status == 0 then
            return string.find(result.stdout, "live_chat")
        end
        return false
    end

    local path = mp.get_property_native('path')
    if filename == nil then
        local is_network = path:find('^http://') ~= nil or path:find('^https://') ~= nil
        if is_network then
            local id = path:gsub("^.*\\?v=", ""):gsub("&.*", "")
            filename = string.format("%s/%s.live_chat.json", options.live_chat_directory, id)
            if not file_exists(filename) or not file_exists(filename .. ".part") then
                print('Checking for live chat on remote...')
                if live_chat_exists_remote(path) then
                    print('Downloading live chat replay...')
                    download_live_chat(path, filename)
                end
            end
        else
            local base_path = path:match('(.+)%..+$') or path
            filename = base_path .. '.live_chat.json'
        end
    end
    current_filename = filename
    update_chat_overlay(mp.get_property_native("time-pos"))
end

mp.add_forced_key_binding("c", "load-chat", function()
    current_filename = nil
    last_position = nil
    download_finished = false
    relative_live_time = nil
    messages = {}
    chat_overlay.data = ''
    load_live_chat()
end)

local function _update_chat_overlay(_, time)
    update_chat_overlay(time)
end
mp.observe_property("time-pos", "native", _update_chat_overlay)
