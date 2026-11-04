#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

export MAESTRI_DATA_DIR="$T/maestri"
export XDG_STATE_HOME="$T/state"
export COCKPIT_CLAUDE_DIRS="$T/claude-a:$T/claude-b"
unset CLAUDE_CONFIG_DIR
unset COLUMNS
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
  printf '%s\n' "$@" | jq -s --arg n "$name" --arg d "${WS_DIR:-}" '{payload:{name:$n,workingDirectory:$d,nodes:.}}' > "$T/maestri/workspaces/$id/workspace.json"
}

note() { printf '%s\n' "${@:3}" > "$T/maestri/workspaces/$1/notes/$2.md"; }

roledir() { echo "$1/.maestri/roles/$(printf '%s' "$2" | tr 'A-Z' 'a-z')"; }

session() {
  local cfg="$1" sid="$2" cwd="$3" status="$4" since="$5" pid="${6:-$$}"
  jq -n --arg sid "$sid" --arg cwd "$cwd" --arg st "$status" --argjson since "$since" --argjson pid "$pid" \
    '{pid:$pid,sessionId:$sid,cwd:$cwd,status:$st,statusUpdatedAt:$since}' > "$cfg/sessions/$sid.json"
}

transcript() {
  local cfg="$1" cwd="$2" sid="$3"
  local dir="$cfg/projects/$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$dir"
  cat > "$dir/$sid.jsonl"
}

usage_line() {
  jq -nc --argjson i "$1" --argjson c "$2" --argjson r "$3" \
    '{type:"assistant",message:{model:"m1",usage:{input_tokens:$i,cache_creation_input_tokens:$c,cache_read_input_tokens:$r},content:[{type:"text",text:"ok"}]}}'
}

state_file() {
  jq -n --argjson at "$2" --argjson w "$3" '{five_hour:{used_percentage:12,resets_at:0},seven_day:{used_percentage:40,resets_at:0},context_window_sizes:{m1:$w,m2:1000000},updated_at:$at}' > "$STATE/$1.json"
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
has "1 row Aracati with its model" "$(row "$out" Aracati)" 'Aracati.*sonnet'
has "1 row Orq with its model and role" "$(row "$out" Orq)" 'Orq.*opus.*Orquestrador'
check "7n each project prints one heading" "$(printf '%s\n' "$out" | grep -c -E '^  Proj[AB] ─')" "2"
check "7n a project's agents follow its heading" "$(printf '%s\n' "$out" | grep -E 'ProjB|Cdx' | head -2 | grep -c .)" "2"
hasnt "2 stopped terminal prints no row" "$out" Parado

reset
CWD=$(roledir "$T/code/proj-a-1" AAAA-EXEC)
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")" \
  "$(terminal Alicerce claude_code running 'claude --model opus' AAAA-EXEC "$T/code/proj-a-2")"
note w1 board "# board" "testes · https://x" "Aracati · #184 · implementing · sonnet · 3" "Alicerce · #172 · reviewing · opus"
out=$(run)
has "3 ticket, state, points" "$(row "$out" Aracati)" '#184 *implementando *3'
has "4 four-field board line: ticket and state, ? points" "$(row "$out" Alicerce)" '#172 *revisando *?'

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
has "6 pending AskUserQuestion shows !" "$(row "$out" Aracati)" '^  !'

transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q1","content":"A"}]}}
$(usage_line 2 1000 99000)
EOF
out=$(run)
hasnt "7 idle session, no pending question, no !" "$(row "$out" Aracati)" '!'

transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q9","name":"AskUserQuestion","input":{}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q9","content":"A"}]}}
$(usage_line 2 1000 99000)
EOF
out=$(run)
hasnt "7b answered question of a finished turn does not light !" "$(row "$out" Aracati)" '!'

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
note w1 "for you" "# for you" "- [ ] one" "- [ ] two" "- [x] done" "- [ ] three"
out=$(run)
has "8 for you count of open lines on the project heading" "$(row "$out" 'ProjA ─')" '3 em for you'

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
payload='{"rate_limits":{"five_hour":{"used_percentage":12.4,"resets_at":1},"seven_day":{"used_percentage":40,"resets_at":2}},"model":{"id":"m1"},"context_window":{"context_window_size":200000}}'
printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" > "$T/sl.out" 2>"$T/sl.err"
check "9 statusline state file written" "$(test -f "$STATE/claude-a.json" && echo yes)" "yes"
check "9 statusline prints one line" "$(wc -l < "$T/sl.out")" "1"
out=$(run)
has "9 header shows both percentages with the age" "$out" '12%.* [0-9]*s .*40%'
check "9 no temp file left behind" "$(ls "$STATE" | grep -c tmp)" "0"

printf '%s' '{"model":{"display_name":"x"}}' | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" > "$T/sl.out" 2>"$T/sl.err"
check "10 no rate_limits: exit code" "$?" "0"
check "10 no rate_limits: no error output" "$(cat "$T/sl.err")" ""
out=$(run)
has "10 last reading is kept" "$out" '12%'
check "10 context window size is kept" "$(jq .context_window_sizes.m1 "$STATE/claude-a.json")" "200000"
printf 'not json' | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" >/dev/null 2>"$T/sl.err"
check "10 garbage payload: no error output" "$(cat "$T/sl.err")" ""

printf '%s' '{"model":{"id":"m2"},"context_window":{"context_window_size":1000000}}' | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" >/dev/null
check "17 two models of one account keep their own window sizes" "$(jq -c '[.context_window_sizes.m1, .context_window_sizes.m2]' "$STATE/claude-a.json")" "[200000,1000000]"

rm -f "$STATE"/*.json
printf '%s' '{"rate_limits":{"seven_day":{"used_percentage":77,"resets_at":2}}}' | CLAUDE_CONFIG_DIR="$T/.claude-hidden" bash "$ROOT/bin/cockpit-statusline" >/dev/null
out=$(run)
has "18 a dot-named account shows in the header" "$out" 'claude-hidden'
has "18 only seven_day: the value stays under 7d" "$out" '5h [░ ]*?.*7d .*77%'

reset
CWD="$T/code/Caso Clinico/proj-1/.maestri/roles/aaaa-exec"
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/Caso Clinico/proj-1")"
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
EOF
state_file claude-a "$NOW" 200000
out=$(run)
has "19 a working directory with a space still finds the transcript" "$(row "$out" Aracati)" '50%'

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running '' AAAA-EXEC "$T/code/proj-a-1")"
out=$(run)
has "20 an empty command shows ? for the model and keeps the columns" "$(row "$out" Aracati)" 'Aracati *? *? *?'

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
has "12 healthy workspace still prints" "$out" 'Aracati'
check "12 malformed workspace shows one ? block" "$(printf '%s\n' "$out" | grep -c '^  ? ─')" "1"

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
rm -rf "$T/maestri/usage" "$T/maestri/preferences.json"
out=$(run); code=$?
check "13 nothing missing: exit code" "$code" "0"
has "13 missing notes, session, transcript, state: ?" "$(row "$out" Aracati)" '?'
has "13 missing preferences: the row still prints" "$(row "$out" Aracati)" 'Aracati.*sonnet'
rm -rf "$T/maestri"
out=$(run); check "13 no Maestri dir at all: exit code" "$?" "0"

reset
CWD=$(roledir "$T/code/proj-a-1" AAAA-EXEC)
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"content":[{"type":"text","text":"x"}],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"token":"SECRET-TOKEN"}
EOF
printf '%s' '{"apiKey":"SECRET-APIKEY","token":"SECRET-TOKEN","credentials":{"password":"SECRET-PASS"},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1},"seven_day":{"used_percentage":6,"resets_at":2}},"model":{"id":"m1"},"context_window":{"context_window_size":1000}}' \
  | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" > "$T/sl.out"
out=$(run)
all="$out$(cat "$T/sl.out" "$STATE"/*.json)"
hasnt "14 no secret value in output or state file" "$all" 'SECRET'


reset
WS=$T/code/proj
DEF=$(roledir "$WS" BBBB-ORCH)
WS_DIR=$WS workspace w1 "ProjA" \
  "$(terminal Definidor claude_code stopped 'claude --model opus' BBBB-ORCH "$WS")" \
  "$(terminal Morto claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-9")" \
  "$(terminal Maestro claude_code stopped claude AAAA-EXEC '')" \
  "$(terminal Sem claude_code stopped 'claude --model opus' AAAA-EXEC "$T/code/proj-8")" \
  "$(terminal Shell generic_shell running '' '' "$WS")"
session "$T/claude-a" s1 "$DEF" idle $(( (NOW - 60) * 1000 ))
dead=$(bash -c 'echo $$')
session "$T/claude-a" s2 "$(roledir "$T/code/proj-9" AAAA-EXEC)" idle $(( NOW * 1000 )) "$dead"
session "$T/claude-b" s3 "$(roledir "$WS" AAAA-EXEC)" busy $(( NOW * 1000 ))
transcript "$T/claude-b" "$(roledir "$WS" AAAA-EXEC)" s3 <<EOF
{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"ok"}]}}
EOF
out=$(run)
has "21 a stopped terminal with a live session gets a row" "$(row "$out" Definidor)" 'Definidor.*opus'
has "21 its role sits in the ticket column" "$(row "$out" Definidor)" 'Orquestrador'
has "21 with no board line the state comes from the session" "$(row "$out" Definidor)" 'parado'
hasnt "22 a running terminal whose process died gets no row" "$out" Morto
hasnt "22 a stopped terminal with no session gets no row" "$out" 'Sem '
has "23 no working directory: matched in the workspace's directory" "$(row "$out" Maestro)" 'Maestro'
has "23 no --model in the command: the transcript's model" "$(row "$out" Maestro)" 'Maestro *opus'
hasnt "24 a shell terminal gets no row" "$out" Shell

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
out=$(run)
has "25 no session files at all: a running terminal still prints" "$(row "$out" Aracati)" 'Aracati.*?'

reset
C1=$(roledir "$T/code/a" AAAA-EXEC); C2=$(roledir "$T/code/b" AAAA-EXEC); C3=$(roledir "$T/code/c" AAAA-EXEC)
workspace w1 "ProjA" "$(terminal Calmo claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/c")"
workspace w2 "ProjB" \
  "$(terminal Tranquilo claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/a")" \
  "$(terminal Urgente claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/b")"
note w2 "for you" "- [ ] um" "- [ ] dois"
note w1 "for you" "- [x] feito"
note w2 board "Urgente · #1 · implementing · sonnet"
session "$T/claude-a" s1 "$C1" idle $(( NOW * 1000 ))
session "$T/claude-a" s2 "$C2" idle $(( NOW * 1000 ))
session "$T/claude-a" s3 "$C3" idle $(( NOW * 1000 ))
transcript "$T/claude-a" "$C2" s2 <<EOF
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}
EOF
out=$(run)
check "26 the row with an open question comes first, its project too" "$(printf '%s\n' "$out" | grep -E 'Calmo|Tranquilo|Urgente' | awk '{print $2}' | tr '\n' ' ')" "Urgente Tranquilo Calmo "
has "26 the title counts agents and everything waiting on you" "$out" '3 agentes · 3 pendências'
hasnt "10n no row with points hides the column" "$(row "$out" Urgente)" '  ?  '

reset
WS=$T/code/x
workspace w1 "ProjA" "$(terminal Longo claude_code running 'claude --model sonnet' AAAA-EXEC "$WS")"
note w1 board "Longo · #171/#172 · reviewing (round 1, tres defeitos voltaram e mais um texto bem comprido para estourar a largura) · sonnet · 5"
state_file claude-personal "$NOW" 200000
jq --argjson r "$(( NOW + 600 ))" '.five_hour.used_percentage = 92 | .five_hour.resets_at = $r' "$STATE/claude-personal.json" > "$T/s.json" && mv "$T/s.json" "$STATE/claude-personal.json"
out=$(COLUMNS=80 bash "$ROOT/bin/cockpit" --once 2>&1)
check "27 at 80 columns no line is longer than 80" "$(( $(printf '%s\n' "$out" | LC_ALL=C.UTF-8 wc -L) <= 80 ))" "1"
has "27 a long state ends in an ellipsis" "$(row "$out" Longo)" '…'
has "27n the ticket drops its parent" "$(row "$out" Longo)" ' #172 '
has "28 the 5-hour reset time shows" "$out" "↻ $(date -d "@$((NOW + 600))" +%H:%M)"
hasnt "29 piped output has no escape codes" "$out" $'\e'
tty=$(script -qec "bash '$ROOT/bin/cockpit' --once" /dev/null 2>&1)
has "29 on a terminal a 92% limit is red" "$tty" $'\e\[38;5;203m█'
state_file claude-personal "$NOW" 200000
jq '.five_hour.resets_at = 1' "$STATE/claude-personal.json" > "$T/s.json" && mv "$T/s.json" "$STATE/claude-personal.json"
out=$(run)
has "30 a window already over says it renewed" "$out" 'renovou'

reset
send() { printf '{"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":50,"resets_at":%s}}}' "$1" "$2" "$(( NOW + 90000 ))" | CLAUDE_CONFIG_DIR="$T/claude-a" bash "$ROOT/bin/cockpit-statusline" >/dev/null; }
send 93 $(( NOW + 600 )); send 80 $(( NOW + 600 ))
check "31 an idle session's older reading does not lower the limit" "$(jq .five_hour.used_percentage "$STATE/claude-a.json")" "93"
send 4 $(( NOW + 18000 ))
check "31 a new window replaces the old reading" "$(jq .five_hour.used_percentage "$STATE/claude-a.json")" "4"
send 93 $(( NOW + 600 ))
check "31 a reading of the old window does not replace the new one" "$(jq .five_hour.used_percentage "$STATE/claude-a.json")" "4"

reset
echo '{"five_hour":{"used_percentage":"muito","resets_at":"logo"},"seven_day":{"used_percentage":null},"updated_at":"ontem"}' > "$STATE/claude-a.json"
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
out=$(run); code=$?
check "32 a changed limits format: exit code" "$code" "0"
hasnt "32 a changed limits format prints no shell error" "$out" 'integer\|syntax\|expected'
has "32 a changed limits format shows ?" "$out" '5h [░ ]*?'

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
