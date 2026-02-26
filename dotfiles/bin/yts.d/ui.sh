# ui.sh — UI functions for yts (sourced, not executed)
# Provides: notifications, fzf browsing, follow-up Q&A, transcript/comments
# viewing, status display, delete, and config commands.
# Depends on: helpers.sh (sourced before this file)

# --- Stage icon mapping ---

_stage_icon() {
  case "$1" in
    resolving_url)           printf '🔗' ;;
    getting_info)            printf 'ℹ️' ;;
    downloading_transcript)  printf '📝' ;;
    fetching_comments)       printf '💬' ;;
    generating_summary)      printf '🧠' ;;
    saving)                  printf '💾' ;;
    error)                   printf '❌' ;;
    *)                       printf '⏳' ;;
  esac
}

# --- Notifications ---

notify() {
  local title="$1" body="${2:-}" urgency="${3:-normal}"
  if [[ "$urgency" == "normal" && "$title" == "Summary ready" ]]; then
    (
      action=$(notify-send -a yts -i youtube -u "$urgency" \
        --action="open_list=Open list" --wait "$title" "$body") || true
      if [[ "$action" == "open_list" ]]; then
        hyprctl dispatch exec "[float; size 1400 (monitor_h*0.8); center] foot -e yts list"
      fi
    ) &
  else
    notify-send -a yts -i youtube -u "$urgency" "$title" "$body"
  fi
}

# --- Entry list builder (shared by select_video_fzf and cmd_list) ---

_build_entry_list() {
  local f title vid date_str

  # Append processing items at the top
  if [[ -f "$YTS_PROCESSING_FILE" ]]; then
    local items
    items=$(jq -r '.items // [] | .[]
      | [.videoId, .title, .stage,
         (.startedAt // .updatedAt // "")]
      | @tsv' "$YTS_PROCESSING_FILE" 2>/dev/null)
    while IFS=$'\t' read -r vid title stage started; do
      [[ -z "$vid" ]] && continue
      local icon
      icon=$(_stage_icon "$stage")
      printf '%s\t%s %s [%s]\t%s\t\n' \
        "$vid" "$icon" "$title" "$stage" "${started:0:10}"
    done <<< "$items"
  fi

  # List summary .md files
  if [[ -d "$YTS_DIR" ]]; then
    for f in "$YTS_DIR"/*.md; do
      [[ ! -f "$f" ]] && continue
      [[ "$(basename "$f")" == _* ]] && continue
      [[ "$f" == *_transcript* ]] && continue
      title=$(head -1 "$f" | sed 's/^# //')
      vid=$(basename "$f" .md | grep -oP '[a-zA-Z0-9_-]{11}$') || continue
      local epoch
      epoch=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      date_str=$(date -d @"$epoch" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$f" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
      local dur
      dur=$(grep -oP '(?<=\*\*Duration:\*\* ).*' "$f" 2>/dev/null) || true
      printf '%s\t%s\t%s %s\t%s\t%s\n' "$vid" "$title" "$date_str" "${dur:+($dur)}" "$f" "$epoch"
    done | sort -t$'\t' -k5 -rn | cut -f1-4
  fi
}

_build_error_list() {
  if [[ ! -f "$YTS_PROCESSING_FILE" ]]; then
    return
  fi
  local vid title stage error_msg
  jq -r '(.items // [])[] | select(.stage == "error")
    | [.videoId, .title, (.error.message // "unknown error"),
       (.updatedAt // "")]
    | @tsv' "$YTS_PROCESSING_FILE" 2>/dev/null |
  while IFS=$'\t' read -r vid title error_msg updated; do
    [[ -z "$vid" ]] && continue
    printf '%s\t❌ %s (%s)\t%s\t\n' "$vid" "$title" "$error_msg" "${updated:0:10}"
  done
}

# --- fzf picker ---

select_video_fzf() {
  local filter="${1:-}"
  local entries

  if [[ "$filter" == "errors" ]]; then
    entries=$(_build_error_list)
  else
    entries=$(_build_entry_list)
  fi

  if [[ -z "$entries" ]]; then
    printf 'No summaries found.\n' >&2
    return 1
  fi

  local selected
  selected=$(printf '%s\n' "$entries" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1..3 \
    --preview='[[ -n {4} ]] && glow -s dracula -w $FZF_PREVIEW_COLUMNS {4} 2>/dev/null || echo "No file available"' \
    --preview-window='right:60%:wrap' \
    --header='enter:select | ESC:cancel' \
    --prompt='Search summaries: ')

  [[ -z "$selected" ]] && return 1
  printf '%s' "$selected"
}

# --- cmd_list: full fzf browser ---

cmd_list() {
  local self="$YTS_SELF"

  _build_entry_list | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1..3 \
    --preview='[[ -n {4} ]] && glow -s dracula -w $FZF_PREVIEW_COLUMNS {4} 2>/dev/null || echo "No file available"' \
    --preview-window='right:60%:wrap' \
    --header='enter:view | C-l:refresh | C-c:copy | C-y:url | C-d:del | C-t:transcript | C-a:ask | C-r:retry' \
    --prompt='Summaries > ' \
    --bind="ctrl-l:reload(\"$self\" _entries)" \
    --bind="enter:execute([[ -n {4} ]] && glow -s dracula -w 0 -p {4} || echo 'No file available. Still processing?')" \
    --bind="ctrl-c:execute-silent([[ -n {4} ]] && cat {4} | wl-copy)+abort" \
    --bind="ctrl-y:execute-silent(echo 'https://www.youtube.com/watch?v='{1} | wl-copy)+abort" \
    --bind="ctrl-d:execute(bash -c '\"$0\" delete --force {1}' \"$self\")+reload(\"$self\" _entries)" \
    --bind="ctrl-t:execute(bash -c 'f={4}; tf=\"\${f%.md}_transcript.txt\"; [[ -f \"\$tf\" ]] && bat --paging=always --style=plain \"\$tf\" || echo \"No transcript found\"')" \
    --bind="ctrl-a:execute(foot -e bash -c '\"$0\" ask {1}' \"$self\")" \
    --bind="ctrl-r:execute(bash -c '\"$0\" retry {1}' \"$self\")" \
    || true
}

# --- cmd_ask: interactive follow-up Q&A ---

cmd_ask() {
  local vid="${1:-}"

  if [[ -z "$vid" ]]; then
    local selected
    selected=$(select_video_fzf) || return 1
    vid=$(printf '%s' "$selected" | cut -d$'\t' -f1)
  fi

  local transcript_file
  transcript_file=$(find_existing_transcript "$vid")
  if [[ -z "$transcript_file" || ! -f "$transcript_file" ]]; then
    printf 'Error: No transcript found for video %s\n' "$vid" >&2
    return 1
  fi

  local summary_file title
  summary_file=$(find_existing_summary "$vid")
  if [[ -n "$summary_file" && -f "$summary_file" ]]; then
    title=$(head -1 "$summary_file" | sed 's/^# //')
  else
    title="$vid"
  fi

  printf 'Ask questions about: %s\n' "$title"
  printf 'Type "q" or press Enter on empty line to quit.\n\n'

  local question answer prompt
  while true; do
    read -rp "Question (q to quit): " question
    [[ -z "$question" || "$question" == "q" ]] && break

    prompt=$(get_followup_prompt "$YTS_LANG" "$question" "$transcript_file")
    printf '\n'
    answer=$(printf '%s' "$prompt" | claude --print --no-session-persistence 2>/dev/null)
    if [[ -n "$answer" ]]; then
      printf '%s\n' "$answer" | bat --style=plain --color=always --language=md 2>/dev/null || printf '%s\n' "$answer"
    else
      printf 'Error: Failed to get answer.\n' >&2
    fi
    printf '\n'
  done
}

# --- cmd_transcript: view raw transcript ---

cmd_transcript() {
  local vid="${1:-}"

  if [[ -z "$vid" ]]; then
    local selected
    selected=$(select_video_fzf) || return 1
    vid=$(printf '%s' "$selected" | cut -d$'\t' -f1)
  fi

  local transcript_file
  transcript_file=$(find_existing_transcript "$vid")
  if [[ -z "$transcript_file" || ! -f "$transcript_file" ]]; then
    printf 'Error: No transcript found for video %s\n' "$vid" >&2
    return 1
  fi

  bat --style=plain --paging=always "$transcript_file"
}

# --- cmd_comments: view or fetch comments ---

cmd_comments() {
  local vid="${1:-}"

  if [[ -z "$vid" ]]; then
    local selected
    selected=$(select_video_fzf) || return 1
    vid=$(printf '%s' "$selected" | cut -d$'\t' -f1)
  fi

  local comments_file
  comments_file=$(find_existing_comments "$vid")

  if [[ -n "$comments_file" && -f "$comments_file" ]]; then
    jq -r '.comments[] | "[\(.author)] (\(.likeCount) likes):\n\(.text)\n"' \
      "$comments_file" 2>/dev/null | bat --style=plain --paging=always
    return 0
  fi

  # No cached comments
  if [[ -z "$YTS_YOUTUBE_API_KEY" ]]; then
    printf 'No comments cached for video %s.\n' "$vid"
    printf 'Set YTS_YOUTUBE_API_KEY to enable fetching comments from YouTube.\n'
    return 1
  fi

  local reply
  read -rp "No comments cached. Fetch from YouTube? [Y/n] " reply
  if [[ "$reply" =~ ^[Nn] ]]; then
    return 0
  fi

  # Determine title for path
  local summary_file title
  summary_file=$(find_existing_summary "$vid")
  if [[ -n "$summary_file" && -f "$summary_file" ]]; then
    title=$(head -1 "$summary_file" | sed 's/^# //')
  else
    title="$vid"
  fi

  local comments_data
  comments_data=$(fetch_comments "$vid")
  if [[ -z "$comments_data" ]]; then
    printf 'Error: Failed to fetch comments.\n' >&2
    return 1
  fi

  local out_path
  out_path=$(get_comments_path "$vid" "$title")
  printf '%s' "$comments_data" > "$out_path"
  printf 'Saved comments to %s\n' "$out_path"

  jq -r '.comments[] | "[\(.author)] (\(.likeCount) likes):\n\(.text)\n"' \
    "$out_path" 2>/dev/null | bat --style=plain --paging=always
}

# --- cmd_status: show active processing jobs ---

cmd_status() {
  if [[ ! -f "$YTS_PROCESSING_FILE" ]]; then
    printf 'No active processing jobs.\n'
    return 0
  fi

  local now_epoch
  now_epoch=$(date +%s)

  # Clean up stale items (>30 min old, not errors)
  local stale_threshold=$(( now_epoch - 1800 ))
  local tmp
  tmp=$(mktemp)
  jq --argjson threshold "$stale_threshold" '
    .items |= [.[] | select(
      .stage == "error" or
      ((.updatedAt // "1970-01-01T00:00:00") | gsub("[TZ]"; " ") | strptime("%Y-%m-%d %H:%M:%S") | mktime) > $threshold
    )]
  ' "$YTS_PROCESSING_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$YTS_PROCESSING_FILE"

  # Clean up stale PID files
  local pidfile pid
  for pidfile in /tmp/yts-worker-*.pid; do
    [[ ! -f "$pidfile" ]] && continue
    pid=$(<"$pidfile")
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pidfile"
    fi
  done

  local items
  items=$(jq -r '.items // [] | length' "$YTS_PROCESSING_FILE" 2>/dev/null)
  if [[ "$items" == "0" || -z "$items" ]]; then
    printf 'No active processing jobs.\n'
    return 0
  fi

  # Print header
  printf '%-13s %-24s %-30s %s\n' "VID" "Stage" "Title" "Duration"
  printf '%s\n' "$(printf '%.0s─' {1..80})"

  # Print each item
  jq -r '.items[] | [.videoId, .stage, .title,
    (.startedAt // .updatedAt // ""),
    (.error.message // ""),
    (.error.failedStage // "")] | @tsv' "$YTS_PROCESSING_FILE" 2>/dev/null |
  while IFS=$'\t' read -r vid stage title started error_msg failed_stage; do
    [[ -z "$vid" ]] && continue

    local icon duration_str
    icon=$(_stage_icon "$stage")

    # Calculate duration
    if [[ -n "$started" ]]; then
      local start_epoch
      start_epoch=$(date -d "$started" +%s 2>/dev/null || echo "$now_epoch")
      local diff=$(( now_epoch - start_epoch ))
      local mins=$(( diff / 60 ))
      local secs=$(( diff % 60 ))
      duration_str="${mins}m ${secs}s"
    else
      duration_str="-"
    fi

    # Truncate title
    local display_title="${title:0:28}"
    [[ ${#title} -gt 28 ]] && display_title="${display_title:0:25}..."

    local stage_display
    if [[ "$stage" == "error" && -n "$failed_stage" ]]; then
      stage_display="$icon error ($failed_stage)"
    else
      stage_display="$icon $stage"
    fi

    printf '%-13s %-24s %-30s %s\n' "$vid" "$stage_display" "$display_title" "$duration_str"

    # Show error message below the entry
    if [[ "$stage" == "error" && -n "$error_msg" ]]; then
      printf '              └─ %s\n' "$error_msg"
    fi
  done
}

# --- cmd_delete: delete summary files ---

cmd_delete() {
  local vid="" delete_all=false force=false
  local arg
  for arg in "$@"; do
    case "$arg" in
      --all) delete_all=true ;;
      --force|-f) force=true ;;
      *)     vid="$arg" ;;
    esac
  done

  if $delete_all; then
    local reply
    read -rp "Delete ALL summaries, transcripts, and comments? This cannot be undone. [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy] ]]; then
      printf 'Cancelled.\n'
      return 0
    fi

    local count=0
    local f
    for f in "$YTS_DIR"/*.md "$YTS_DIR"/*_transcript.txt "$YTS_DIR"/*_comments.json; do
      [[ ! -f "$f" ]] && continue
      [[ "$(basename "$f")" == _* ]] && continue
      rm -f "$f"
      count=$(( count + 1 ))
    done
    printf 'Deleted %d files.\n' "$count"
    return 0
  fi

  if [[ -z "$vid" ]]; then
    local selected
    selected=$(select_video_fzf) || return 1
    vid=$(printf '%s' "$selected" | cut -d$'\t' -f1)
  fi

  # Find files for this VID
  local files=()
  local f
  for f in "$YTS_DIR"/*"${vid}"*; do
    [[ -f "$f" ]] && files+=("$f")
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    printf 'No files found for video %s\n' "$vid"
    # Still try to clear from processing
    clear_item "$vid"
    return 0
  fi

  # Get title for confirmation
  local title=""
  local summary_file
  summary_file=$(find_existing_summary "$vid")
  if [[ -n "$summary_file" && -f "$summary_file" ]]; then
    title=$(head -1 "$summary_file" | sed 's/^# //')
  else
    title="$vid"
  fi

  printf 'Files to delete:\n'
  local f
  for f in "${files[@]}"; do
    printf '  %s\n' "$(basename "$f")"
  done

  if ! $force; then
    local reply
    read -rp "Delete files for '$title'? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy] ]]; then
      printf 'Cancelled.\n'
      return 0
    fi
  fi

  for f in "${files[@]}"; do
    rm -f "$f"
    printf 'Deleted: %s\n' "$(basename "$f")"
  done

  clear_item "$vid"
  printf 'Done.\n'
}

# --- cmd_config: show or edit config ---

cmd_config() {
  local action="${1:-}"

  if [[ "$action" == "edit" ]]; then
    local config_dir
    config_dir=$(dirname "$YTS_CONFIG_FILE")
    mkdir -p "$config_dir"

    if [[ ! -f "$YTS_CONFIG_FILE" ]]; then
      cat > "$YTS_CONFIG_FILE" << 'DEFAULTCFG'
# yts configuration
# This file is sourced as bash. Set variables as needed.

# Summary language: ru or en
#YTS_LANG=ru

# YouTube API key for comments (optional)
#YTS_YOUTUBE_API_KEY=

# Fetch comments with summary
#YTS_FETCH_COMMENTS=false

# Max comments to fetch
#YTS_MAX_COMMENTS=20

# Auto-open summary on completion
#YTS_AUTO_OPEN=false

# Subtitle languages to try (comma-separated, in order)
#YTS_SUB_LANGS=en,ru,uk

# Summaries directory
#YTS_DIR=~/Documents/video_summaries
DEFAULTCFG
      printf 'Created default config at %s\n' "$YTS_CONFIG_FILE"
    fi

    "${EDITOR:-vim}" "$YTS_CONFIG_FILE"
    return
  fi

  # Print current config
  printf 'YTS_DIR=%s\n' "$YTS_DIR"
  printf 'YTS_LANG=%s\n' "$YTS_LANG"
  printf 'YTS_YOUTUBE_API_KEY=%s\n' "${YTS_YOUTUBE_API_KEY:+(set)}${YTS_YOUTUBE_API_KEY:-(not set)}"
  printf 'YTS_FETCH_COMMENTS=%s\n' "$YTS_FETCH_COMMENTS"
  printf 'YTS_MAX_COMMENTS=%s\n' "$YTS_MAX_COMMENTS"
  printf 'YTS_AUTO_OPEN=%s\n' "$YTS_AUTO_OPEN"
  printf 'YTS_SUB_LANGS=%s\n' "$YTS_SUB_LANGS"
  printf 'Config file: %s\n' "$YTS_CONFIG_FILE"
}
