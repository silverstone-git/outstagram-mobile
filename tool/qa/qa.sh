#!/bin/sh
# On-device QA helpers (Git Bash on Windows). See docs/qa.md for the loop and the rules.
#
#   tool/qa/qa.sh shot NAME        screenshot -> $QA_OUT/NAME.png, downscaled 2x (tap coords = image coords x 2)
#   tool/qa/qa.sh tap X Y          tap in *screenshot* coordinates (doubled for the 1080x2340 screen)
#   tool/qa/qa.sh text "a b c"     type text (spaces escaped for adb)
#   tool/qa/qa.sh launch [staging] start the prod (or staging) app
#   tool/qa/qa.sh testimage        push a generated image to the phone gallery (never upload the user's photos)
#   tool/qa/qa.sh alarms           the app's scheduled reminders (exact fire windows)
#   tool/qa/qa.sh errors [svc]     prod (or outsie-staging) 5xx and tracebacks in the last hour
set -e
ADB="${ADB:-$HOME/dev/platform-tools/adb.exe}"
QA_OUT="${QA_OUT:-${TMPDIR:-/tmp}/outstagram-qa}"
mkdir -p "$QA_OUT"
pkg() { [ "$1" = staging ] && echo com.cyto.outstagram.staging || echo com.cyto.outstagram; }

case "$1" in
  shot)
    "$ADB" exec-out screencap -p > "$QA_OUT/$2.png"
    python -c "from PIL import Image; im=Image.open(r'$QA_OUT/$2.png'); im.thumbnail((540,1200)); im.save(r'$QA_OUT/$2.png')"
    echo "$QA_OUT/$2.png" ;;
  tap) "$ADB" shell input tap $(( $2 * 2 )) $(( $3 * 2 )) ;;
  text) "$ADB" shell input text "$(printf '%s' "$2" | sed 's/ /%s/g')" ;;
  launch) "$ADB" shell monkey -p "$(pkg "$2")" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 ;;
  testimage)
    python - "$QA_OUT/qa_test.jpg" <<'EOF'
import sys
from PIL import Image, ImageDraw
im = Image.new("RGB", (1200, 900), (16, 16, 32)); d = ImageDraw.Draw(im)
for i in range(0, 900, 6): d.line([(0, i), (1200, i)], fill=(255, max(0, 140 - i // 8), min(255, i // 4)))
d.ellipse([350, 200, 850, 700], fill=(57, 245, 107)); im.save(sys.argv[1], quality=90)
EOF
    MSYS_NO_PATHCONV=1 "$ADB" push "$QA_OUT/qa_test.jpg" /sdcard/Pictures/outstagram_qa_test.jpg >/dev/null
    MSYS_NO_PATHCONV=1 "$ADB" shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d file:///sdcard/Pictures/outstagram_qa_test.jpg >/dev/null
    echo "pushed /sdcard/Pictures/outstagram_qa_test.jpg (delete it after QA)" ;;
  alarms) "$ADB" shell dumpsys alarm | grep -A2 "com.cyto.outstagram" | grep -E "origWhen=|window=" ;;
  errors)
    svc="${2:-outsie}"
    gcloud logging read "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$svc\" AND (httpRequest.status>=500 OR severity>=ERROR)" \
      --limit=300 --freshness=1h --format="value(httpRequest.status,httpRequest.requestUrl,textPayload)" 2>/dev/null \
      | grep -E "^5|Error|/app/" | grep -v site-packages | sort | uniq -c | sort -rn | head -20
    # counts span the whole hour, including errors from before a fix: compare with the latest one
    echo "latest 5xx: $(gcloud logging read "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$svc\" AND httpRequest.status>=500"       --limit=1 --freshness=1h --format="value(timestamp,httpRequest.requestUrl)" 2>/dev/null)" ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
