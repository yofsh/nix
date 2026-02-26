# voice.d/dictate.sh — transcribe and type via wtype
# Sourced by voice dispatcher, not executed directly

RECORDING_PID_FILE="/tmp/voice_recording.pid"
AUDIO_FILE="/tmp/voice_recording.wav"
NOTIFY_ID=10020
RECORD_MSG="Recording..."

. "$VOICE_DIR/core.sh"

on_success() {
  echo "$TEXT"
  wl-copy "$TEXT"
  wtype "$TEXT"
  notify "Transcribed" "$TEXT"
}

do_toggle() {
  if [ -f "$RECORDING_PID_FILE" ]; then
    if transcribe; then
      on_success
    fi
  else
    start_recording
  fi
}

case "${1:-toggle}" in
  start) start_recording ;;
  stop) transcribe && on_success ;;
  toggle) do_toggle ;;
  *) echo "Usage: voice dictate [start|stop|toggle]" ;;
esac
