#!/usr/bin/env bash
# Quick smoke test for the MiniMax-H3 video streaming server
# Tests: health, models, completion, streaming
#
# Usage:
#   bash test.sh                          # test default (port 8188)
#   bash test.sh http://localhost:8188    # test specific instance
BASE="${1:-http://localhost:8188}"
PASS=0
FAIL=0

log() {
  printf "[%s] %-30s %s\n" "$1" "$2" "$3"
  if [ "$1" = "PASS" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
}

echo "=== MiniMax-H3 Server Test ==="
echo "Target: $BASE"
echo ""

# 1. Health
HEALTH=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE/health" 2>/dev/null)
if [ "$HEALTH" = "200" ]; then log "PASS" "Health" "OK"; else log "FAIL" "Health" "HTTP $HEALTH"; fi

# 2. List models
MODELS=$(curl -sf "$BASE/v1/models" 2>/dev/null)
if echo "$MODELS" | grep -qi "MiniMax"; then log "PASS" "Models" "MiniMax-H3 listed"; else log "FAIL" "Models" "Not found"; fi

# 3. Chat completion
CHAT=$(curl -sf "$BASE/v1/chat/completions" -X POST -H "Content-Type: application/json" \
  -d '{"model":"MiniMax-H3","messages":[{"role":"user","content":"What is 2+2? Answer with just the number."}],"max_tokens":5,"temperature":0}' 2>/dev/null)
CHAT_TEXT=$(echo "$CHAT" | python3 -c "import sys,json;print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "")
if [ -n "$CHAT_TEXT" ] && ! echo "$CHAT_TEXT" | grep -qi "error"; then
  log "PASS" "Chat" "'$CHAT_TEXT'"
else
  log "FAIL" "Chat" "$(echo "$CHAT" | head -c 80)"
fi

# 4. Streaming
STREAM_CHUNKS=$(curl -sf -N "$BASE/v1/chat/completions" -X POST -H "Content-Type: application/json" \
  -d '{"model":"MiniMax-H3","messages":[{"role":"user","content":"Count to 3:"}],"max_tokens":10,"stream":true}' 2>/dev/null \
  | grep -c "^data:" || echo "0")
if [ "$STREAM_CHUNKS" -gt 0 ]; then
  log "PASS" "Streaming" "$STREAM_CHUNKS chunks"
else
  log "FAIL" "Streaming" "No SSE data"
fi

# Summary
echo ""
TOTAL=$((PASS + FAIL))
echo "Result: $PASS/$TOTAL passed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
