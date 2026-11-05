#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME=$(command -v google-chrome || command -v google-chrome-stable || command -v chromium) || { echo "red: needs Google Chrome"; exit 1; }
T=$(mktemp -d); SRV=''; trap '[ -z "$SRV" ] || kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT

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

git -C "$ROOT" show b1e3a40:bin/cockpit > "$T/cockpit-main"
: > "$T/once-changed"
timeless() { sed -E -e 's/ +[0-9]+[smhd]( |$)/ A\1/g' -e 's/^(  COCKPIT  )[0-9:]+/\1/'; }
run() {
  local new code old
  new=$(bash "$ROOT/bin/cockpit" --once 2>&1); code=$?
  old=$(bash "$T/cockpit-main" --once 2>&1)
  diff <(timeless <<<"$old") <(timeless <<<"$new") >> "$T/once-changed"
  printf '%s\n' "$new"
  return "$code"
}

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

sum() { find "$T/maestri" "$T/claude-a" "$T/claude-b" "$T/state" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum; }
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

snap() { timeout 20 bash "$ROOT/bin/cockpit" --json 2>/dev/null; }
agent() { jq -c --arg n "$2" '.projects[].agents[] | select(.name == $n)' <<<"$1"; }
val() { jq -r "$2" <<<"$1"; }
one_agent() { workspace w1 "ProjA" "$(terminal "$1" claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"; }
CWD=$(roledir "$T/code/proj-a-1" AAAA-EXEC)

reset
one_agent Aracati
note w1 board "Aracati · #171/#184 · implementing · sonnet · 3"
note w1 "for you" "- [ ] one" "- [ ] two"
session "$T/claude-a" s1 "$CWD" busy $(( (NOW - 7200) * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
EOF
state_file claude-a "$NOW" 200000
jq --argjson f "$(( NOW + 600 ))" --argjson s "$(( NOW + 90000 ))" '.five_hour.resets_at = $f | .seven_day.resets_at = $s' "$STATE/claude-a.json" > "$T/s.json" && mv "$T/s.json" "$STATE/claude-a.json"
out=$(snap); code=$?
check "S1 json is valid and has every field of the terminal list, both reset times and the step: exit code" "$code" "0"
check "S1 json is valid and has every field of the terminal list, both reset times and the step: agent" \
  "$(val "$(agent "$out" Aracati)" '[.name,.model,.role,.ticket,.points,.status_text,.since,.context,.step] | @csv')" \
  '"Aracati","sonnet","Executor","#184",3,"implementando","2h",50,2'
check "S1 json is valid and has every field of the terminal list, both reset times and the step: limits" \
  "$(val "$out" '.limits[] | select(.account == "claude-a") | [.five_hour.used, .five_hour.resets_at, .seven_day.used, .seven_day.resets_at, .updated_at] | @csv')" \
  "12,$((NOW + 600)),40,$((NOW + 90000)),$NOW"
check "S1 json is valid and has every field of the terminal list, both reset times and the step: project and for you" \
  "$(val "$out" '.projects[0] | [.name, .for_you] | @csv')" '"ProjA",2'

reset
one_agent Aracati
mkdir -p "$T/maestri/workspaces/bad"; echo '{broken' > "$T/maestri/workspaces/bad/workspace.json"
rm -rf "$T/maestri/usage" "$T/maestri/preferences.json"
echo '{"five_hour":{"used_percentage":"muito","resets_at":"logo"},"seven_day":{"used_percentage":null},"updated_at":"ontem"}' > "$STATE/claude-a.json"
out=$(snap); code=$?
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: exit code" "$code" "0"
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: malformed workspace" \
  "$(val "$out" '.projects[] | select(.name == "?") | .agents[0] | [.name,.status,.step,.context] | join(" ")')" '? ? ? ?'
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: missing files" \
  "$(val "$(agent "$out" Aracati)" '[.role,.ticket,.points,.since,.context,.step,.status] | join(" ")')" '? ? ? ? ? ? ?'
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: missing for you" \
  "$(val "$out" '.projects[] | select(.name == "ProjA") | .for_you')" '?'
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: changed limits format" \
  "$(val "$out" '.limits[] | select(.account == "claude-a") | [.five_hour.used,.five_hour.resets_at,.seven_day.used,.seven_day.resets_at,.age] | join(" ")')" '? ? ? ? ?'
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: missing usage file" \
  "$(val "$out" '.limits[] | select(.account == "codex") | [.five_hour.used,.seven_day.used,.age] | join(" ")')" '? ? ?'
mkdir -p "$T/maestri/usage/providers"
echo '{"providers":[{"id":"codex","meters":[{"windows":[{"ring":"session","usedPercent":7},{"ring":"weekly","usedPercent":23}]}]}]}' > "$T/maestri/usage/providers/.status.json"
out=$(snap)
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: codex with no dates" \
  "$(val "$out" '.limits[] | select(.account == "codex") | [.five_hour.used,.five_hour.resets_at,.seven_day.used,.seven_day.resets_at,.updated_at,.age] | join(" ")')" '7 ? 23 ? ? ?'
echo '{"providers":[{"id":"codex","meters":[{"windows":[{"ring":"session","usedPercent":7,"resetsAt":"2030-01-01T00:00:00Z"},{"ring":"weekly","usedPercent":23,"resetsAt":"2030-01-02T00:00:00Z"},{"ring":"weekly","usedPercent":9}]}]}]}' > "$T/maestri/usage/providers/.status.json"
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: codex with two weekly windows invents no date" \
  "$(val "$(snap)" '.limits[] | select(.account == "codex") | [.five_hour.used,.five_hour.resets_at,.seven_day.used,.seven_day.resets_at] | join(" ")')" "7 $(date -d 2030-01-01T00:00:00Z +%s) 23 $(date -d 2030-01-02T00:00:00Z +%s)"
rm -rf "$T/maestri"
out=$(snap); code=$?
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: no Maestri dir" "$code/$(val "$out" '.projects | length')" "0/0"

reset
jq '.payload.rolePresets += [{"id":"cccc-rev","name":"Code Reviewer"},{"id":"CCCC-REV","name":"Revisor"}]' "$T/maestri/preferences.json" > "$T/p.json" && mv "$T/p.json" "$T/maestri/preferences.json"
workspace w1 "ProjA" "$(terminal Ana claude_code running 'claude --model sonnet' CCCC-REV "$T/code/proj-a-1")"
note w1 board "Ana · #1"
note w1 "for you" "- [ ] one"
out=$(snap); code=$?
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: a board line with an empty state" "$code $(val "$out" '.projects | length') $(val "$(agent "$out" Ana)" '[.role,.status_text] | join(" ")')" "0 1 Code Reviewer ?"
chmod 000 "$T/maestri/workspaces/w1/notes/for you.md"
out=$(snap); code=$?
check "S2 a malformed workspace or a missing file gives ? in that field and exit 0: an unreadable for you" "$code $(val "$out" '.projects[0].for_you')" "0 ?"
chmod 644 "$T/maestri/workspaces/w1/notes/for you.md"
out=$(timeout 20 bash "$ROOT/bin/cockpit" --once 2>&1); code=$?
check "S12 a board line with an empty field still ends and exits 0" "$code" 0

reset
one_agent Aracati
workspace w2 "ProjB" "$(terminal Outro claude_code running 'claude --model opus' AAAA-EXEC "$T/code/proj-b-1")"
note w1 board "Aracati · #184"$'\t'" · implementing · sonnet · 3"
note w1 "for you" "- [ ] one"
note w2 "for you" "- [ ] two" "- [ ] three"
out=$(snap); code=$?
check "S2 a tab in a board line gives ? in that field and exit 0: exit code" "$code" 0
check "S2 a tab in a board line gives ? in that field and exit 0: the field" "$(val "$(agent "$out" Aracati)" '.ticket')" '?'
check "S2 a tab in a board line gives ? in that field and exit 0: for you stays" "$(val "$out" '[.projects[].for_you] | @csv')" '1,2'
check "S2 a tab in a board line gives ? in that field and exit 0: the other project stays" "$(val "$(agent "$out" Outro)" '.model')" opus

reset
one_agent Aracati
echo '{"five_hour":{"used_percentage":"","resets_at":1793860000},"seven_day":{"used_percentage":40,"resets_at":1793860001},"updated_at":""}' > "$STATE/claude-a.json"
check "S2 an empty limit field stays unknown and moves no other field" \
  "$(val "$(snap)" '.limits[] | select(.account == "claude-a") | [.five_hour.used,.five_hour.resets_at,.seven_day.used,.seven_day.resets_at,.updated_at] | join(" ")')" '? 1793860000 40 1793860001 ?'
echo '{"providers":[{"id":"codex","lastSuccessAt":"","meters":[{"windows":[{"ring":"session","usedPercent":"","resetsAt":"2030-01-01T00:00:00Z"},{"ring":"weekly","usedPercent":23}]}]}]}' > "$T/maestri/usage/providers/.status.json"
check "S2 an empty codex field stays unknown and moves no other field" \
  "$(val "$(snap)" '.limits[] | select(.account == "codex") | [.five_hour.used,.five_hour.resets_at,.seven_day.used] | join(" ")')" "? $(date -d 2030-01-01T00:00:00Z +%s) 23"
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
jq '.status = ""' "$T/claude-a/sessions/s1.json" > "$T/s.json" && mv "$T/s.json" "$T/claude-a/sessions/s1.json"
transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
EOF
state_file claude-a "$NOW" 200000
check "S2 an empty session status moves no other field" "$(val "$(agent "$(snap)" Aracati)" '.context')" 50

reset
one_agent Aracati
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"content":[{"type":"text","text":"sem usage"}]}}
EOF
state_file claude-a "$NOW" 200000
check "S3 a context the cockpit cannot compute is unknown in the snapshot, not 0" "$(val "$(agent "$(snap)" Aracati)" '.context')" '?'
transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"model":"m1","usage":{},"content":[{"type":"text","text":"ok"}]}}
EOF
check "S3 a context the cockpit cannot compute is unknown in the snapshot, not 0: empty usage" "$(val "$(agent "$(snap)" Aracati)" '.context')" '?'
transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
EOF
state_file claude-a "$NOW" 0
check "S3 a context the cockpit cannot compute is unknown in the snapshot, not 0: zero window" "$(val "$(agent "$(snap)" Aracati)" '.context')" '?'

for line in 'recon|1|running' 'grilling|1|running' 'implementing|2|running' 'reviewing|3|review' 'PR open|4|review' 'CI|5|review' \
  'verified|6|review' 'waiting Jonatas|6|needs' 'merged PR #187|7|done' 'held behind #173|0|blocked'; do
  IFS='|' read -r bstate step status <<<"$line"
  reset
  one_agent Aracati
  note w1 board "Aracati · #184 · $bstate · sonnet · 3"
  session "$T/claude-a" s1 "$CWD" idle $(( NOW * 1000 ))
  check "S4 each board state maps to its step and status: $bstate" "$(val "$(agent "$(snap)" Aracati)" '[.step, .status] | join(" ")')" "$step $status"
done
reset
one_agent Aracati
note w1 board "Aracati · #184 · implementing · sonnet · 3"
session "$T/claude-a" s1 "$CWD" idle $(( NOW * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}
EOF
check "S4 each board state maps to its step and status: an open question is needs" "$(val "$(agent "$(snap)" Aracati)" '.status')" needs
reset
one_agent Aracati
note w1 board "# board"
session "$T/claude-a" s1 "$CWD" idle $(( NOW * 1000 ))
check "S4 each board state maps to its step and status: idle with no board line is stopped" "$(val "$(agent "$(snap)" Aracati)" '.status')" stopped
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
check "S4 each board state maps to its step and status: busy with no board line is running" "$(val "$(agent "$(snap)" Aracati)" '.status')" running
rm "$T/claude-a/sessions/s1.json"
session "$T/claude-b" s9 "$T/elsewhere" busy $(( NOW * 1000 ))
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")" "$(terminal Cdx codex running 'codex' '' "$T/code/proj-b")"
out=$(snap)
check "S4 each board state maps to its step and status: a running codex terminal is running" "$(val "$(agent "$out" Cdx)" '.status')" running
rm "$T/claude-b/sessions/s9.json"
check "S4 each board state maps to its step and status: no session at all is ?" "$(val "$(agent "$(snap)" Aracati)" '.status')" '?'

reset
one_agent Aracati
note w1 board "# board" "Outro · #9 · implementing · sonnet · 1"
check "S5 a ticket with no board line has no step" "$(val "$(agent "$(snap)" Aracati)" '[.ticket, .step] | join(" ")')" '— —'

reset
one_agent Aracati
note w1 board "# board" "testes · https://x/y" "status 04/11: #171/#172 merged" \
  "Tamarindo · #153 · merged PR #186 · sonnet" \
  "Alicerce · #171/#172 · merged PR #188 · opus" \
  "Mirante · #171/#173 · merged PR #191 · opus" \
  "Aracati · #171/#174 · reviewing (PR #190) · opus" \
  "#171/#176 · held behind PR #190 e #192" \
  "#171/#179 · held behind #173 e #174"
check "S6 five parent lines with two merged give 2 of 5" "$(val "$(snap)" '.projects[0].slices | tojson')" '[{"parent":"#171","merged":2,"total":5}]'
reset
one_agent Aracati
note w1 board "# board" "Aracati · #184 · reviewing · opus" "Tamarindo · #153 · merged PR #186 · sonnet"
note w1 board "Aracati · ENG-894/ENG-900 · merged PR #9 · opus" "ENG-894/ENG-901 · held behind ENG-900"
check "S6 a Linear parent counts its slices" "$(val "$(snap)" '.projects[0].slices | tojson')" '[{"parent":"ENG-894","merged":1,"total":2}]'
note w1 board "# board" "Aracati · #184 · reviewing · opus" "Tamarindo · #153 · merged PR #186 · sonnet"
check "S6 a board with no parent gives no slices" "$(val "$(snap)" '.projects[0].slices | tojson')" '[]'

reset
one_agent Aracati
note w1 board "Aracati · #184 · merged PR #187 · sonnet · 3"
note w1 "for you" "# for you"
session "$T/claude-a" s1 "$CWD" idle $(( NOW * 1000 ))
out=$(snap)
check "S7 an agent with a merged line and an idle session is done and not counted in pendências: status" "$(val "$(agent "$out" Aracati)" '.status')" done
check "S7 an agent with a merged line and an idle session is done and not counted in pendências: pendências" "$(val "$out" '.pending.total')" 0
transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}
EOF
out=$(snap)
check "S7 an agent with a merged line and an idle session is done and not counted in pendências: even with an open question" "$(val "$(agent "$out" Aracati)" '.status') $(val "$out" '.pending.total')" 'done 0'

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet --api-key SECRET-COMMAND' AAAA-EXEC "$T/code/proj-a-1")"
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"model":"m1","content":[{"type":"text","text":"SECRET-TEXT"}],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"token":"SECRET-TOKEN"}
EOF
echo '{"apiKey":"SECRET-APIKEY","credentials":{"password":"SECRET-PASS"},"five_hour":{"used_percentage":5,"resets_at":1},"seven_day":{"used_percentage":6,"resets_at":2},"updated_at":1,"context_window_sizes":{"m1":1000}}' > "$STATE/claude-a.json"
echo '{"token":"SECRET-TOKEN","providers":[{"id":"codex","apiKey":"SECRET-APIKEY","meters":[{"windows":[{"ring":"session","usedPercent":7}]}]}]}' > "$T/maestri/usage/providers/.status.json"
workspace w2 "ProjB" "$(terminal Vazado claude_code running "claude --model opus
ANTHROPIC_API_KEY=sk-SECRET" AAAA-EXEC "$T/code/proj-b-1")" "$(terminal Longo claude_code running 'claude --model claude-opus-5-5[1m]' AAAA-EXEC "$T/code/proj-b-2")"
session "$T/claude-a" s2 "$(roledir "$T/code/proj-b-1" AAAA-EXEC)" busy $(( NOW * 1000 ))
session "$T/claude-a" s3 "$(roledir "$T/code/proj-b-2" AAAA-EXEC)" busy $(( NOW * 1000 ))
out=$(snap)
check "S8 a model that is not a name token is ?" "$(val "$(agent "$out" Vazado)" '.model')" '?'
check "S8 a model that is a name token stays" "$(val "$(agent "$out" Longo)" '.model')" 'claude-opus-5-5[1m]'
hasnt "S8 a secret after the model reaches no terminal line" "$(bash "$ROOT/bin/cockpit" --once 2>&1)" SECRET
check "S8 a fixture with secret fields shows none of their values in json: the fixture produced a row" "$(val "$(agent "$out" Aracati)" '.model')" sonnet
hasnt "S8 a fixture with secret fields shows none of their values in json" "$out" SECRET

serve_start() {
  PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
  env PATH="${SERVE_PATH:-$PATH}" bash "$ROOT/bin/cockpit" --serve "$PORT" > "$T/serve.log" 2>&1 &
  SRV=$!
  for _ in $(seq 100); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/" && return
    sleep 0.1
  done
  echo "FAIL  server did not start: $(cat "$T/serve.log")"; failed=1
}
serve_stop() { kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; SRV=''; }
code_of() { curl -s -o /dev/null -w '%{http_code}' "$@" "http://127.0.0.1:$PORT${URLPATH:-/snapshot}"; }
page() { "$CHROME" --headless=new --disable-gpu --no-sandbox --user-data-dir="$T/profile" --virtual-time-budget=4000 --dump-dom "http://127.0.0.1:$PORT/" 2>/dev/null | sed '/<script>/,/<\/script>/d'; }
visible() { sed 's/<[^>]*>/ /g' <<<"$1" | tr -s ' \n' ' '; }
cell() { grep -oP "<td class=\"$2\">.*?</td>" <<<"$1"; }
refused() { [ "$(code_of "$@")" -ge 400 ] && echo yes; }

reset
one_agent Aracati
note w1 board "Aracati · #171/#184 · reviewing · sonnet · 3" "#171/#185 · merged PR #1 · opus"
note w1 "for you" "- [ ] one"
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
EOF
state_file claude-a "$NOW" 200000
jq --argjson f "$(( NOW + 600 ))" --argjson s "$(( NOW + 90000 ))" '.five_hour.resets_at = $f | .seven_day.resets_at = $s' "$STATE/claude-a.json" > "$T/s.json" && mv "$T/s.json" "$STATE/claude-a.json"
before=$(sum)
serve_start
check "S9 serve binds to 127.0.0.1 and returns the page and the snapshot: bound to loopback only" "$(ss -ltnH "sport = :$PORT" | awk '{print $4}')" "127.0.0.1:$PORT"
has "S9 serve binds to 127.0.0.1 and returns the page and the snapshot: the page" "$(curl -s "http://127.0.0.1:$PORT/")" '<title>Cockpit'
check "S9 serve binds to 127.0.0.1 and returns the page and the snapshot: the snapshot" "$(val "$(curl -s "http://127.0.0.1:$PORT/snapshot")" '.projects[0].agents[0].name')" Aracati
check "S9 serve binds to 127.0.0.1 and returns the page and the snapshot: an unknown path is 404" "$(URLPATH=/nada code_of)" 404
hasnt "S9 the server sends no CORS header" "$(curl -s -D - -o /dev/null -H 'Origin: http://evil.example' "http://127.0.0.1:$PORT/snapshot" | tr 'A-Z' 'a-z')" 'access-control'

check "S10 POST returns an error" "$(refused -X POST -d x)" yes
check "S10 PUT returns an error" "$(refused -X PUT -d x)" yes
check "S10 DELETE returns an error" "$(refused -X DELETE)" yes
curl -s -o /dev/null "http://127.0.0.1:$PORT/"; curl -s -o /dev/null "http://127.0.0.1:$PORT/snapshot"
check "S10 the data directories checksum is unchanged after requests" "$(sum)" "$before"

check "S11 a request with Host evil.example returns 403" "$(code_of -H 'Host: evil.example')" 403
check "S11 a request with Host evil.example returns 403: the page too" "$(URLPATH=/ code_of -H 'Host: evil.example')" 403
check "S11 a request with Host evil.example returns 403: before the method" "$(code_of -X POST -H 'Host: evil.example')" 403
check "S11 a request with Host evil.example returns 403: a lookalike" "$(code_of -H 'Host: localhost.evil.example')" 403
check "S11 a request with a foreign Origin returns 403" "$(code_of -H 'Origin: http://evil.example')" 403
check "S11 a request with a foreign Origin returns 403: the page too" "$(URLPATH=/ code_of -H 'Origin: http://evil.example')" 403
check "S11 a request with a foreign Origin returns 403: a lookalike" "$(code_of -H 'Origin: http://localhost.evil.example')" 403
check "S11 a request with a foreign Origin returns 403: a null origin" "$(code_of -H 'Origin: null')" 403
check "S11 a request with a foreign Origin returns 403: another scheme" "$(code_of -H 'Origin: file://localhost')" 403
for origin in "http://localhost:$PORT" "http://127.0.0.1:$PORT" http://localhost; do
  check "S11 Origin $origin passes" "$(code_of -H "Origin: $origin")" 200
done
check "S11 a missing Host is rejected" "$(code_of -H 'Host:')" 403
for host in localhost 127.0.0.1 "localhost:$PORT" "127.0.0.1:$PORT"; do
  check "S11 Host $host passes" "$(URLPATH=/ code_of -H "Host: $host")" 200
done

second=$(timeout 5 bash "$ROOT/bin/cockpit" --serve "$PORT" 2>&1); code=$?
check "S9 a port taken exits non-zero" "$((code != 0))" 1
has "S9 a port taken gives a clear error" "$second" "$PORT"
hasnt "S9 a port taken shows no traceback" "$second" Traceback
for bad in abc 70000 0; do
  second=$(timeout 5 bash "$ROOT/bin/cockpit" --serve "$bad" 2>&1); code=$?
  check "S9 port $bad exits non-zero" "$((code != 0))" 1
  has "S9 port $bad gives a clear error" "$second" "$bad is not a port"
done

dom=$(page)
served=$(curl -s "http://127.0.0.1:$PORT/")
has "S13 the served page is the page" "$served" 'fetch('
hasnt "S13 the page has no request outside the machine" "$served" '://\|<link\|@import\|url(\|src='
has "S13 the page shows the board step" "$(cell "$dom" c-done)" 'revisando'
hasnt "S13 the page has no percentage for Conclusão" "$(cell "$dom" c-done)" '%'
has "S6 the page shows the slices of the parent ticket" "$dom" 'Fatias do ticket #171'
has "S6 the page shows 1 of 2" "$dom" '1 de 2'
has "S9 the page shows the real quota" "$dom" '<span class="pct">12%</span>'
has "S9 the page shows the age of the limits" "$dom" 'lido há'
serve_stop

reset
one_agent '<img src=x>'
state_file claude-a "$NOW" 200000
jq '.five_hour.used_percentage = 94 | .five_hour.resets_at = 1 | .seven_day.used_percentage = 10' "$STATE/claude-a.json" > "$T/s.json" && mv "$T/s.json" "$STATE/claude-a.json"
echo '{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 600))"'},"updated_at":'"$NOW"'}' > "$STATE/claude-b.json"
serve_start
dom=$(page); text=$(visible "$dom")
has "S14 an unknown value on the page renders as ? or —, never 0: the page rendered" "$text" 'Agentes 1 '
hasnt "S14 an unknown value on the page renders as ? or —, never 0: no bare zero" "$dom" '>0%\?<'
has "S14 an unknown value on the page renders as ? or —, never 0: quota" "$dom" '<span class="pct">?</span>'
has "S14 an unknown value on the page renders as ? or —, never 0: context" "$(cell "$dom" c-ctx)" '?'
has "S14 an unknown value on the page renders as ? or —, never 0: Conclusão" "$(cell "$dom" c-done)" '?'
has "S14 an unknown value on the page renders as ? or —, never 0: pendências" "$text" 'Pendências ? '
has "S14 an expired window is not the quota nearest its limit" "$text" 'Mais perto do limite 30%'
has "S14 the quota nearest its limit names its window" "$text" 'claude-b · 5 horas'
hasnt "S6 the page hides the slices with no parent" "$dom" 'Fatias do ticket'
hasnt "S14 snapshot values are not trusted markup" "$dom" '<img'
has "S14 snapshot values are shown as text" "$dom" '&lt;img'
serve_stop

reset
one_agent Aracati
state_file claude-a "$NOW" 200000
jq --argjson f "$(( NOW + 600 ))" --argjson s "$(( NOW + 90000 ))" '.five_hour.used_percentage = 10 | .five_hour.resets_at = $f | .seven_day.used_percentage = 95 | .seven_day.resets_at = $s' "$STATE/claude-a.json" > "$T/s.json" && mv "$T/s.json" "$STATE/claude-a.json"
serve_start
has "S14 the quota nearest its limit may be the 7-day one" "$(visible "$(page)")" 'Mais perto do limite 95% claude-a · 7 dias'
serve_stop

mkdir -p "$T/nojq"
for tool in bash python3 dirname readlink date; do ln -s "$(command -v "$tool")" "$T/nojq/$tool"; done
SERVE_PATH="$T/nojq" serve_start
check "S9 a snapshot that fails returns an error status" "$(code_of)" 500
has "S14 the page says the refresh failed" "$(page)" 'role="status">Atualização falhou'
serve_stop

snapshots_alive() { pgrep -f -- "$ROOT/bin/cockpit --json|jq -e . $STATE/stuck.json" | wc -l; }
reset
one_agent Aracati
state_file claude-a "$NOW" 200000
serve_start
mkfifo "$STATE/stuck.json"
started=$(date +%s)
for _ in 1 2 3 4 5 6 7 8; do curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:$PORT/snapshot" >> "$T/burst" & done
sleep 2
check "S10 at most one snapshot at a time: a burst starts one collection" "$(pgrep -f "jq -e . $STATE/stuck.json" | wc -l)" 1
check "S10 at most one snapshot at a time: the page still answers" "$(URLPATH=/ code_of)" 200
for _ in $(seq 240); do [ "$(grep -c . "$T/burst")" = 8 ] && break; sleep 0.25; done
check "S9 a stuck snapshot answers an error to everyone waiting" "$(sort -u "$T/burst")" 500
check "S9 a stuck snapshot is cut within the timeout" "$(( $(date +%s) - started <= 30 ))" 1
sleep 0.5
check "S9 nothing of the snapshot survives the timeout" "$(snapshots_alive)" 0
rm "$STATE/stuck.json"
check "S9 after a stuck snapshot the next one works" "$(code_of)" 200
mkfifo "$STATE/stuck.json"
curl -s -o /dev/null "http://127.0.0.1:$PORT/snapshot" &
sleep 2
check "S9 a stuck snapshot is running before the server stops" "$(pgrep -f "jq -e . $STATE/stuck.json" | wc -l)" 1
serve_stop
sleep 0.5
check "S9 nothing of the snapshot survives the server" "$(snapshots_alive)" 0
rm "$STATE/stuck.json"

check "S12 the --once output for the existing fixtures is unchanged" "$(cat "$T/once-changed")" ""

exit $failed
