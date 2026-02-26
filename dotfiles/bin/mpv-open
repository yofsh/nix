#!/bin/sh
LINK=$1
if [ $# -eq 0 ]; then
	LINK=$(wl-paste)
fi

notify-send -u low -i mpv "Opening link with mpv" "$LINK"

mpv --input-ipc-server=/tmp/mpvsocket --speed=2 --title="floating mpv" --geometry=640x360 --ytdl-format="bestvideo[height<=?480][fps<=?30][vcodec!=?vp9]+bestaudio/best" "$LINK" &
>/tmp/mpvlog || notify-send -u low -i mpv "Cant open URL" "$(cat /tmp/mpvlog)"
