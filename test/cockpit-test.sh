#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

export MAESTRI_DATA_DIR="$T/maestri"
export XDG_STATE_HOME="$T/state"
export COCKPIT_CLAUDE_DIRS="$T/claude-a:$T/claude-b"
unset CLAUDE_CONFIG_DIR
STATE="$XDG_STATE_HOME/jonatas-workflow/cockpit"
NOW=$(date +%s)

failed=0
check() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: expected '$3', got '$2'"; failed=1; fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then echo "ok    $1"; else echo "FAIL  $1: '$3' not in:"; printf '%s\n' "$2"; failed=1; fi; }
hasnt() { if printf '%s' "$2" | grep -q -- "$3"; then echo "FAIL  $1: '$3' found in:"; printf '%s\n' "$2"; failed=1; else echo "ok    $1"; fi; }
row() { printf '%s\n' "$1" | grep -- "$2" | head -1; }

reset() {
  rm -rf "$T/maestri" "$T/state" "$T/claude-a" "$T/claude-b"
  mkdir -p "$T/maestri/workspaces" "$T/maestri/usage/providers" "$T/claude-a/sessions" "$T/claude-b/sessions" "$STATE"
  cat > "$T/maestri/preferences.json" <<'EOF'
{"payload":{"rolePresets":[
  {"id":"AAAA-EXEC","name":"Executor"},
  {"id":"BBBB-ORCH","name":"Orquestrador"}]}}
EOF
  echo '{"providers":[]}' > "$T/maestri/usage/providers/.status.json"
}

terminal() {
  jq -n --arg name "$1" --arg type "$2" --arg status "$3" --arg cmd "$4" --arg role "$5" --arg wd "$6" \
    '{content:{terminal:{_0:{name:$name,agentType:$type,status:$status,command:$cmd,assignedRoleId:$role,workingDirectory:$wd,apiKey:"SECRET-APIKEY",token:"SECRET-TOKEN"}}}}'
}

workspace() {
  local id="$1" name="$2"; shift 2
  mkdir -p "$T/maestri/workspaces/$id/notes"
  printf '%s\n' "$@" | jq -s --arg n "$name" '{payload:{name:$n,nodes:.}}' > "$T/maestri/workspaces/$id/workspace.json"
}

note() { printf '%s\n' "${@:3}" > "$T/maestri/workspaces/$1/notes/$2.md"; }

roledir() { echo "$1/.maestri/roles/$(printf '%s' "$2" | tr 'A-Z' 'a-z')"; }

session() {
  local cfg="$1" sid="$2" cwd="$3" status="$4" since="$5"
  jq -n --arg sid "$sid" --arg cwd "$cwd" --arg st "$status" --argjson since "$since" \
    '{sessionId:$sid,cwd:$cwd,status:$st,statusUpdatedAt:$since}' > "$cfg/sessions/$sid.json"
}

transcript() {
  local cfg="$1" cwd="$2" sid="$3"
  local dir="$cfg/projects/$(printf '%s' "$cwd" | tr '/.' '--')"
  mkdir -p "$dir"
  cat > "$dir/$sid.jsonl"
}

usage_line() {
  jq -nc --argjson i "$1" --argjson c "$2" --argjson r "$3" \
    '{type:"assistant",message:{usage:{input_tokens:$i,cache_creation_input_tokens:$c,cache_read_input_tokens:$r},content:[{type:"text",text:"ok"}]}}'
}

state_file() {
  jq -n --argjson at "$2" --argjson w "$3" '{five_hour:{used_percentage:12,resets_at:0},seven_day:{used_percentage:40,resets_at:0},context_window_size:$w,updated_at:$at}' > "$STATE/$1.json"
}

run() { bash "$ROOT/bin/cockpit" --once 2>&1; }

EXEC_DIR=$T/code/proj-a-1
reset
workspace w1 "ProjA" \
  "$(terminal Aracati claude_code running 'claude --model sonnet --effort low' AAAA-EXEC "$T/code/proj-a-1")" \
  "$(terminal Orq claude_code running 'claude --model opus --effort high' BBBB-ORCH "$T/code/proj-a")" \
  "$(terminal Parado claude_code stopped 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-2")"
workspace w2 "ProjB" \
  "$(terminal Cdx codex running 'codex --no-daemon' '' "$T/code/proj-b")"
out=$(run)
check "1 exit code" "$?" "0"
has "1 row Aracati: project, role, model" "$(row "$out" Aracati)" 'ProjA.*Aracati.*Executor.*sonnet'
has "1 row Orq: project, role, model" "$(row "$out" Orq)" 'ProjA.*Orq.*Orquestrador.*opus'
has "1 row Cdx in the other workspace" "$(row "$out" Cdx)" 'ProjB.*Cdx'
hasnt "2 stopped terminal prints no row" "$out" Parado

reset
CWD=$(roledir "$T/code/proj-a-1" AAAA-EXEC)
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")" \
  "$(terminal Alicerce claude_code running 'claude --model opus' AAAA-EXEC "$T/code/proj-a-2")"
note w1 board "# board" "testes · https://x" "Aracati · #184 · implementing · sonnet · 3" "Alicerce · #172 · reviewing · opus"
out=$(run)
check "3 ticket, state, points" "$(row "$out" Aracati | awk '{print $5, $6, $7}')" "#184 implementing 3"
check "4 four-field board line: ticket and state, ? points" "$(row "$out" Alicerce | awk '{print $5, $6, $7}')" "#172 reviewing ?"
check "4 the row keeps all columns" "$(row "$out" Alicerce | awk '{print NF}')" "10"

reset
CWD=$(roledir "$T/code/proj-a-1" AAAA-EXEC)
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
note w1 board "# board" "Aracati · #184 · implementing · sonnet · 3"
session "$T/claude-a" s1 "$CWD" busy $(( (NOW - 7200) * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
EOF
state_file claude-a "$NOW" 200000
out=$(run)
has "5 time in state" "$(row "$out" Aracati)" '2h'
has "5 context percentage from the transcript" "$(row "$out" Aracati)" '50%'

transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}
EOF
out=$(run)
has "6 pending AskUserQuestion shows *" "$(row "$out" Aracati)" '\*'

transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q1","content":"A"}]}}
$(usage_line 2 1000 99000)
EOF
out=$(run)
hasnt "7 idle session, no pending question, no *" "$(row "$out" Aracati)" '\*'

transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q9","name":"AskUserQuestion","input":{}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q9","content":"A"}]}}
$(usage_line 2 1000 99000)
EOF
out=$(run)
hasnt "7b answered question of a finished turn does not light *" "$(row "$out" Aracati)" '\*'

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
note w1 "for you" "# for you" "- [ ] one" "- [ ] two" "- [x] done" "- [ ] three"
out=$(run)
has "8 for you count of open lines" "$(row "$out" Aracati)" '3'

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
payload='{"rate_limits":{"five_hour":{"used_percentage":12.4,"resets_at":1},"seven_day":{"used_percentage":40,"resets_at":2}},"context_window":{"context_window_size":200000}}'
printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" > "$T/sl.out" 2>"$T/sl.err"
check "9 statusline state file written" "$(test -f "$STATE/claude-a.json" && echo yes)" "yes"
check "9 statusline prints one line" "$(wc -l < "$T/sl.out")" "1"
out=$(run)
has "9 header shows both percentages with the age" "$out" '12%.*(0s).*40%.*(0s)'
check "9 no temp file left behind" "$(ls "$STATE" | grep -c tmp)" "0"

printf '%s' '{"model":{"display_name":"x"}}' | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" > "$T/sl.out" 2>"$T/sl.err"
check "10 no rate_limits: exit code" "$?" "0"
check "10 no rate_limits: no error output" "$(cat "$T/sl.err")" ""
out=$(run)
has "10 last reading is kept" "$out" '12%'
check "10 context window size is kept" "$(jq .context_window_size "$STATE/claude-a.json")" "200000"
printf 'not json' | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" >/dev/null 2>"$T/sl.err"
check "10 garbage payload: no error output" "$(cat "$T/sl.err")" ""

reset
cat > "$T/maestri/usage/providers/.status.json" <<EOF
{"providers":[
 {"id":"claude","meters":[{"windows":[{"ring":"session","usedPercent":0},{"ring":"weekly","usedPercent":0}]}]},
 {"id":"codex","lastSuccessAt":"$(date -u -d "@$((NOW - 120))" +%Y-%m-%dT%H:%M:%SZ)","meters":[{"windows":[{"ring":"session","usedPercent":7},{"ring":"weekly","usedPercent":23}]}]}]}
EOF
out=$(run)
has "11 codex limits come from the Maestri file" "$out" 'codex.*7%.*23%'
hasnt "11 claude 0% in the Maestri file does not reach the header" "$out" 'claude.*0%'

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
mkdir -p "$T/maestri/workspaces/bad"; echo '{broken' > "$T/maestri/workspaces/bad/workspace.json"
out=$(run)
check "12 exit code with a malformed workspace" "$?" "0"
has "12 healthy workspace still prints" "$out" 'ProjA.*Aracati'
has "12 malformed workspace shows ?" "$(row "$out" '^?')" '?'

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
rm -rf "$T/maestri/usage" "$T/maestri/preferences.json"
out=$(run); code=$?
check "13 nothing missing: exit code" "$code" "0"
has "13 missing notes, session, transcript, state: ?" "$(row "$out" Aracati)" '?'
has "13 missing preferences: role ?" "$(row "$out" Aracati)" 'ProjA *Aracati *?'
rm -rf "$T/maestri"
out=$(run); check "13 no Maestri dir at all: exit code" "$?" "0"

reset
CWD=$(roledir "$T/code/proj-a-1" AAAA-EXEC)
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"content":[{"type":"text","text":"x"}],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"token":"SECRET-TOKEN"}
EOF
printf '%s' '{"apiKey":"SECRET-APIKEY","token":"SECRET-TOKEN","credentials":{"password":"SECRET-PASS"},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1},"seven_day":{"used_percentage":6,"resets_at":2}},"context_window":{"context_window_size":1000}}' \
  | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" > "$T/sl.out"
out=$(run)
all="$out$(cat "$T/sl.out" "$STATE"/*.json)"
hasnt "14 no secret value in output or state file" "$all" 'SECRET'

sum() { find "$T/maestri" "$T/claude-a" "$T/claude-b" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum; }
before=$(sum); run >/dev/null; after=$(sum)
check "15 data directories unchanged after a run" "$after" "$before"

H="$T/home"; mkdir -p "$H"
CLAUDE_HOME="$H" bash "$ROOT/bin/cockpit-install" >/dev/null 2>&1
check "16 missing settings.json is created" "$(jq -r '.statusLine.command' "$H/settings.json")" "$ROOT/bin/cockpit-statusline"
echo '{"model":"opus","statusLine":{"type":"command","command":"/bin/other"}}' > "$H/settings.json"
CLAUDE_HOME="$H" bash "$ROOT/bin/cockpit-install" >/dev/null 2>&1
check "16 a different statusLine is left untouched" "$(jq -r '.statusLine.command' "$H/settings.json")" "/bin/other"
echo '{"model":"opus"}' > "$H/settings.json"
CLAUDE_HOME="$H" bash "$ROOT/bin/cockpit-install" >/dev/null 2>&1
CLAUDE_HOME="$H" bash "$ROOT/bin/cockpit-install" >/dev/null 2>&1
check "16 run twice: one statusLine, other settings kept" "$(jq -c '[.model, (.statusLine|type), (keys|length)]' "$H/settings.json")" '["opus","object",2]'

exit $failed
