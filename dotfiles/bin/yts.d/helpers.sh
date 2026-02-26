log() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%S)"
  printf '[%s] [yts] %s\n' "$ts" "$1" >&2
}

extract_video_id() {
  local url="$1" vid
  vid=$(printf '%s' "$url" | grep -oP '(?:youtube\.com/(?:watch\?.*?v=|embed/|v/|shorts/)|youtu\.be/)\K[a-zA-Z0-9_-]{11}' | head -1) || true
  if [[ -z "$vid" ]]; then
    return 1
  fi
  printf '%s' "$vid"
}

is_valid_youtube_url() {
  extract_video_id "$1" >/dev/null 2>&1
}

normalize_youtube_url() {
  local vid
  vid=$(extract_video_id "$1") || return 1
  printf 'https://www.youtube.com/watch?v=%s' "$vid"
}

sanitize_filename() {
  local title="$1" result
  result=$(printf '%s' "$title" | sed -e 's/[<>:"\/\\|?*]//g' -e 's/[[:space:]]\+/_/g')
  printf '%s' "${result:0:80}"
}

get_summary_path() {
  local vid="$1" title="$2"
  printf '%s/%s_%s.md' "$YTS_DIR" "$(sanitize_filename "$title")" "$vid"
}

get_transcript_path() {
  local vid="$1" title="$2"
  printf '%s/%s_%s_transcript.txt' "$YTS_DIR" "$(sanitize_filename "$title")" "$vid"
}

get_comments_path() {
  local vid="$1" title="$2"
  printf '%s/%s_%s_comments.json' "$YTS_DIR" "$(sanitize_filename "$title")" "$vid"
}

find_existing_summary() {
  local vid="$1" found
  found=$(find "$YTS_DIR" -maxdepth 1 -name "*${vid}.md" ! -name "*_transcript*" -print -quit 2>/dev/null)
  if [[ -z "$found" ]]; then
    return 1
  fi
  printf '%s' "$found"
}

find_existing_transcript() {
  local vid="$1" found
  found=$(find "$YTS_DIR" -maxdepth 1 -name "*${vid}_transcript.txt" -print -quit 2>/dev/null)
  if [[ -z "$found" ]]; then
    return 1
  fi
  printf '%s' "$found"
}

find_existing_comments() {
  local vid="$1" found
  found=$(find "$YTS_DIR" -maxdepth 1 -name "*${vid}_comments.json" -print -quit 2>/dev/null)
  if [[ -z "$found" ]]; then
    return 1
  fi
  printf '%s' "$found"
}

clean_vtt() {
  awk '
    BEGIN { last = "" }
    /^WEBVTT/      { next }
    /^Kind:/       { next }
    /^Language:/   { next }
    /^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} *-->/ { next }
    /^[[:space:]]*[0-9]+[[:space:]]*$/ { next }
    /^[[:space:]]*$/ { next }
    /align:/       { next }
    /position:/    { next }
    {
      gsub(/<[^>]+>/, "")
      gsub(/\&nbsp;/, " ")
      gsub(/\&amp;/, "\\&")
      gsub(/\&lt;/, "<")
      gsub(/\&gt;/, ">")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      if ($0 != "" && $0 != last) {
        lines[++n] = $0
        last = $0
      }
    }
    END {
      result = ""
      for (i = 1; i <= n; i++) {
        result = (i == 1) ? lines[i] : result " " lines[i]
      }
      gsub(/  +/, " ", result)
      print result
    }
  '
}

get_processing_items() {
  if [[ ! -f "$YTS_PROCESSING_FILE" ]]; then
    printf '[]'
    return
  fi
  jq -r '.items // []' "$YTS_PROCESSING_FILE" 2>/dev/null || printf '[]'
}

set_stage() {
  local vid="$1" stage="$2" title="$3" url="$4"
  local now tmp
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  tmp=$(mktemp)

  local current='{"items":[]}'
  if [[ -f "$YTS_PROCESSING_FILE" ]]; then
    current=$(jq '.' "$YTS_PROCESSING_FILE" 2>/dev/null) || current='{"items":[]}'
  fi

  printf '%s' "$current" | jq \
    --arg vid "$vid" \
    --arg stage "$stage" \
    --arg title "$title" \
    --arg url "$url" \
    --arg now "$now" \
    '
    if (.items | map(.videoId) | index($vid)) then
      .items |= map(
        if .videoId == $vid then
          .stage = $stage |
          .updatedAt = $now |
          (if $title != "" then .title = $title else . end)
        else . end
      )
    else
      .items += [{
        videoId: $vid,
        url: $url,
        title: (if $title != "" then $title else "Loading..." end),
        stage: $stage,
        startedAt: $now,
        updatedAt: $now
      }]
    end
    ' > "$tmp" && mv "$tmp" "$YTS_PROCESSING_FILE"

  log "Stage: $stage | Video: $vid"
}

set_error() {
  local vid="$1" message="$2" failed_stage="$3" title="$4" url="$5"
  local now tmp
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  tmp=$(mktemp)

  local current='{"items":[]}'
  if [[ -f "$YTS_PROCESSING_FILE" ]]; then
    current=$(jq '.' "$YTS_PROCESSING_FILE" 2>/dev/null) || current='{"items":[]}'
  fi

  printf '%s' "$current" | jq \
    --arg vid "$vid" \
    --arg message "$message" \
    --arg failed_stage "$failed_stage" \
    --arg title "$title" \
    --arg url "$url" \
    --arg now "$now" \
    '
    if (.items | map(.videoId) | index($vid)) then
      .items |= map(
        if .videoId == $vid then
          .stage = "error" |
          .updatedAt = $now |
          .error = {message: $message, failedStage: $failed_stage} |
          (if $title != "" then .title = $title else . end)
        else . end
      )
    else
      .items += [{
        videoId: $vid,
        url: $url,
        title: (if $title != "" then $title else "Unknown" end),
        stage: "error",
        startedAt: $now,
        updatedAt: $now,
        error: {message: $message, failedStage: $failed_stage}
      }]
    end
    ' > "$tmp" && mv "$tmp" "$YTS_PROCESSING_FILE"

  log "Error: $message | Stage: $failed_stage | Video: $vid"
}

clear_item() {
  local vid="$1" tmp
  [[ ! -f "$YTS_PROCESSING_FILE" ]] && return
  tmp=$(mktemp)
  jq --arg vid "$vid" '.items |= map(select(.videoId != $vid))' \
    "$YTS_PROCESSING_FILE" > "$tmp" && mv "$tmp" "$YTS_PROCESSING_FILE"
  log "Cleared processing status | Video: $vid"
}

ensure_dirs() {
  mkdir -p "$YTS_DIR" "$YTS_JOBS_DIR"
}
