# mpv-youtube-chat
This fork supports downloading live chats as they download so it works for livestreams (that are live).
Takes about 10 seconds to start working.

My live stream logic:
When downloading the live chat from a live stream, the script seeks to the last empty line of the file. Then, it waits for that empty line to update, and it uses that first comment to time other new, downloaded comments. This is done for three reasons:

1. Comments downloaded during livestreams have incorrect timing (videoOffsetTimeMsec) in relation to the stream duration.
2. YTDLP seems to download comments in batches of about 5-10 seconds. Instead of displaying them all at once, we use their timings relative to each other.
3. The reference comment has to be new. If the live stream live chat file (name.live_chat.json.part) was partially downloaded during the first hour of a 10 hour stream, and we used a comment from that time as the reference, newer downloaded comments will be displayed after 9-ish hours. This occurs because the reference comment's time must match the current stream duration when it was commented (see formula below).

Since downloaded comments aren't correct relative to the stream duration, we use the first comment downloaded to represent the stream duration, and use the differences in time between newer downloaded comments to time when they appear.
- Stream duration + (comment time - reference comment time)

Example, stream duration is 5 seconds (just started). 
The script downloads the first comment since opening the stream; reference comment time is set to 5 seconds. 
Comment time refers to any comments downloaded after the reference comment; let's say it was commented 2 seconds after the reference comment.

The comment is displayed when the stream duration reaches 7 seconds: (5 + (7-5)) = 7

If the reference comment was old (posted at 2 seconds), comment is displayed later than it should: (5 + (7-2)) = 10

