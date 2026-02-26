#!/bin/sh
pkill dunst
sleep 0.5

dunstify -u low "Low priority" "Notification ext goes here"
dunstify "Normal priority" "Notification text goes here"
dunstify -u critical "Critical priority" "Notification text goes here"

dunstify -u low -h "int:value:5" "Low priority priority with progress"
dunstify -h "int:value:40" "Normal priority with progress"
dunstify -u critical -h "int:value:90" "Normal priority with progress"

dunstify -i background "With background icon" "Notification ext goes here"
dunstify -i youtube "Normal youtube icon" "Notification ext goes here"

dunstify -a "Telegram Desktop" "Telegram notificaiton" "With some text in here With some text in here With some text in here With some text in here With some text in here "

dunstify -a "Firefox" "New message from test" "With some text in here With some text in here With some text in here With some text in here With some text in here "

dunstify -u -low "Translation" "With some text in here With some text in here With some text in here With some text in here With some text in here "

dunstify "New message from User" "It's a Slack notification from browser."
