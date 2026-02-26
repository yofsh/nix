#!/bin/sh
EXT="jpeg"
IMAGE="/tmp/gsimg.$EXT"
GEOMETRY="$(slurp)"

if [ -z "$GEOMETRY" ]; then
  exit 1
fi

echo "$GEOMETRY" "$IMAGE"

grim -t $EXT -g "$GEOMETRY" -q 60 "$IMAGE"

if [ ! -f "$IMAGE" ]; then
  echo "No image to search, exiting."
  exit 1
fi

notify-send -i $IMAGE -u low "Sending image to google"
RESP=$(curl -i -s -F sch=sch -F "encoded_image=@$IMAGE" https://lens.google.com/upload)
URL=$(echo $RESP | grep -oP '(?<=location: )https?://\S+')
echo URL:
echo $URL
rm $IMAGE
firefox "$URL"
