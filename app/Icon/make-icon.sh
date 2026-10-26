#!/bin/bash
# Renders Icon/AppIcon.svg into the app's AppIcon asset catalog. Run after editing the SVG:
#   app/Icon/make-icon.sh
# Uses sips (built into macOS), which renders SVG gradients correctly.
set -euo pipefail

icon_dir="$(cd "$(dirname "$0")" && pwd)"
svg="$icon_dir/AppIcon.svg"
out="$icon_dir/../BrewUpdates/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$out"

# macOS needs each size at 1x and 2x: 16, 32, 128, 256 and 512 points
for size in 16 32 64 128 256 512 1024; do
    sips -s format png -Z "$size" "$svg" --out "$out/icon_${size}.png" >/dev/null
done

cat > "$out/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

cat > "$out/../Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "Wrote $out"
