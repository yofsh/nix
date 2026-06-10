# shellcheck shell=bash
# archive.sh — archive + image-collection helpers shared by bin/ scripts
# (yazi-convert, photo-print). Source, don't run.

is_image() {
  case "${1,,}" in
    *.jpg|*.jpeg|*.png|*.webp|*.heic|*.heif|*.tiff|*.tif|*.bmp|*.avif|*.gif) return 0 ;;
    *) return 1 ;;
  esac
}

is_archive() {
  case "${1,,}" in
    *.zip|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz|*.tar|*.rar|*.7z) return 0 ;;
    *) return 1 ;;
  esac
}

# extract_archive ARCHIVE DEST — tar handles the tarballs, 7z (fetched ad-hoc
# via nix-shell) everything else (zip/rar/7z).
extract_archive() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  case "${archive,,}" in
    *.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz|*.tar) tar xf "$archive" -C "$dest" ;;
    *) nix-shell -p p7zip --run "7z x -o'$dest' -bso0 '$archive'" >&2 ;;
  esac
}

# find_images DIR — NUL-separated, sorted image paths under DIR. Consume with:
#   while IFS= read -r -d '' f; do ...; done < <(find_images "$dir")
find_images() {
  find "$1" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
    -o -iname '*.webp' -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.tiff' \
    -o -iname '*.tif' -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.gif' \) -print0 | sort -z
}
