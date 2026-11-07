# Renders the stream-json log of one agent stage for the Herdr viewer tab
# (#389). Read-only: the loop itself never depends on this output.
#
#   tail -n +1 -F <stage>.jsonl | jq -rR --unbuffered -f viewer.jq \
#     [--arg status 1 --arg title <stage>]
#
# With `status`, every line that changes the stage's state is prefixed with
# an OSC 7501 report, the way Claude Code reports itself to herdr-core:
# `state=…:app=claude-code[:title=…][:msg=…]`, title and msg in base64. The
# tab then counts as a working agent in Herdr. Without it (replaying a log
# in a terminal) nothing but text is printed.

def dim: "\u001b[2m\(.)\u001b[0m";
def cyan: "\u001b[36m\(.)\u001b[0m";
def red: "\u001b[31m\(.)\u001b[0m";
def bold: "\u001b[1m\(.)\u001b[0m";

def short($n): tostring | gsub("\\s+"; " ") | if length > $n then .[0:$n] + "…" else . end;

def report($state; $msg):
  if $ARGS.named.status then
    "\u001b]7501;state=\($state):app=claude-code"
    + (if ($ARGS.named.title // "") != "" then ":title=\($ARGS.named.title | @base64)" else "" end)
    + (if $msg != "" then ":msg=\($msg | short(80) | @base64)" else "" end)
    + "\u001b\\"
  else "" end;

def tool_arg:
  .command // .file_path // .pattern // .skill // .description // .url // .query
  // (tojson);

def tool_text:
  if type == "string" then .
  elif type == "array" then map(.text? // "") | join(" ")
  else tostring end;

fromjson? |
if .type == "system" and .subtype == "init" then
  report("working"; "startet") + ("▶ \(.model) · \(.cwd)" | bold)
elif .type == "assistant" then
  .message.content[]? |
  if .type == "text" then "\n" + .text
  elif .type == "tool_use" then
    (.input | tool_arg) as $arg |
    report("working"; "\(.name) \($arg)") + ("→ \(.name) " + ($arg | short(160)) | cyan)
  elif .type == "thinking" then "· denkt" | dim
  else empty end
elif .type == "user" and (.message.content | type) == "array" then
  .message.content[]? | select(.type == "tool_result") |
  if .is_error then "  ✗ " + (.content | tool_text | short(200)) | red
  else "  ✓ " + (.content | tool_text | short(120)) | dim end
elif .type == "result" then
  (if .is_error then "Fehler" else "fertig" end) as $end |
  (report(if .is_error then "error" else "done" end; $end)
   + ("\n■ \($end) · \(.num_turns) Turns · \((.duration_ms // 0) / 1000 | floor) s" | bold)),
  (.permission_denials[]? | "  abgelehnt: " + (.tool_input | tool_arg | short(160)) | red)
else empty end
