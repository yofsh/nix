#!/bin/sh
EXT="jpeg"
GEOMETRY="$(slurp)"

if [ -z "$GEOMETRY" ]; then
  exit 1
fi

TEXT=$(grim -t $EXT -g "$GEOMETRY" -q 60 - |  magick - -density 300 -resize 300%  png:- | tesseract - - --oem 1 -l eng+ukr+rus+spa --dpi 300)
EXITCODE="$?"

if [ $EXITCODE -eq 0 ] && [ -n "$TEXT" ]; then
  echo "$TEXT"
  wl-copy "$TEXT"
  notify-send -i clipboard -u low "Text copied to clipboard" "$TEXT"
else
  notify-send -i clipboard -u low "Can't find any text, exit code $EXITCODE" "Output: $TEXT"
  echo "Either command failed or variable is not empty"
  echo "Result:"
  echo "$TEXT"
fi

