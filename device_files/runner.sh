#!/system/bin/sh
BASE=/sdcard/retroidRootRunner
mkdir -p "$BASE"
echo $$ > "$BASE/runner.pid"
echo "runner started $(date) pid $$" >> "$BASE/output.log"
rm -f "$BASE/stop" "$BASE/cmd" "$BASE/cmd.run"
while true; do
  if [ -f "$BASE/stop" ]; then echo "stop seen $(date)" >> "$BASE/output.log"; rm -f "$BASE/stop"; break; fi
  if [ -f "$BASE/cmd" ]; then
    mv "$BASE/cmd" "$BASE/cmd.run"
    echo "=== $(date) ===" >> "$BASE/output.log"
    cat "$BASE/cmd.run" >> "$BASE/output.log"
    echo "--- output ---" >> "$BASE/output.log"
    sh "$BASE/cmd.run" >> "$BASE/output.log" 2>&1
    echo "=== exit $? ===" >> "$BASE/output.log"
    rm -f "$BASE/cmd.run"
  fi
  sleep 1
done
rm -f "$BASE/runner.pid"
echo "loop exited $(date)" >> "$BASE/output.log"
