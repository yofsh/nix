# voice.d/core.sh — shared config and helpers for voice scripts
# Sourced by voice dispatcher, not executed directly

# whisper.cpp configuration
WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"
MODEL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/whisper-cpp"
MODEL="${WHISPER_MODEL:-ggml-small.en.bin}"

VOICE_DIR="$(dirname "$(realpath "$0")")/voice.d"

notify() {
  notify-send -h "string:x-tag:voice" -t 3000 -i microphone-sensitivity-high "$1" "$2"
}

start_recording() {
  if [ -f "$RECORDING_PID_FILE" ]; then
    notify "Already recording" "Press again to stop"
    return
  fi

  notify "${RECORD_MSG:-Recording...}" "Speak now"

  pw-record --channels=1 --rate=16000 "$AUDIO_FILE" &
  echo $! > "$RECORDING_PID_FILE"
}

transcribe() {
  if [ ! -f "$RECORDING_PID_FILE" ]; then
    notify "Not recording" ""
    return 1
  fi

  PID=$(cat "$RECORDING_PID_FILE")
  kill "$PID" 2>/dev/null
  rm "$RECORDING_PID_FILE"

  sleep 0.1

  notify "Transcribing..." "Please wait"

  TEXT=$("$WHISPER_BIN" \
    -m "$MODEL_DIR/$MODEL" \
    -f "$AUDIO_FILE" \
    --no-prints \
    -nt \
    2>/dev/null | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  EXITCODE=$?

  rm -f "$AUDIO_FILE"

  if [ $EXITCODE -eq 0 ] && [ -n "$TEXT" ]; then
    return 0
  else
    notify "Transcription failed" "Exit code: $EXITCODE"
    return 1
  fi
}
