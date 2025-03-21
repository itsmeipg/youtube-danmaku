# YouTube Danmaku
This fork renders YouTube danmaku and supports parsing live chat as it downloads so it works for livestreams (that are live).
Takes about 10 seconds to start working.

# Livestream implementation logic
Script gets newest messages since live chat file downloaded. Comment times are not synced with the video, but synced relative to each other. Script uses livestream duration to sync newly downloaded comments with livestream. YT-DLP downloads comments in batches, so syncing the whole batch to one point of time (livestream duration) would display comments all at once. Script uses the last comment of each batch to calculate the offset between stream and newly downloaded comments. Offset is applied to each comment to sync them with the livestream and maintain their timing relative to each other.

# Might not be possible but I'll try to add it
- Probably a better way to find displayed messages instead of going through all the messages every render loop.
- Reverse direction (probably possible)
- Overlapping transparency control
- Superchat boxes
- Member messages are green/customizable
- Implement message break/wrap (probably possible)

# Sources
- https://github.com/m13253/danmaku2ass/blob/ced881747670c2eb1c0dbd292c2a567f444b056a/danmaku2ass.py#L747
- https://github.com/Tony15246/uosc_danmaku/blob/main/render.lua
- https://github.com/ShazibRahman/mpv-youtube-live-chat-relay/blob/bd6b0f40a1b4ac71ce635bca5e0cd179e98f0034/main.lua#L104
