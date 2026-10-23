#!/usr/bin/env bash
# MacTahoe folder icons — dynamic color template for Noctalia.
# Reads colors-final, finds the closest MacTahoe palette color to the
# target, then recolors the base theme's folder SVGs.
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
COLOR_FILE="$CONFIG_DIR/colors-final"

[[ -f "$COLOR_FILE" ]] || exit 0

mapfile -t lines <"$COLOR_FILE"

TARGET="${lines[0]//[# ]/}"
[[ ${#TARGET} -ge 6 ]] || exit 0
TARGET="${TARGET:0:6}"

TR=$((16#${TARGET:0:2}))
TG=$((16#${TARGET:2:2}))
TB=$((16#${TARGET:4:2}))

MAPPING="${lines[${#lines[@]}-1]}"

closest=$(
  awk -v r="$TR" -v g="$TG" -v b="$TB" -v m="$MAPPING" '
  function rgb2hsv(r,g,b, mx,mn,d,h,s,v,t) {
    r/=255; g/=255; b/=255
    mx = (r>g)?(r>b?r:b):(g>b?g:b)
    mn = (r<g)?(r<b?r:b):(g<b?g:b)
    v = mx
    d = mx - mn
    if (d == 0) { s = 0; h = 0 }
    else {
      s = d / mx
      if (mx == r) {
        t = (g - b) / d
        if (t < 0) t += 6
        h = 60 * t
      } else if (mx == g) {
        h = 60 * (((b - r) / d) + 2)
      } else {
        h = 60 * (((r - g) / d) + 4)
      }
    }
    return h SUBSEP s SUBSEP v
  }
  BEGIN {
    WH = 10; WS = 1; WV = 0.3
    split(rgb2hsv(r,g,b), tgt, SUBSEP)
    th = tgt[1]; ts = tgt[2]; tv = tgt[3]
    n = split(m, arr)
    for (i = 1; i <= n; i++) {
      split(arr[i], p, ":")
      cr = strtonum("0x" substr(p[2],1,2))
      cg = strtonum("0x" substr(p[2],3,2))
      cb = strtonum("0x" substr(p[2],5,2))
      split(rgb2hsv(cr,cg,cb), c, SUBSEP)
      ch = c[1]; cs = c[2]; cv = c[3]
      dh = th - ch
      if (dh < 0) dh = -dh
      if (dh > 180) dh = 360 - dh
      dh /= 180
      ds = ts - cs
      dv = tv - cv
      d = WH * (ts*cs) * dh*dh + WS * ds*ds + WV * dv*dv
      if (min == "" || d < min) { min = d; name = p[1] }
    }
    print name
  }
')

msg() { printf '%s: %s\n' "${0##*/}" "$*"; } >&2

# Palette hex values
declare -A PALETTE=(
  [blue]=006efd   [green]=27d83d  [grey]=686868
  [orange]=ff8b1d [purple]=aa5adc [red]=fe342c   [yellow]=ffc61d
)

# Compute HSV variants (dark / main / medium / light) for a hex color.
color_variants() {
  local hex="$1"
  local r g b
  r=$((16#${hex:0:2}))
  g=$((16#${hex:2:2}))
  b=$((16#${hex:4:2}))
  awk -v r=$r -v g=$g -v b=$b '
function rgb2hsv(r,g,b,  mx,mn,d,h,s,v,t) {
  r/=255; g/=255; b/=255
  mx=(r>g)?(r>b?r:b):(g>b?g:b); mn=(r<g)?(r<b?r:b):(g<b?g:b)
  v=mx; d=mx-mn
  if(d==0){s=0;h=0} else { s=d/mx
    if(mx==r){t=(g-b)/d;if(t<0)t+=6;h=60*t}
    else if(mx==g){h=60*(((b-r)/d)+2)}
    else{h=60*(((r-g)/d)+4)}
  }
  return h SUBSEP s SUBSEP v
}
function hsv2rgb(h,s,v,  hi,f,p,q,tm,rv,gv,bv) {
  hi=int(h/60)%6; f=h/60-int(h/60)
  p=v*(1-s); q=v*(1-f*s); tm=v*(1-(1-f)*s)
  if(hi==0){rv=v;gv=tm;bv=p}
  else if(hi==1){rv=q;gv=v;bv=p}
  else if(hi==2){rv=p;gv=v;bv=tm}
  else if(hi==3){rv=p;gv=q;bv=v}
  else if(hi==4){rv=tm;gv=p;bv=v}
  else{rv=v;gv=p;bv=q}
  printf "%02x%02x%02x", int(rv*255), int(gv*255), int(bv*255)
}
BEGIN {
  split(rgb2hsv(r,g,b), t, SUBSEP)
  h=t[1]+0; s=t[2]+0; v=t[3]+0
  ds=s*1.25; if(ds>1)ds=1; dv=v*0.80
  hsv2rgb(h,ds,dv); printf "\n"
  printf "%02x%02x%02x\n",r,g,b
  ms=s*0.90; mv=v*1.10; if(mv>1)mv=1
  hsv2rgb(h,ms,mv); printf "\n"
  ls=s*0.75; lv=v*1.15; if(lv>1)lv=1
  hsv2rgb(h,ls,lv); printf "\n"
}'
}

# All known blue shades used in MacTahoe SVGs (main + gradient)
BLUE_SHADES=(006efd 56a1d3 67b1de 7cc1ea 88ccf2 46a2d7 008ea2 60c0f0 83d4fb)

active_theme() {
  local t
  t="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true)"
  t="${t//\'/}"
  [[ -n "$t" ]] && printf '%s' "$t"
}

find_system_source() {
  local name="$1" base
  for base in /usr/share/icons /usr/local/share/icons; do
    if [[ -f "$base/$name/index.theme" && ! -f "$base/$name/.tahoe-overlay" ]]; then
      printf '%s' "$base/$name"
      return 0
    fi
  done
  return 1
}

# ── main ──────────────────────────────────────────────────────────────────────

theme_name="$(active_theme)" || {
  msg "Cannot detect active icon theme"
  exit 1
}

sys="$(find_system_source "$theme_name")" || {
  msg "System source for '$theme_name' not found"
  exit 1
}

usr="$HOME/.local/share/icons/$theme_name"

# First run: symlink everything from system, then replace places with real copies
if [[ ! -f "$usr/index.theme" ]]; then
  mkdir -p "$usr"
  for d in "$sys"/*/; do
    dname="${d%/}"
    dname="${dname##*/}"
    ln -sfn "$d" "$usr/$dname"
  done
  for f in "$sys"/*.*; do
    fname="${f##*/}"
    [[ "$fname" == "icon-theme.cache" || "$fname" == "AUTHORS" || "$fname" == "COPYING" ]] && continue
    ln -sfn "$f" "$usr/$fname"
  done
  # Replace symlinked places with real copies for recoloring
  rm -f "$usr/places" "$usr/places@2x"
  cp -rf --no-dereference "$sys/places" "$usr/" 2>/dev/null || true
  [[ -d "$sys/places@2x" ]] && cp -rf --no-dereference "$sys/places@2x" "$usr/" 2>/dev/null || true
fi

# Save pristine originals on first run, restore before each recolor
orig="$usr/.tahoe-orig"
if [[ ! -d "$orig/places" ]]; then
  mkdir -p "$orig"
  cp -rf --no-dereference "$sys/places" "$orig/" 2>/dev/null || true
  [[ -d "$sys/places@2x" ]] && cp -rf --no-dereference "$sys/places@2x" "$orig/" 2>/dev/null || true
fi
# Restore fresh originals before recoloring
cp -rf --no-dereference "$orig/places" "$usr/" 2>/dev/null || true
[[ -d "$orig/places@2x" ]] && cp -rf --no-dereference "$orig/places@2x" "$usr/" 2>/dev/null || true

src_hex="${PALETTE[$closest]}"
[[ -n "$src_hex" ]] || exit 0

tgt_hex="${PALETTE[$closest]}"  # same palette color, but we replace with TARGET
# Actually: we replace src_hex (the palette color closest to target)
# with the target color itself. But the target may not be a palette color.
# So we just replace the palette hex with the target hex directly.

# Compute target color variants for gradient replacement
tgt_variants="$(color_variants "$TARGET")"
tgt_dark="#$(sed -n '1p' <<<"$tgt_variants")"
tgt_main="#${TARGET}"
tgt_med="#$(sed -n '3p' <<<"$tgt_variants")"
tgt_light="#$(sed -n '4p' <<<"$tgt_variants")"

# Build sed args: replace each blue shade with corresponding target variant
sed_args=()
for h in 008ea2 56a1d3; do
  sed_args+=(-e "s/#${h}/${tgt_dark}/gi")
done
for h in 006efd 46a2d7 67b1de; do
  sed_args+=(-e "s/#${h}/${tgt_main}/gi")
done
for h in 60c0f0 7cc1ea; do
  sed_args+=(-e "s/#${h}/${tgt_med}/gi")
done
for h in 83d4fb 88ccf2; do
  sed_args+=(-e "s/#${h}/${tgt_light}/gi")
done

# Also replace the palette source color with target (for non-blue palettes)
if [[ "$closest" != "blue" ]]; then
  src_variants="$(color_variants "$src_hex")"
  src_dark="#$(sed -n '1p' <<<"$src_variants")"
  src_main="#${src_hex}"
  src_med="#$(sed -n '3p' <<<"$src_variants")"
  src_light="#$(sed -n '4p' <<<"$src_variants")"

  for h in $(grep -roh "#[0-9a-fA-F]\{6\}" "$usr/places/scalable/"*.svg 2>/dev/null | tr -d '#' | sort -u); do
    upper="${h^^}"
    for pv in "${src_dark}" "${src_main}" "${src_med}" "${src_light}"; do
      if [[ "${upper}" == "${pv^^}" ]]; then
        if [[ "${upper}" == "${src_dark^^}" ]]; then
          sed_args+=(-e "s/#${h}/${tgt_dark}/gi")
        elif [[ "${upper}" == "${src_main^^}" ]]; then
          sed_args+=(-e "s/#${h}/${tgt_main}/gi")
        elif [[ "${upper}" == "${src_med^^}" ]]; then
          sed_args+=(-e "s/#${h}/${tgt_med}/gi")
        elif [[ "${upper}" == "${src_light^^}" ]]; then
          sed_args+=(-e "s/#${h}/${tgt_light}/gi")
        fi
        break
      fi
    done
  done
fi

# Recolor folder SVGs — scalable + all fixed sizes
for dir in "$usr"/places/{scalable,16,22,24,32} "$usr"/places@2x/{scalable,16,22,24,32}; do
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*.svg; do
    [[ -f "$f" ]] || continue
    [[ -L "$f" ]] && continue
    # Skip if no replaceable colors
    grep -qi '#006efd\|#56a1d3\|#67b1de\|#7cc1ea\|#88ccf2\|#46a2d7\|#008ea2\|#60c0f0\|#83d4fb\|#dedede\|#363636\|#51546e' "$f" 2>/dev/null && {
      sed -i "${sed_args[@]}" "$f"
      # Monochrome/symbolic icons: CSS color or fill grey → target-tinted grey
      if grep -qi '#dedede\|#363636\|#51546e' "$f" 2>/dev/null; then
        mono_hex=$(printf '%02x%02x%02x' $(($(printf '%d' "0x${TARGET:0:2}")*38/100+40)) $(($(printf '%d' "0x${TARGET:2:2}")*38/100+40)) $(($(printf '%d' "0x${TARGET:4:2}")*38/100+40)))
        sed -i -e "s/#dedede/#${mono_hex}/gi" -e "s/#363636/#${mono_hex}/gi" -e "s/#51546e/#${mono_hex}/gi" "$f"
      fi
      continue
    }
    # For non-blue palettes: check if source palette color is present
    if [[ "$closest" != "blue" ]]; then
      grep -qi "#${src_hex}" "$f" 2>/dev/null && sed -i "${sed_args[@]}" "$f"
    fi
  done
done

gtk-update-icon-cache --force --quiet "$usr" 2>/dev/null || true
