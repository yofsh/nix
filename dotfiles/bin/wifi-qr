#!/bin/sh
# connect to WIFI with the webcam and QR code

QR=$(zbarcam --raw -1)
echo "QR code content:"
echo "$QR"
PREAMBULE=$(echo "$QR" | awk -F'[ ;]' '{print $1}')
QRTYPE=$(echo "$PREAMBULE" | awk -F'[ :]' '{print $1}')
if [ "$QRTYPE" != "WIFI" ]; then
	echo "QR code is not wifi"
	exit 1
fi

SSID=$(echo "$QR" | awk -F'[ ;]' '{print $1}' | awk -F'[ :]' '{print $3}')
PASSWORD=$(echo "$QR" | awk -F'[ ;]' '{print $3}' | awk -F'[ :]' '{print $2}')
HIDDEN=$(echo "$QR" | awk -F'[ ;]' '{print $4}' | awk -F'[ :]' '{print $2}')
TYPE=$(echo "$QR" | awk -F'[ ;]' '{print $2}' | awk -F'[ :]' '{print $2}')

#TODO: add support for hidden networks
echo "Trying to connect to SSID $SSID, with - $TYPE, hidden - $HIDDEN"
nmcli d w l --rescan yes
nmcli dev wifi connect "$SSID" password "$PASSWORD"
