#!/bin/sh
EXT="jpeg"
IMAGE="/tmp/barcode.$EXT"

GEOMETRY="$(slurp)"
if [ -z "$GEOMETRY" ]; then
	exit 1
fi

grim -t $EXT -g "$GEOMETRY" "$IMAGE"
SCANRESULT=$(zbarimg --raw "$IMAGE" | tr -d '\n')

if [ -z "$SCANRESULT" ]; then
	notify-send -u low "zbar" "No scan data found"
else
	echo "$SCANRESULT" | wl-copy
	convert $IMAGE -resize 75x75 "$BARCODE_IMAGE"
	notify-send -u low -i "$IMAGE" "zbar" "$SCANRESULT\n(copied to clipboard)"
	wl-copy "$SCANRESULT"
	# xdg-open "$SCANRESULT"
fi
