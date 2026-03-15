# worker.sh — prompts, transcript, comments, summary generation, background worker
# Sourced by yts after helpers.sh. Do not execute directly.

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

get_summary_prompt() {
	local lang="$1" has_comments="$2"
	local section_count lang_instruction

	if [[ "$has_comments" == "true" ]]; then
		section_count="five"
	else
		section_count="four"
	fi

	if [[ "$lang" == "en" ]]; then
		lang_instruction="Write ALL content in English."
	else
		lang_instruction="Write your ENTIRE response in the language identified by code '${lang}'. Translate ALL section headers and content to that language."
	fi

	printf '%s' "ultrathink

Analyze the video transcript and create a structured summary.

OUTPUT LANGUAGE: ${lang_instruction}

CRITICAL REQUIREMENTS:
- Output ONLY plain Markdown text without terminal formatting
- ALL ${section_count} sections are REQUIRED — do not skip any
- Use EXACTLY the section structure shown below
- Section headers shown below are in English for reference — translate them to the output language

Format (follow EXACTLY):

## Summary
2-3 sentence overview of the video content.

## Conclusion
Extended key takeaways (4-6 sentences covering main insights and implications).

## Topics Discussed
For EACH topic provide:

- **Topic name.** Short summary. Conclusion from the topic.
- **Topic name.** Short summary. Conclusion from the topic.
(list ALL main topics from the video in this format)
"

	if [[ "$has_comments" == "true" ]]; then
		cat <<'PROMPT'

## Audience Reactions 💬
*Analysis of viewer comments:*

**Overall sentiment:** [positive/mixed/negative/critical]

**Main discussion themes:**
- **[theme]** — what viewers are saying, how it relates to video content
- **[theme]** — what viewers are saying, how it relates to video content

**Interesting additions from viewers:** (if comments contain useful information)
- [additions/clarifications from viewers]

**Criticism and disagreement:** (if viewers express disagreement)
- [what viewers disagree with and why]
PROMPT
	fi

	cat <<'PROMPT'

## Robot Thoughts 🤖
*These are my personal reflections as an AI assistant:*

**Quality assessment:** [your evaluation of usefulness and reliability of the content]

**What looks valid:**
- **[statement]** — detailed explanation of why this is true, logical reasoning, known studies or sources that support this, practical examples if applicable
- **[statement]** — detailed explanation of why this is true, logical reasoning, known studies or sources that support this, practical examples if applicable
- ...

**Criticism:** (only if there are real issues related to the topic)
- 🔴 **[serious error]** — detailed explanation of why this is wrong, logical reasoning, counterarguments or sources that refute this
- 🟠 **[moderate problem]** — detailed explanation of the issue, why it matters, how it affects conclusions
- 🟡 **[minor concern]** — explanation of what's off and why it's worth noting

**Unconfirmed statements:** (only if there are questionable facts)
- 🔴 **[likely false claim]** — why it raises doubts, what facts contradict it, where to find refutation
- 🟠 **[needs verification]** — what exactly needs checking, which sources could confirm or refute
- 🟡 **[worth double-checking]** — why it's worth verifying, possible inaccuracies

**Questions raised:**
- **[question]** — why this is important to clarify, how the answer affects understanding of the topic
- **[question]** — why this is important to clarify, how the answer affects understanding of the topic
- ...

IMPORTANT:
- The "Robot Thoughts" section is REQUIRED — provide your honest critical assessment
- Do NOT use colored formatting or ANSI codes
- Remember: ALL output must be in the specified language

Transcript:
PROMPT
}

get_followup_prompt() {
	local lang="$1" question="$2" transcript_file="$3"
	local transcript_content lang_instruction
	transcript_content=$(<"$transcript_file")

	if [[ "$lang" == "en" ]]; then
		lang_instruction="Respond in English."
	else
		lang_instruction="Respond in the language identified by code '${lang}'."
	fi

	cat <<PROMPT
You are an assistant that answers questions about a video based on its transcript.

Rules:
- Answer only based on information from the transcript
- If the information is not in the transcript, honestly say so
- Be precise and specific
- Format your response in Markdown
- ${lang_instruction}

Video transcript:
${transcript_content}

User question: ${question}

Answer:
PROMPT
}

# ---------------------------------------------------------------------------
# Transcript downloading
# ---------------------------------------------------------------------------

download_transcript() {
	local url="$1" vid="$2"
	local lang last_error="" vtt_file transcript
	local -a langs cookie_args=()

	# Build cookie args if configured
	if [[ -n "${YTS_COOKIES_BROWSER:-}" ]]; then
		cookie_args=(--cookies-from-browser "$YTS_COOKIES_BROWSER")
	fi

	# Split $YTS_SUB_LANGS (comma-separated) into array
	IFS=',' read -ra langs <<<"$YTS_SUB_LANGS"

	for lang in "${langs[@]}"; do
		log "Trying subtitles: $lang"

		# Run yt-dlp; capture exit code without aborting
		if yt-dlp "${cookie_args[@]}" --write-auto-subs --sub-lang "$lang" --sub-format vtt \
			--skip-download -o "/tmp/$vid" "$url" 2>"/tmp/yts-ytdlp-err-$vid"; then
			# Success — look for VTT
			vtt_file=$(find /tmp -maxdepth 1 -name "${vid}*.vtt" -print -quit 2>/dev/null)
			if [[ -n "$vtt_file" ]]; then
				transcript=$(clean_vtt <"$vtt_file")
				rm -f "$vtt_file"
				if [[ -n "$transcript" ]]; then
					log "Got subtitles in $lang"
					printf '%s' "$transcript"
					rm -f "/tmp/yts-ytdlp-err-$vid"
					return 0
				fi
			fi
		else
			last_error=$(<"/tmp/yts-ytdlp-err-$vid")

			# yt-dlp may have written the VTT despite failing
			vtt_file=$(find /tmp -maxdepth 1 -name "${vid}*.vtt" -print -quit 2>/dev/null)
			if [[ -n "$vtt_file" ]]; then
				transcript=$(clean_vtt <"$vtt_file")
				rm -f "$vtt_file"
				if [[ -n "$transcript" ]]; then
					log "Found $lang subtitle file despite error, using it"
					printf '%s' "$transcript"
					rm -f "/tmp/yts-ytdlp-err-$vid"
					return 0
				fi
			fi
		fi
	done

	rm -f "/tmp/yts-ytdlp-err-$vid"

	# All attempts exhausted
	if [[ "$last_error" == *"Sign in to confirm"* ]] || [[ "$last_error" == *"not a bot"* ]]; then
		printf 'YouTube bot detection — try updating browser cookies' >&2
	elif [[ "$last_error" == *"reloaded"* ]]; then
		printf 'YouTube session expired — re-login in browser and retry' >&2
	elif [[ "$last_error" == *"429"* ]] || [[ "$last_error" == *"Too Many Requests"* ]]; then
		printf 'Rate limited by YouTube' >&2
	else
		printf 'No subtitles available for this video' >&2
	fi
	return 1
}

fetch_video_title_fallback() {
	local url="$1"
	local encoded_url response title

	encoded_url=$(jq -nr --arg url "$url" '$url|@uri') || return 1
	response=$(curl -fsSL "https://www.youtube.com/oembed?url=${encoded_url}&format=json" 2>/dev/null) || return 1
	title=$(printf '%s' "$response" | jq -r '.title // empty') || return 1
	[[ -n "$title" ]] || return 1
	printf '%s' "$title"
}

# ---------------------------------------------------------------------------
# Comments fetching
# ---------------------------------------------------------------------------

fetch_comments() {
	local vid="$1"
	local api_url response error_reason

	api_url="https://www.googleapis.com/youtube/v3/commentThreads?part=snippet&videoId=${vid}&maxResults=${YTS_MAX_COMMENTS}&order=relevance&textFormat=plainText&key=${YTS_YOUTUBE_API_KEY}"

	response=$(curl -s "$api_url") || {
		log "Warning: comments fetch network error"
		return 1
	}

	# Check for API errors
	if printf '%s' "$response" | jq -e '.error' >/dev/null 2>&1; then
		error_reason=$(printf '%s' "$response" | jq -r '.error.errors[0].reason // ""')

		case "$error_reason" in
		keyInvalid)
			log "Warning: Invalid YouTube API key"
			return 1
			;;
		commentsDisabled)
			log "Warning: Comments are disabled for this video"
			return 1
			;;
		quotaExceeded)
			log "Warning: YouTube API quota exceeded"
			return 1
			;;
		*)
			local err_msg
			err_msg=$(printf '%s' "$response" | jq -r '.error.message // "Unknown API error"')
			log "Warning: YouTube API error: $err_msg"
			return 1
			;;
		esac
	fi

	# Parse response into our format
	printf '%s' "$response" | jq \
		--arg vid "$vid" \
		--arg now "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
		'{
      videoId: $vid,
      fetchedAt: $now,
      totalResults: (.pageInfo.totalResults // (.items | length)),
      comments: [
        (.items // [])[] |
        .snippet.topLevelComment as $c |
        {
          id: $c.id,
          author: $c.snippet.authorDisplayName,
          text: $c.snippet.textDisplay,
          likeCount: $c.snippet.likeCount,
          publishedAt: $c.snippet.publishedAt
        }
      ]
    }'
}

# ---------------------------------------------------------------------------
# Summary generation
# ---------------------------------------------------------------------------

generate_summary() {
	local lang="$1" transcript_file="$2" comments_file="${3:-}"
	local has_comments="false"
	local prompt full_prompt summary claude_bin
	local -a required_sections

	# Determine if we have comments
	if [[ -n "$comments_file" && -f "$comments_file" ]]; then
		local comment_count
		comment_count=$(jq '.comments | length' "$comments_file" 2>/dev/null || echo 0)
		if [[ "$comment_count" -gt 0 ]]; then
			has_comments="true"
		fi
	fi

	# Build full prompt
	prompt=$(get_summary_prompt "$lang" "$has_comments")
	full_prompt="${prompt}$(cat "$transcript_file")"

	# Append comments if available
	if [[ "$has_comments" == "true" ]]; then
		local comments_appendix
		comments_appendix=$(_format_comments "$comments_file")
		full_prompt="${full_prompt}${comments_appendix}"
	fi

	# Find claude CLI
	claude_bin=$(command -v claude 2>/dev/null) || {
		printf 'claude CLI not found' >&2
		return 1
	}

	# Run claude with 5-minute timeout
	summary=$(printf '%s' "$full_prompt" | timeout 300 "$claude_bin" --print --no-session-persistence 2>/dev/null) || {
		printf 'Claude CLI failed or timed out' >&2
		return 1
	}

	# Strip ANSI escape codes
	summary=$(printf '%s' "$summary" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')

	# Strip <thinking>...</thinking> tags
	summary=$(printf '%s' "$summary" | sed ':a;N;$!ba;s/<thinking>.*<\/thinking>//g')

	# Trim
	summary=$(printf '%s' "$summary" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

	# Validate length and structure
	local summary_len=${#summary}
	if [[ "$summary_len" -lt 200 ]]; then
		printf 'Summary generation failed - response too short (%d chars)' "$summary_len" >&2
		return 1
	fi

	if [[ "$summary" != *"##"* ]]; then
		printf 'Summary generation failed - missing section headers' >&2
		return 1
	fi

	# Validate required sections
	if [[ "$lang" == "en" ]]; then
		required_sections=("## Summary" "## Conclusion" "## Topics Discussed" "## Robot Thoughts")
		local missing="" section
		for section in "${required_sections[@]}"; do
			local heading_text="${section#\#\# }"
			if ! printf '%s' "$summary" | grep -qiP "^##\s+\**${heading_text}\**\s*$"; then
				missing="${missing:+$missing, }$section"
			fi
		done
		if [[ -n "$missing" ]]; then
			log "Warning: summary missing sections: $missing — accepting anyway"
		fi
	else
		# For non-English output, headers are translated — just count them
		local header_count
		header_count=$(printf '%s' "$summary" | grep -cP '^\s*##\s' || true)
		if [[ "$header_count" -lt 3 ]]; then
			log "Warning: summary has only $header_count section headers (expected at least 4) — accepting anyway"
		fi
	fi

	printf '%s' "$summary"
}

# Internal helper: format comments appendix
_format_comments() {
	local comments_file="$1"
	jq -r '
    "\n\n---\n\nTop Comments from viewers:\n\n" +
    ([.comments | to_entries[] |
      "\(.key + 1). [\(.value.author)] (\(.value.likeCount) likes): \(.value.text)"]
    | join("\n\n"))
  ' "$comments_file"
}

# ---------------------------------------------------------------------------
# File saving
# ---------------------------------------------------------------------------

save_summary() {
	local vid="$1" title="$2" url="$3" summary_text="$4" transcript_file="$5" comments_file="${6:-}" duration="${7:-}"
	local summary_path transcript_path comments_path created

	created=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
	summary_path=$(get_summary_path "$vid" "$title")
	transcript_path=$(get_transcript_path "$vid" "$title")

	# Format duration
	local duration_str=""
	if [[ -n "$duration" && "$duration" -gt 0 ]] 2>/dev/null; then
		local mins=$((duration / 60)) secs=$((duration % 60))
		if [[ $mins -gt 0 ]]; then
			duration_str="${mins}m ${secs}s"
		else
			duration_str="${secs}s"
		fi
	fi

	# Write summary markdown
	{
		printf '# %s\n\n%s\n\n---\n\n' "$title" "$summary_text"
		printf '**URL:** %s\n' "$url"
		printf '**Created:** %s\n' "$created"
		[[ -n "$duration_str" ]] && printf '**Duration:** %s\n' "$duration_str"
	} >"$summary_path"

	log "Saved summary to: $summary_path"

	# Copy transcript
	cp "$transcript_file" "$transcript_path"
	log "Saved transcript to: $transcript_path"

	# Copy comments if provided
	if [[ -n "$comments_file" && -f "$comments_file" ]]; then
		comments_path=$(get_comments_path "$vid" "$title")
		cp "$comments_file" "$comments_path"
		log "Saved comments to: $comments_path"
	fi
}

# ---------------------------------------------------------------------------
# cmd_summarize — user-facing entry point
# ---------------------------------------------------------------------------

cmd_summarize() {
	local url="" lang="$YTS_LANG" vid norm_url existing

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-l | --lang)
			[[ -z "${2:-}" ]] && {
				printf 'Error: --lang requires a language code\n' >&2
				return 1
			}
			lang="$2"
			shift 2
			;;
		*) url="$1"; shift ;;
		esac
	done

	# 1. Get URL from arg, clipboard, or prompt
	if [[ -z "$url" ]]; then
		url=$(wl-paste --no-newline 2>/dev/null) || true
	fi

	if [[ -z "$url" ]] || ! is_valid_youtube_url "$url"; then
		read -rp 'Enter YouTube URL: ' url
	fi

	# 2. Validate
	if ! is_valid_youtube_url "$url"; then
		printf 'Error: Invalid YouTube URL: %s\n' "$url" >&2
		return 1
	fi

	vid=$(extract_video_id "$url")
	norm_url=$(normalize_youtube_url "$url")

	# 4. Check for existing summary
	if existing=$(find_existing_summary "$vid"); then
		notify "Summary exists" "Summary already exists for this video" normal
		printf 'Summary already exists: %s\n' "$existing"
		return 0
	fi

	# 5. Check if already processing
	if [[ -f "$YTS_PROCESSING_FILE" ]] &&
		jq -e --arg vid "$vid" '.items[] | select(.videoId == $vid)' "$YTS_PROCESSING_FILE" >/dev/null 2>&1; then
		notify "Already processing" "This video is already being processed" normal
		printf 'Video is already being processed: %s\n' "$vid"
		return 0
	fi

	# 6. Ensure directories
	ensure_dirs

	# 7. Write job JSON
	local job_file="$YTS_JOBS_DIR/${vid}.json"
	local created
	created=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

	cat >"$job_file" <<JOB
{
  "videoId": "${vid}",
  "url": "${norm_url}",
  "outputLanguage": "${lang}",
  "createdAt": "${created}",
  "youtubeApiKey": "${YTS_YOUTUBE_API_KEY}",
  "fetchComments": ${YTS_FETCH_COMMENTS},
  "maxComments": ${YTS_MAX_COMMENTS},
  "autoOpen": ${YTS_AUTO_OPEN}
}
JOB

	# 8. Spawn background worker
	nohup "$YTS_SELF" _worker "$job_file" >"/tmp/yts-worker-${vid}.log" 2>&1 &
	local worker_pid=$!

	# 9. Save PID
	printf '%d' "$worker_pid" >"/tmp/yts-worker-${vid}.pid"

	# 10. Notification
	notify "Processing started" "$norm_url" normal

	# 11. Terminal feedback
	printf 'Processing started for %s (pid %d)\n' "$norm_url" "$worker_pid"
	printf 'Worker log: /tmp/yts-worker-%s.log\n' "$vid"
}

# ---------------------------------------------------------------------------
# cmd_worker — background worker pipeline
# ---------------------------------------------------------------------------

cmd_worker() {
	local job_file="$1"
	local vid url lang api_key fetch_comments max_comments auto_open
	local title="Loading..." transcript summary
	local tmp_transcript="" tmp_comments=""

	# Read job config
	if [[ ! -f "$job_file" ]]; then
		log "Job config not found: $job_file"
		return 1
	fi

	vid=$(jq -r '.videoId' "$job_file")
	url=$(jq -r '.url' "$job_file")
	lang=$(jq -r '.outputLanguage' "$job_file")
	api_key=$(jq -r '.youtubeApiKey // ""' "$job_file")
	fetch_comments=$(jq -r '.fetchComments // false' "$job_file")
	max_comments=$(jq -r '.maxComments // 20' "$job_file")
	auto_open=$(jq -r '.autoOpen // false' "$job_file")

	local worker_start_epoch
	worker_start_epoch=$(date +%s)

	log "Processing video: $vid | URL: $url | Language: $lang"

	# Cleanup trap
	_worker_cleanup() {
		rm -f "${job_file:-}" "${tmp_transcript:-}" "${tmp_comments:-}"
		rm -f "/tmp/yts-worker-${vid:-unknown}.pid"
	}
	trap _worker_cleanup EXIT

	# Helper: fail with error
	_worker_fail() {
		local message="$1" failed_stage="$2"
		set_error "$vid" "$message" "$failed_stage" "$title" "$url"
		notify "Processing failed" "$message" critical
		return 1
	}

	# Check for existing summary
	if find_existing_summary "$vid" >/dev/null 2>&1; then
		log "Summary already exists"
		clear_item "$vid"
		return 0
	fi

	# --- Stage: getting_info ---
	set_stage "$vid" "getting_info" "$title" "$url"
	local info_output info_err info_status stderr_content
	info_err=$(mktemp)
	info_status=0
	local -a cookie_args=()
	if [[ -n "${YTS_COOKIES_BROWSER:-}" ]]; then
		cookie_args=(--cookies-from-browser "$YTS_COOKIES_BROWSER")
	fi
	info_output=$(timeout 30 yt-dlp "${cookie_args[@]}" --no-playlist --get-title "$url" 2>"$info_err") || info_status=$?
	title=$(printf '%s' "$info_output" | awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }')
	stderr_content=$(<"$info_err")
	rm -f "$info_err"

	if [[ -n "$title" ]]; then
		log "Got title from yt-dlp: $title"
	elif title=$(fetch_video_title_fallback "$url"); then
		log "Got title from oEmbed fallback: $title"
	elif [[ "$stderr_content" == *"unavailable"* ]] || [[ "$info_output" == *"unavailable"* ]]; then
		_worker_fail "Video not found or unavailable" "getting_info"
		return 1
	elif [[ "$stderr_content" == *"Private video"* ]] || [[ "$info_output" == *"Private video"* ]]; then
		_worker_fail "Video is private" "getting_info"
		return 1
	elif [[ "$stderr_content" == *"command not found"* ]]; then
		_worker_fail "yt-dlp not installed" "getting_info"
		return 1
	elif [[ "$stderr_content" == *"getaddrinfo"* ]] || [[ "$stderr_content" == *"ETIMEDOUT"* ]] ||
		[[ "$stderr_content" == *"Network"* ]] || [[ "$stderr_content" == *"network"* ]]; then
		_worker_fail "Network error" "getting_info"
		return 1
	else
		title="$vid"
		log "Warning: title lookup failed (exit $info_status); using video ID as title"
	fi

	# --- Stage: downloading_transcript ---
	set_stage "$vid" "downloading_transcript" "$title" "$url"
	tmp_transcript=$(mktemp /tmp/yts-transcript-XXXXXX.txt)

	local existing_transcript
	if existing_transcript=$(find_existing_transcript "$vid"); then
		log "Using existing transcript: $existing_transcript"
		cp "$existing_transcript" "$tmp_transcript"
	else
		if ! transcript=$(download_transcript "$url" "$vid"); then
			_worker_fail "${transcript:-Failed to download transcript}" "downloading_transcript"
			return 1
		fi
		printf '%s' "$transcript" >"$tmp_transcript"
	fi

	# --- Stage: fetching_comments (optional) ---
	if [[ "$fetch_comments" == "true" && -n "$api_key" ]]; then
		set_stage "$vid" "fetching_comments" "$title" "$url"
		log "Fetching comments (max: $max_comments)..."
		tmp_comments=$(mktemp /tmp/yts-comments-XXXXXX.json)

		local existing_comments
		if existing_comments=$(find_existing_comments "$vid"); then
			log "Using existing comments: $existing_comments"
			cp "$existing_comments" "$tmp_comments"
		elif fetch_comments "$vid" >"$tmp_comments" 2>/dev/null; then
			local ccount
			ccount=$(jq '.comments | length' "$tmp_comments" 2>/dev/null || echo 0)
			log "Fetched $ccount comments"
		else
			log "Warning: Comments fetch failed, continuing without comments"
			rm -f "$tmp_comments"
			tmp_comments=""
		fi
	fi

	# --- Stage: generating_summary ---
	set_stage "$vid" "generating_summary" "$title" "$url"
	if ! summary=$(generate_summary "$lang" "$tmp_transcript" "$tmp_comments"); then
		_worker_fail "${summary:-Failed to generate summary}" "generating_summary"
		return 1
	fi

	# --- Stage: saving ---
	set_stage "$vid" "saving" "$title" "$url"
	local elapsed=$(($(date +%s) - worker_start_epoch))
	save_summary "$vid" "$title" "$url" "$summary" "$tmp_transcript" "$tmp_comments" "$elapsed"

	# Success
	clear_item "$vid"
	notify "Summary ready" "$title" normal

	# Auto-open in foot terminal with bat if enabled
	if [[ "$auto_open" == "true" ]]; then
		local summary_path
		summary_path=$(get_summary_path "$vid" "$title")
		if command -v foot >/dev/null 2>&1 && command -v bat >/dev/null 2>&1; then
			foot -- bat --style=plain "$summary_path" &
		fi
	fi

	log "Successfully completed processing for $vid"
}

# ---------------------------------------------------------------------------
# cmd_retry — retry a failed job
# ---------------------------------------------------------------------------

cmd_retry() {
	local vid="${1:-}" url

	# If no VID given, pick from error items via fzf
	if [[ -z "$vid" ]]; then
		if [[ ! -f "$YTS_PROCESSING_FILE" ]]; then
			printf 'No processing file found\n' >&2
			return 1
		fi

		vid=$(jq -r '.items[] | select(.stage == "error") | "\(.videoId)\t\(.title)\t\(.error.message)"' \
			"$YTS_PROCESSING_FILE" 2>/dev/null |
			fzf --delimiter='\t' \
				--with-nth=2,3 \
				--header="Select failed job to retry" \
				--preview='echo "Video: {1}\nError: {3}"' |
			cut -f1)

		if [[ -z "$vid" ]]; then
			printf 'No job selected\n'
			return 1
		fi
	fi

	# Get the URL from processing file
	url=$(jq -r --arg vid "$vid" '.items[] | select(.videoId == $vid) | .url' \
		"$YTS_PROCESSING_FILE" 2>/dev/null)

	if [[ -z "$url" || "$url" == "null" ]]; then
		printf 'Error: Could not find URL for video %s\n' "$vid" >&2
		return 1
	fi

	# Clear the error item
	clear_item "$vid"

	# Re-submit
	cmd_summarize "$url"
}
