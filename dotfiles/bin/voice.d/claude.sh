# voice.d/claude.sh — transcribe and open Claude Code
# Sourced by voice dispatcher, not executed directly

RECORDING_PID_FILE="/tmp/voice_claude_recording.pid"
AUDIO_FILE="/tmp/voice_claude_recording.wav"
NOTIFY_ID=10021
RECORD_MSG="Recording for Claude..."

# Extra claude args (e.g. --model, --thinking)
CLAUDE_EXTRA_ARGS="${CLAUDE_EXTRA_ARGS:-}"

. "$VOICE_DIR/core.sh"

on_success() {
  notify "Opening Claude Code..." "$TEXT"
  foot -e bash -c "claude --dangerously-skip-permissions $CLAUDE_EXTRA_ARGS \"$TEXT\""
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
  *) echo "Usage: voice claude [start|stop|toggle]" ;;
esac
