# shellcheck shell=bash
# print-ui — interactive preview/tuner used by `photo-print`.
# Source AFTER print-layouts. Needs chafa + a TTY.
#
# Caller sets these before calling print_ui_run:
#   PUI_IMAGES   : array of source image paths (first 1-2 drive the live preview)
#   PUI_PRINTER  : printer name, or "" for tune-only (the print key is disabled)
#   pui_print()  : function `pui_print MODE ORIENT` that prints all images in the
#                  chosen mode (only called when PUI_PRINTER is non-empty)
#
# print_ui_run returns 0 if it printed, 1 if cancelled.
#
# Modes shown: photo, polaroid, polaroid-2, two-up, regular.
# Geometry lives in print-layouts' PL_* vars; this just drives them live.

PUI_MODES=(photo polaroid polaroid2 twoup regular)

# numeric knobs per mode: "label var step big min max" (blank = no knobs)
_pui_params() {
	case "$1" in
		polaroid)  printf '%s\n' "PAD  PL_PAD  2 10 0 300" ;;
		polaroid2) printf '%s\n' "PAD2   PL_PAD2    2 10 0 300" "ROTATE PL_ROTATE 90 90 0 270" ;;
		*) : ;;
	esac
}

_pui_nparams() { local n; n=$(_pui_params "${PUI_MODES[$pui_vi]}" | wc -l); echo "${n//[[:space:]]/}"; }

# render the current mode to the preview file, scaled to PUI_PCT% for responsiveness
_pui_render() {
	local mode="$1" pct="$PUI_PCT"
	(
		PL_SHEET_W=$(( PUI_SW * pct / 100 )); PL_SHEET_H=$(( PUI_SH * pct / 100 ))
		PL_A4_W=$(( PUI_A4W * pct / 100 ));   PL_A4_H=$(( PUI_A4H * pct / 100 ))
		PL_PAD=$(( PL_PAD * pct / 100 ));     PL_PAD2=$(( PL_PAD2 * pct / 100 ))
		case "$mode" in
			photo)     render_photo    "$PUI_S1" "$PUI_PREVIEW" ;;
			polaroid)  polaroid_single "$PUI_S1" "$PUI_PREVIEW" ;;
			polaroid2) polaroid_two    "$PUI_S1" "$PUI_S2" "$PUI_PREVIEW" ;;
			twoup)     render_two_up   "$PUI_S1" "$PUI_S2" "$PUI_PREVIEW" "$pui_orient" ;;
			regular)   render_regular  "$PUI_S1" "$PUI_PREVIEW" ;;
		esac
	)
}

_pui_lib_lines() {
	cat <<-EOF
	  : "\${PL_PAD:=$PL_PAD}"
	  : "\${PL_PAD2:=$PL_PAD2}"   : "\${PL_ROTATE:=$PL_ROTATE}"   : "\${PL_CUT:=$PL_CUT}"
	  : "\${PL_EDGE:=${PL_EDGE:-}}"
	EOF
}

_pui_read_key() {
	local k rest
	IFS= read -rsn1 k || return 1
	if [[ $k == $'\e' ]]; then IFS= read -rsn2 -t 0.01 rest || rest=''; k+="$rest"; fi
	printf '%s' "$k"
}

_pui_adjust() { # $1=+1|-1  $2=step|big
	local d="$1" which="$2" mode="${PUI_MODES[$pui_vi]}"
	local -a P spec
	mapfile -t P < <(_pui_params "$mode")
	[ "${#P[@]}" -gt 0 ] || return 0
	spec=(${P[$pui_sel]})
	local var="${spec[1]}" step="${spec[2]}" big="${spec[3]}" min="${spec[4]}" max="${spec[5]}"
	local delta="$step"; [ "$which" = big ] && delta="$big"
	local val="${!var}"
	if [ "$var" = PL_ROTATE ]; then
		val=$(( (val + d*90 + 360) % 360 ))
	else
		val=$(( val + d*delta ))
		if (( val < min )); then val="$min"; fi
		if (( val > max )); then val="$max"; fi
	fi
	printf -v "$var" '%s' "$val"
}

_pui_draw() {
	local mode="${PUI_MODES[$pui_vi]}"
	_pui_render "$mode"
	local cols lines imgrows i=0 np line name var val
	local -a P spec
	cols=$(tput cols); lines=$(tput lines)
	np=$(_pui_nparams)
	printf '\033[2J\033[H'
	[ -n "$PUI_PRINTER" ] && printf 'printer : %s\n' "$PUI_PRINTER"
	printf -- '-- mode: %s  [%d/%d]  Tab to switch --\n' "$mode" "$((pui_vi+1))" "${#PUI_MODES[@]}"
	mapfile -t P < <(_pui_params "$mode")
	for line in "${P[@]}"; do
		spec=(${line}); name="${spec[0]}"; var="${spec[1]}"; val="${!var}"
		if [ "$i" = "$pui_sel" ]; then printf ' \033[7m> %-8s %5s\033[0m\n' "$name" "$val"
		else printf '   %-8s %5s\n' "$name" "$val"; fi
		i=$((i+1))
	done
	case "$mode" in
		polaroid|polaroid2) printf '   %-8s %5s\n' "edge" "${PL_EDGE:-off}" ;;
	esac
	[ "$mode" = polaroid2 ] && printf '   %-8s %5s\n' "cut" "$([ "$PL_CUT" = 1 ] && echo on || echo off)"
	[ "$mode" = twoup ] && printf '   %-8s %5s\n' "orient" "$pui_orient"
	[ "$np" = 0 ] && [ "$mode" != twoup ] && echo "   (no adjustable values)"
	local act="q quit"
	[ -n "$PUI_PRINTER" ] && act="p PRINT   q cancel"
	echo "Tab mode  j/k sel  h/l -/+  H/L big  e edge  c cut  r rot  o orient  s show  $act"
	imgrows=$(( lines - 12 )); if (( imgrows < 6 )); then imgrows=6; fi
	# -c full: use the terminal's full colour range (foot sixel) so the preview is
	# less washed out. It's still a sixel approximation, not the real print colour.
	chafa -c full -s "${cols}x${imgrows}" "$PUI_PREVIEW" 2>/dev/null || true
}

print_ui_run() {
	PUI_PCT="${PUI_PCT:-50}"
	PUI_SW="$PL_SHEET_W"; PUI_SH="$PL_SHEET_H"; PUI_A4W="$PL_A4_W"; PUI_A4H="$PL_A4_H"
	local work; work="$(mktemp -d)"
	PUI_S1="$work/s1.jpg"; PUI_S2="$work/s2.jpg"; PUI_PREVIEW="$work/preview.jpg"
	if ! magick "${PUI_IMAGES[0]}" -auto-orient "${PL_TOSRGB[@]}" -strip -resize '720x720>' "$PUI_S1" 2>/dev/null; then
		echo "cannot read ${PUI_IMAGES[0]}" >&2; rm -rf "$work"; return 1
	fi
	if [ "${#PUI_IMAGES[@]}" -ge 2 ]; then
		magick "${PUI_IMAGES[1]}" -auto-orient "${PL_TOSRGB[@]}" -strip -resize '720x720>' "$PUI_S2" 2>/dev/null || cp "$PUI_S1" "$PUI_S2"
	else
		cp "$PUI_S1" "$PUI_S2"
	fi

	pui_vi=1; pui_sel=0; pui_orient="${pui_orient:-landscape}"
	local printed=1 k np
	printf '\033[?25l'   # hide cursor
	_pui_draw
	while true; do
		k="$(_pui_read_key)" || break
		case "$k" in
			q|$'\e') break ;;
			p) if [ -n "$PUI_PRINTER" ]; then
				printf '\033[2J\033[H\033[?25h'
				pui_print "${PUI_MODES[$pui_vi]}" "$pui_orient"; printed=0; break
			   fi ;;
			$'\t') pui_vi=$(( (pui_vi+1) % ${#PUI_MODES[@]} )); pui_sel=0; _pui_draw ;;
			j|$'\e[B') np=$(_pui_nparams); if (( np > 0 )); then pui_sel=$(( (pui_sel+1) % np )); fi; _pui_draw ;;
			k|$'\e[A') np=$(_pui_nparams); if (( np > 0 )); then pui_sel=$(( (pui_sel-1+np) % np )); fi; _pui_draw ;;
			l|$'\e[C'|'+'|'=') _pui_adjust +1 step; _pui_draw ;;
			h|$'\e[D'|'-'|'_') _pui_adjust -1 step; _pui_draw ;;
			L) _pui_adjust +1 big; _pui_draw ;;
			H) _pui_adjust -1 big; _pui_draw ;;
			e) if [ -n "$PL_EDGE" ]; then PL_EDGE=""; else PL_EDGE="gray85"; fi; _pui_draw ;;
			c) if [ "$PL_CUT" = 1 ]; then PL_CUT=0; else PL_CUT=1; fi; _pui_draw ;;
			r) PL_ROTATE=$(( (PL_ROTATE+90) % 360 )); _pui_draw ;;
			o) if [ "$pui_orient" = landscape ]; then pui_orient=portrait; else pui_orient=landscape; fi; _pui_draw ;;
			s) printf '\n'; _pui_lib_lines; echo '  (press any key)'; _pui_read_key >/dev/null; _pui_draw ;;
			*) : ;;
		esac
	done
	printf '\033[?25h'   # show cursor
	rm -rf "$work"
	[ "$printed" = 0 ] && return 0
	printf '\033[2J\033[H'
	echo "values -> paste as defaults in print-layouts:"; echo
	_pui_lib_lines
	return 1
}
