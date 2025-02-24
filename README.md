# mpv-youtube-chat
This fork supports downloading live chats as they download so it works for livestreams (that are live).
Takes about 10 seconds to start working.

My live stream logic:
When downloading the live chat from a live stream, the script seeks to the last empty line of the file. Then, it wait for that empty line to update, and it uses that first comment to time other new, downloaded comments. This is done for three reasons:

1. Comments downloaded during livestreams have incorrect timing (videoOffsetTimeMsec) in relation to the stream duration.
2. YTDLP seems to download comments in batches of about 5-10 seconds. To prevent displaying them all at once, we use their timings relative to each other.
3. The reference comment has to be new. If the live stream live chat file (name.live_chat.json.part) was partially downloaded during the first hour of a 10 hour stream, and we used a comment from that time as the reference, newer downloaded comments will be displayed after 9-ish hours.

The timing of downloaded live messages is not correct relative to the stream duration, but correct relative to each other. I use this formula to correct the comments' timing relative to the stream:
- Stream duration + (comment time - reference comment time)

Example, stream duration is 5 seconds (just started). 
The script downloads the first comment since opening the stream; reference comment time is set to 5 seconds. 
Comment time refers to any comments downloaded after the reference comment; let's say it was commented 2 seconds after the reference comment.

The comment is displayed when the stream duration reaches 7 seconds: (5 + (7-5)) = 7

