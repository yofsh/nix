# shellcheck shell=bash
# print-layouts — shared print-layout rendering for `photo-print` (and its preview).
# Sourced, not executed. Geometry is tunable via PL_* env vars (defaults below), so
# the live preview can experiment without editing anything; once you settle on numbers,
# bake them in by editing the defaults here (both the preview and printing use them).
#
# A "polaroid card" fills a box: a square photo with EQUAL padding on top + left +
# right, and the bottom (the thick caption) is simply whatever height is left over.
# Only the padding is adjustable; the bottom is always derived. Sharp corners.

# Sheet = 4x6 @ 300dpi (portrait), matches 4x6.Borderless media exactly.
: "${PL_SHEET_W:=1200}"
: "${PL_SHEET_H:=1800}"
# A4 @ 300dpi (for the "regular" mode preview).
: "${PL_A4_W:=2480}"
: "${PL_A4_H:=3508}"

# Colour: convert each source to sRGB using its EMBEDDED profile (e.g. Display P3
# from phones) so prints aren't washed out. Falls back to a plain sRGB tag if the
# bundled profile is missing. PL_TOSRGB is spliced in right after the source loads.
: "${PL_SRGB:=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/sRGB.icc}"
if [ -f "$PL_SRGB" ]; then PL_TOSRGB=(-profile "$PL_SRGB"); else PL_TOSRGB=(-colorspace sRGB); fi

# --- single polaroid (fills the whole sheet) ---
: "${PL_PAD:=26}"        # equal margin on top/left/right; bottom fills the rest

# --- two polaroids (rotated 90deg, stacked; card size auto = same shape as single) ---
: "${PL_PAD2:=26}"       # equal margin on three sides of each card
: "${PL_ROTATE:=90}"     # rotation applied to each card
: "${PL_CUT:=1}"         # 1 = dashed cut guide down the middle, 0 = off
: "${PL_CUT_COLOR:=gray70}"

# faint hairline that separates the photo from the white frame ('' disables it)
: "${PL_EDGE:=gray85}"

# _pl_card SRC OUT BOX_W BOX_H PAD  — fill a BOX_W x BOX_H card: square photo with
# equal PAD on top/left/right, thick bottom caption = the leftover height.
_pl_card() {
	local src="$1" out="$2" bw="$3" bh="$4" pad="$5"
	local photo=$(( bw - 2*pad ))
	local edge=()
	[ -n "$PL_EDGE" ] && edge=(-bordercolor "$PL_EDGE" -border 1)
	magick -size "${bw}x${bh}" xc:white \
		\( "$src" -auto-orient "${PL_TOSRGB[@]}" \
			-resize "${photo}x${photo}^" -gravity center -extent "${photo}x${photo}" \
			"${edge[@]}" \) \
		-gravity North -geometry "+0+${pad}" -compose Over -composite \
		-density 300 -units PixelsPerInch -quality 95 \
		"$out"
}

# polaroid_single SRC OUT  — one polaroid filling the whole 4x6 sheet.
polaroid_single() {
	_pl_card "$1" "$2" "$PL_SHEET_W" "$PL_SHEET_H" "$PL_PAD"
}

# polaroid_two A B OUT  — two polaroids rotated PL_ROTATE deg, stacked on a 4x6 sheet.
# Each card's size is auto-derived so the card has the same shape as the single
# (rotated to fill the sheet width); gaps are derived so the middle gap is exactly
# 2x the top/bottom edge gaps (cut the middle -> equal margin all round); a dashed
# cut guide is centred in the middle gap.
polaroid_two() {
	local a="$1" b="$2" out="$3" ca cb
	ca="$(mktemp --suffix=.png)"; cb="$(mktemp --suffix=.png)"
	# rotated card height = boxw (= sheetW^2/sheetH, same proportion as the single).
	local boxw=$(( PL_SHEET_W * PL_SHEET_W / PL_SHEET_H ))
	# edge gap g; middle gap = 2g  (4g + 2*boxw = sheetH).
	local g=$(( (PL_SHEET_H - 2*boxw) / 4 ))
	if (( g < 0 )); then g=0; fi
	# Card length = sheet width inset by g on each side, so the photo keeps the SAME g
	# margin from EVERY sheet edge (top/bottom/left/right) — otherwise the rotated
	# photo's top edge sits flush against the side of the sheet.
	local cardlen=$(( PL_SHEET_W - 2*g ))
	_pl_card "$a" "$ca" "$boxw" "$cardlen" "$PL_PAD2"
	_pl_card "$b" "$cb" "$boxw" "$cardlen" "$PL_PAD2"
	local mid=$(( PL_SHEET_H / 2 )) x1=$g x2=$(( PL_SHEET_W - g ))
	local cut=()
	if [ "$PL_CUT" = 1 ]; then
		cut=(-stroke "$PL_CUT_COLOR" -strokewidth 2 -fill none
			-draw "stroke-dasharray 16 12 line ${x1},${mid} ${x2},${mid}")
	fi
	magick -size "${PL_SHEET_W}x${PL_SHEET_H}" xc:white \
		\( "$ca" -background white -rotate "$PL_ROTATE" \) \
			-gravity North -geometry "+0+${g}" -compose Over -composite \
		\( "$cb" -background white -rotate "$PL_ROTATE" \) \
			-gravity South -geometry "+0+${g}" -compose Over -composite \
		"${cut[@]}" \
		-background white -flatten \
		-density 300 -units PixelsPerInch -quality 95 "$out"
	rm -f "$ca" "$cb"
}

# render_photo SRC OUT  — plain 4x6 borderless: fill the sheet (centre-crop overflow).
render_photo() {
	magick "$1" -auto-orient "${PL_TOSRGB[@]}" \
		-resize "${PL_SHEET_W}x${PL_SHEET_H}^" -gravity center -extent "${PL_SHEET_W}x${PL_SHEET_H}" \
		-density 300 -units PixelsPerInch -quality 95 "$2"
}

# render_two_up A B OUT [landscape|portrait]  — two photos filled (no frame) on one sheet:
#   landscape -> stacked top/bottom ;  portrait -> side-by-side on a rotated sheet.
render_two_up() {
	local a="$1" b="$2" out="$3" orient="${4:-landscape}"
	local gut=$(( PL_SHEET_W / 60 ))
	if [ "$orient" = portrait ]; then
		local cw=$(( (PL_SHEET_H - gut) / 2 ))
		magick -size "${PL_SHEET_H}x${PL_SHEET_W}" xc:white \
			\( "$a" -auto-orient "${PL_TOSRGB[@]}" -resize "${cw}x${PL_SHEET_W}^" -gravity center -extent "${cw}x${PL_SHEET_W}" \) -gravity West -composite \
			\( "$b" -auto-orient "${PL_TOSRGB[@]}" -resize "${cw}x${PL_SHEET_W}^" -gravity center -extent "${cw}x${PL_SHEET_W}" \) -gravity East -composite \
			-density 300 -units PixelsPerInch -quality 95 "$out"
	else
		local ch=$(( (PL_SHEET_H - gut) / 2 ))
		magick -size "${PL_SHEET_W}x${PL_SHEET_H}" xc:white \
			\( "$a" -auto-orient "${PL_TOSRGB[@]}" -resize "${PL_SHEET_W}x${ch}^" -gravity center -extent "${PL_SHEET_W}x${ch}" \) -gravity North -composite \
			\( "$b" -auto-orient "${PL_TOSRGB[@]}" -resize "${PL_SHEET_W}x${ch}^" -gravity center -extent "${PL_SHEET_W}x${ch}" \) -gravity South -composite \
			-density 300 -units PixelsPerInch -quality 95 "$out"
	fi
}

# render_regular SRC OUT  — A4 plain paper: fit the whole image with white margins.
render_regular() {
	magick -size "${PL_A4_W}x${PL_A4_H}" xc:white \
		\( "$1" -auto-orient "${PL_TOSRGB[@]}" -resize "${PL_A4_W}x${PL_A4_H}" \) \
		-gravity center -compose Over -composite \
		-density 300 -units PixelsPerInch -quality 95 "$2"
}
