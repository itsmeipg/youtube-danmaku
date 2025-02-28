local options = {
    live_chat_directory = mp.command_native({"expand-path", "~~/live_chat"}),
    yt_dlp_path = 'yt-dlp',
    autoload = true,
    danmaku_visibility = true,

    fontname = "sans-serif",
    fontsize = 30,
    bold = true,
    message_color = 'ffffff',
    transparency = 0, -- 0-255 (0 = opaque, 255 = transparent)
    outline = 1,
    shadow = 0,
    duration = 10, -- May be innacurate (about third/half of a second) and more so for longer messages
    displayarea = 0.7 -- Percentage of screen height for display area
}

require("danmaku_renderer")
require("mp.options").read_options(options)
local utils = require("mp.utils")

local filename
local last_position = nil
local download_finished = false
local messages = {}

local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
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
    local function string_to_color(str)
        local hash = 5381
        for i = 1, str:len() do
            hash = (33 * hash + str:byte(i)) % 16777216
        end
        return hash
    end

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

local function get_parsed_messages(live_chat_json)
    local parsed_messages = {}
    for line in io.lines(live_chat_json) do
        local entry = utils.parse_json(line)
        if entry.replayChatItemAction then
            local time = tonumber(entry.videoOffsetTimeMsec or entry.replayChatItemAction.videoOffsetTimeMsec)
            for _, action in ipairs(entry.replayChatItemAction.actions) do
                local parsed_message = parse_chat_action(action, time)
                if parsed_message then
                    table.insert(parsed_messages, parsed_message)
                end
            end
        end
    end
    return parsed_messages
end

local function get_new_parsed_messages(filename)
    local file = io.open(filename, "r")
    if not file then
        return
    end

    if not last_position then
        for line in file:lines() do
            last_position = file:seek()
        end
    else
        file:seek("set", last_position)
    end

    local entries = {}
    local latest_entry_time
    for line in file:lines() do
        last_position = file:seek()
        local entry = utils.parse_json(line)
        if entry and entry.replayChatItemAction then
            latest_entry_time = tonumber(entry.videoOffsetTimeMsec or entry.replayChatItemAction.videoOffsetTimeMsec)
            table.insert(entries, entry)
        end
    end
    file:close()

    local new_parsed_messages = {}
    if #entries > 0 then
        local live_offset = latest_entry_time - mp.get_property_native("duration") * 1000
        for _, entry in ipairs(entries) do
            local time = tonumber(entry.videoOffsetTimeMsec or entry.replayChatItemAction.videoOffsetTimeMsec)
            for _, action in ipairs(entry.replayChatItemAction.actions) do
                local new_parsed_message = parse_chat_action(action, entry.isLive and (time - live_offset) or time)
                if new_parsed_message then
                    table.insert(new_parsed_messages, new_parsed_message)
                end
            end
        end
    end

    return new_parsed_messages
end

local function update_messages()
    if filename then
        if file_exists(filename) and not download_finished then
            download_finished = true
            local parsed_messages = get_parsed_messages(filename)
            messages = {}
            for _, message in ipairs(parsed_messages) do
                add_comment(message.time / 1000, message.contents)
            end
        elseif file_exists(filename .. ".part") then
            local new_parsed_messages = get_new_parsed_messages(filename .. ".part")
            if new_parsed_messages then
                for _, message in ipairs(new_parsed_messages) do
                    add_comment(message.time / 1000, message.contents)
                end
            end
        end
    end
end

local function reset()
    filename = nil
    last_position = nil
    download_finished = false
    messages = {}
end

local function load_live_chat()
    reset()

    local function download_live_chat(url)
        mp.command_native_async({
            name = "subprocess",
            args = {'yt-dlp', '--skip-download', '--sub-langs=live_chat', url, '--write-sub', '-o', '%(id)s', '-P',
                    options.live_chat_directory}
        })
    end

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
    local is_network = path:find('^http://') or path:find('^https://')
    if is_network then
        local id = path:gsub("^.*\\?v=", ""):gsub("&.*", "")
        filename = string.format("%s/%s.live_chat.json", options.live_chat_directory, id)
        if not file_exists(filename) and live_chat_exists_remote(path) then
            download_live_chat(path, filename)
        end
    else
        local base_path = path:match('(.+)%..+$') or path
        filename = base_path .. '.live_chat.json'
    end
end

mp.register_event("file-loaded", function()
    if options.autoload then
        load_live_chat()
    end
end)

mp.add_hook("on_unload", 50, function()
    reset()
end)

local timer = mp.add_periodic_timer(.1, update_messages)
