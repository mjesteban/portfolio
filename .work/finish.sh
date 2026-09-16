#!/bin/bash
# Encode legs -> assets/vid, posters, SSIM seam check (architecture A).
# Each leg is cut so it ENDS on the exact frame that was used as the next leg's
# start image (leg0: -0.05s, leg1/2: -0.15s), removing the motion offset at seams.
cd "$(dirname "$0")"
NAMES="intro craft work contact"
CUTS="4.45 7.89 7.89 0"     # 0 = no cut (last leg)

# crf 23 / g 12 measured at VMAF 97.8 vs a crf-14 reference, 34% smaller than crf 20 / g 8.
# g 12 = keyframe every 0.5s: scrub seeks decode at most 11 frames to land a frame.
enc() { # src dst [duration] [mobile_width]
  if [ "$3" != "0" ]; then dur=(-t "$3"); else dur=(); fi
  if [ -n "$4" ]; then vf="scale=$4:-2:flags=lanczos,unsharp=5:5:0.6:5:5:0.0"; crf=24
  else vf="unsharp=5:5:0.8:5:5:0.0"; crf=23; fi
  ffmpeg -v error -y -i "$1" "${dur[@]}" -an -vf "$vf" \
    -c:v libx264 -preset slow -crf $crf -pix_fmt yuv420p \
    -g 12 -keyint_min 12 -sc_threshold 0 -movflags +faststart "$2"
  echo "enc $2 $(du -h "$2" | cut -f1) dur=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$2")"
}

i=0
for n in $NAMES; do
  cut=$(echo $CUTS | cut -d' ' -f$((i+1)))
  [ -s "leg_$i.mp4" ] && enc "leg_$i.mp4" "../assets/vid/$n.mp4" "$cut"
  # Phone tier (engine picks it via clipMobile when min(screen) <= 600). Same framing,
  # so posterMobile stays unwired and the desktop poster webp scales down for both.
  [ -s "leg_$i.mp4" ] && enc "leg_$i.mp4" "../assets/vid/$n-m.mp4" "$cut" 960
  i=$((i+1))
done

for n in $NAMES; do
  [ -s "../assets/vid/$n.mp4" ] || continue
  ffmpeg -v error -y -ss 0 -i "../assets/vid/$n.mp4" -frames:v 1 -q:v 2 "poster_$n.png"
  cwebp -quiet -q 84 "poster_$n.png" -o "../assets/$n-poster.webp" && echo "poster $n"
done

seam() { # fileA fileB -> ssim between A's true last frame and B's first frame
  rm -f _sa.png _sb.png
  nf=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "$1")
  ffmpeg -v error -y -i "$1" -vf "select=eq(n\,$((nf-1)))" -frames:v 1 -update 1 _sa.png
  ffmpeg -v error -y -ss 0 -i "$2" -frames:v 1 _sb.png
  [ -s _sa.png ] && [ -s _sb.png ] || { echo "extract-failed"; return; }
  ffmpeg -v info -i _sa.png -i _sb.png -lavfi ssim -f null - 2>&1 | grep -o 'All:[0-9.]*' | cut -d: -f2
}
prev=""
for n in $NAMES; do
  if [ -n "$prev" ] && [ -s "../assets/vid/$prev.mp4" ] && [ -s "../assets/vid/$n.mp4" ]; then
    s=$(seam "../assets/vid/$prev.mp4" "../assets/vid/$n.mp4")
    v=$(awk -v s="${s:-0}" 'BEGIN{ print (s>=0.90) ? "PASS" : (s>=0.75) ? "WARN" : "FAIL" }')
    echo "$v  $prev>$n  ssim=$s"
  fi
  prev=$n
done
