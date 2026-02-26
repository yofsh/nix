#!/bin/sh
#
INTERVAL=0.5

VALID_ARGS=$(getopt -o t,n:: --long title,interval: -- "$@")
if [[ $? -ne 0 ]]; then
	exit 1
fi

eval set -- "$VALID_ARGS"

echo " valid args: $VALID_ARGS"
while [ "$1" != "--" ]; do
	case "$1" in
	-n | --interval)
		echo "Processing 'interval' option"
		INTERVAL=$2
		echo "interval is $INTERVAL"
		shift 2
		;;
	-t | --title)
		echo "Processing 'title' option"
		SHOW_TITLE=true
		shift
		;;
	*)
		echo "Invalid option: $1"
		exit 1
		;;
	esac
done
shift

COMMAND=$@

tput civis
function finish {
	tput cnorm
	exit
}
trap finish EXIT

COLS=$(tput cols)
LINES=$(tput lines)

clear
tput cup 0 0

while true; do

	NEW_COLS=$(tput cols)
	NEW_LINES=$(tput lines)

	# Redraw the content if the size of the terminal changes
	if [[ "$NEW_COLS" -ne "$COLS" || "$NEW_LINES" -ne "$LINES" ]]; then
		clear
		COLS="$NEW_COLS"
		LINES="$NEW_LINES"
	fi
	tput cup 0 0

	if [ "$SHOW_TITLE" = true ]; then
		echo "$(date +"%Y-%m-%d %H:%M:%S,%3N")"
		echo
		grc --colour=on $COMMAND | head -n "$((LINES - 3))"
	else
		grc --colour=on $COMMAND | head -n "$((LINES - 1))"
	fi
	sleep $INTERVAL
done
