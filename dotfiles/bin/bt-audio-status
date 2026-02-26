#!/bin/sh

ISA2DP=$(pactl list cards | grep 'Active.*a2dp')
echo $ISA2DP
if [ "$1" = "toggle" ]; then
	if [ -z "$ISA2DP" ]; then
		INDEX=$(pactl list cards | grep -E 'Name|Active.*headset-head-unit' | tail -n2 | head -n1 | awk '{print $2}')
		echo $INDEX
		echo "test"
		pactl set-card-profile "$INDEX" a2dp-sink
	else
		INDEX=$(pactl list cards | grep -E 'Name|Active.*a2dp' | tail -n2 | head -n1 | awk '{print $2}')
		echo $INDEX
		pactl set-card-profile "$INDEX" headset-head-unit
	fi
fi

ISA2DP=$(pactl list cards | grep 'Active.*a2dp')
if [ -z "$ISA2DP" ]; then
	echo "headset"
else
	echo "A2"
fi
