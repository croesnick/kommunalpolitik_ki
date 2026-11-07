# Renders the stream-json log of one agent stage for the herdr viewer pane
# (#389). Read-only: the loop itself never depends on this output.
#
#   tail -n +1 -F <stage>.jsonl | jq -rR --unbuffered -f viewer.jq

def dim: "\u001b[2m\(.)\u001b[0m";
def cyan: "\u001b[36m\(.)\u001b[0m";
def red: "\u001b[31m\(.)\u001b[0m";
def bold: "\u001b[1m\(.)\u001b[0m";

def short($n): tostring | gsub("\\s+"; " ") | if length > $n then .[0:$n] + "…" else . end;

def tool_arg:
  .command // .file_path // .pattern // .skill // .description // .url // .query
  // (tojson);

def tool_text:
  if type == "string" then .
  elif type == "array" then map(.text? // "") | join(" ")
  else tostring end;

fromjson? |
if .type == "system" and .subtype == "init" then
  "▶ \(.model) · \(.cwd)" | bold
elif .type == "assistant" then
  .message.content[]? |
  if .type == "text" then "\n" + .text
  elif .type == "tool_use" then "→ \(.name) " + (.input | tool_arg | short(160)) | cyan
  elif .type == "thinking" then "· denkt" | dim
  else empty end
elif .type == "user" and (.message.content | type) == "array" then
  .message.content[]? | select(.type == "tool_result") |
  if .is_error then "  ✗ " + (.content | tool_text | short(200)) | red
  else "  ✓ " + (.content | tool_text | short(120)) | dim end
elif .type == "result" then
  ("\n■ \(if .is_error then "Fehler" else "fertig" end) · \(.num_turns) Turns · \((.duration_ms // 0) / 1000 | floor) s" | bold),
  (.permission_denials[]? | "  abgelehnt: " + (.tool_input | tool_arg | short(160)) | red)
else empty end
