# voice.d/stream.sh — VAD continuous streaming transcription
# Sourced by voice dispatcher, not executed directly

PID_FILE="/tmp/voice_stream.pid"
FIFO="/tmp/voice_stream.fifo"

MODEL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/whisper-cpp"
MODEL="${WHISPER_MODEL:-ggml-small.en.bin}"

# VAD mode settings
VAD_THOLD="${VAD_THOLD:-0.6}"
AUDIO_LEN="${AUDIO_LEN:-10000}"
CAPTURE_ID="${CAPTURE_ID:--1}"

notify() {
  notify-send -h "string:x-tag:voice-stream" -t 3000 -i microphone-sensitivity-high "$1" "$2"
}

start_stream() {
  if [ -f "$PID_FILE" ]; then
    notify "Already streaming" "Press again to stop"
    return
  fi

  if [ ! -f "$MODEL_DIR/$MODEL" ]; then
    notify "Model not found" "$MODEL_DIR/$MODEL"
    return 1
  fi

  rm -f "$FIFO"
  mkfifo "$FIFO"

  whisper-stream \
    -m "$MODEL_DIR/$MODEL" \
    --step 0 \
    --length "$AUDIO_LEN" \
    --vad-thold "$VAD_THOLD" \
    --capture "$CAPTURE_ID" \
    --no-flash-attn \
    -t 4 \
    2>/dev/null > "$FIFO" &
  STREAM_PID=$!

  (
    in_block=false
    block_text=""
    last_text=""
    while IFS= read -r line; do
      if [[ "$line" == *"START"* ]]; then
        in_block=true
        block_text=""
        continue
      fi
      if [[ "$line" == *"END"* ]]; then
        in_block=false
        block_text=$(echo "$block_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$block_text" ] && [ "$block_text" != "$last_text" ]; then
          if [ -n "$last_text" ] && [[ "$block_text" == "$last_text"* ]]; then
            new_part="${block_text#"$last_text"}"
            new_part=$(echo "$new_part" | sed 's/^[[:space:]]*//')
            if [ -n "$new_part" ]; then
              wtype " $new_part"
            fi
          else
            wtype "$block_text "
          fi
          last_text="$block_text"
        fi
        continue
      fi
      if $in_block; then
        text=$(echo "$line" | sed 's/^\[.*\] *//')
        if [ -n "$text" ]; then
          block_text="${block_text} ${text}"
        fi
      fi
    done < "$FIFO"
  ) &
  PARSER_PID=$!

  echo "${STREAM_PID}:${PARSER_PID}" > "$PID_FILE"
  notify "Streaming dictation ON" "Speak naturally, pauses trigger transcription"
}

stop_stream() {
  if [ ! -f "$PID_FILE" ]; then
    notify "Not streaming" ""
    return
  fi

  IFS=':' read -r STREAM_PID PARSER_PID < "$PID_FILE"
  kill "$STREAM_PID" 2>/dev/null
  kill "$PARSER_PID" 2>/dev/null
  rm -f "$PID_FILE" "$FIFO"

  notify "Streaming dictation OFF" ""
}

do_toggle() {
  if [ -f "$PID_FILE" ]; then
    stop_stream
  else
    start_stream
  fi
}

case "${1:-toggle}" in
  start) start_stream ;;
  stop) stop_stream ;;
  toggle) do_toggle ;;
  *) echo "Usage: voice stream [start|stop|toggle]" ;;
esac
