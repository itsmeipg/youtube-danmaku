# mpv-youtube-chat
This fork supports downloading live chats as they download so it works for livestreams (that are live).
Takes about 10 seconds to start working.

# Live stream implementation logic
Script gets newest messages since live_chat file downloaded. Comment times are not synced with the video, but synced relative to each other. Script uses livestream duration to sync newly downloaded comments with livestream. YT-DLP downloads comments in batches, so syncing the whole batch to one point of time (livestream duration) would display comments all at once. Script uses the last comment of each batch to calculate the offset between stream and newly downloaded comments. Offset is applied to each comment to sync them with the livestream and maintain their timing relative to each other.

# Todo
Fix archived live stream danmaku
Cleanup code (mostly in main.lua)
Integrate danmaku_renderer.lua directly into main.lua
Get accurate start position and end position
Fix message formatting
Reverse direction
Lanes and lane management
Overlapping transparency control
Superchat boxes
Member messages are green/customizable
Fix options
Implement message break/wrap
Find a way for YT-DLP to update live_chat.json.part faster and with less delay.
