#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME=$(command -v google-chrome || command -v google-chrome-stable || command -v chromium) || { echo "red: needs Google Chrome"; exit 1; }
T=$(mktemp -d); SRV=''; trap '[ -z "$SRV" ] || kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT

export MAESTRI_DATA_DIR="$T/maestri"
export XDG_STATE_HOME="$T/state"
export COCKPIT_CLAUDE_DIRS="$T/claude-a:$T/claude-b"
export COCKPIT_PROC_DIR="$T/no-proc"
export COCKPIT_CODEX_DIR="$T/codex/sessions"
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
  rm -rf "$T/maestri" "$T/state" "$T/claude-a" "$T/claude-b" "$T/claude-c" "$T/proc" "$T/codex"
  mkdir -p "$T/proc" "$T/codex/sessions"
  mkdir -p "$T/maestri/workspaces" "$T/maestri/usage/providers" "$T/claude-a/sessions" "$T/claude-b/sessions" "$STATE"
  cat > "$T/maestri/preferences.json" <<'EOF'
{"payload":{"rolePresets":[
  {"id":"AAAA-EXEC","name":"Executor"},
  {"id":"BBBB-ORCH","name":"Orquestrador"}]}}
EOF
  echo '{"providers":[]}' > "$T/maestri/usage/providers/.status.json"
}

terminal() {
  jq -n --arg name "$1" --arg type "$2" --arg status "$3" --arg cmd "$4" --arg role "$5" --arg wd "$6" --arg id "${7:-}" \
    '{content:{terminal:{_0:{id:$id,name:$name,agentType:$type,status:$status,command:$cmd,assignedRoleId:$role,workingDirectory:$wd,apiKey:"SECRET-APIKEY",token:"SECRET-TOKEN"}}}}'
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
for date in '""' '"0"'; do
  echo '{"providers":[{"id":"codex","lastSuccessAt":'"$date"',"meters":[{"windows":[{"ring":"session","usedPercent":7,"resetsAt":'"$date"'},{"ring":"weekly","usedPercent":23,"resetsAt":'"$date"'}]}]}]}' > "$T/maestri/usage/providers/.status.json"
  check "S2 a codex date $date is no date" \
    "$(val "$(snap)" '.limits[] | select(.account == "codex") | [.five_hour.resets_at,.seven_day.resets_at,.updated_at,.age] | join(" ")')" '? ? ? ?'
done
printf '{"five_hour":{"used_percentage":1},"seven_day":{"used_percentage":2},"updated_at":"x\\u001f77"}\n' > "$STATE/claude-a.json"
check "S2 a separator inside a value moves no other field" \
  "$(val "$(snap)" '.limits[] | select(.account == "claude-a") | [.five_hour.used,.seven_day.used,.updated_at] | join(" ")')" '1 2 ?'
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
for model in 'claude-sonnet-4@20250514' 'openrouter/anthropic/claude-opus' 'opus[1M]'; do
  workspace w3 "ProjC" "$(terminal Valido claude_code running "claude --model $model --effort low" AAAA-EXEC "$T/code/proj-c-1")"
  session "$T/claude-a" s4 "$(roledir "$T/code/proj-c-1" AAAA-EXEC)" busy $(( NOW * 1000 ))
  check "S8 the model name $model stays" "$(val "$(agent "$(snap)" Valido)" '.model')" "$model"
done
workspace w3 "ProjC" "$(terminal Citado claude_code running 'claude --model "opus" --effort low' AAAA-EXEC "$T/code/proj-c-1")"
check "S8 a quoted model name loses its quotes" "$(val "$(agent "$(snap)" Citado)" '.model')" opus
workspace w3 "ProjC" "$(terminal Recuo claude_code running "claude --model opus
KEY=sk-SECRET" AAAA-EXEC "$T/code/proj-c-1")"
transcript "$T/claude-a" "$(roledir "$T/code/proj-c-1" AAAA-EXEC)" s4 <<EOF
{"type":"assistant","message":{"model":"claude-fable-5-1","content":[{"type":"text","text":"ok"}]}}
EOF
check "S8 a rejected model falls back to the transcript" "$(val "$(agent "$(snap)" Recuo)" '.model')" fable
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
for site in cross-site same-site; do
  check "S11 Sec-Fetch-Site $site returns 403" "$(code_of -H "Sec-Fetch-Site: $site")" 403
  check "S11 Sec-Fetch-Site $site returns 403: the page too" "$(URLPATH=/ code_of -H "Sec-Fetch-Site: $site")" 403
done
for site in same-origin none; do
  check "S11 Sec-Fetch-Site $site passes" "$(code_of -H "Sec-Fetch-Site: $site")" 200
done
check "S11 a missing Sec-Fetch-Site passes" "$(code_of)" 200
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

waiting_session() {
  session "$T/claude-a" s1 "$CWD" waiting $(( NOW * 1000 ))
  jq --arg w "$1" '.waitingFor = $w' "$T/claude-a/sessions/s1.json" > "$T/s.json" && mv "$T/s.json" "$T/claude-a/sessions/s1.json"
}
reset
one_agent Aracati
note w1 board "# board"
waiting_session "input needed"
out=$(snap)
check "W1 a waiting session with waitingFor input needed and no board line is needs with esperando resposta" "$(val "$(agent "$out" Aracati)" '[.status, .status_text] | join(" ")')" 'needs esperando resposta'
has "W1 a waiting session with waitingFor input needed and no board line shows ! in the table" "$(row "$(bash "$ROOT/bin/cockpit" --once 2>&1)" Aracati)" '^  !.*esperando resposta'
waiting_session ""
check "W2 the same session with an empty waitingFor gives the same result" "$(val "$(agent "$(snap)" Aracati)" '[.status, .status_text] | join(" ")')" 'needs esperando resposta'
check "W3 the JSON counts the waiting row in pending.agents and in needs" "$(val "$(snap)" '[.pending.agents, .projects[0].agents[0].status] | join(" ")')" '1 needs'
reset
one_agent Aracati
note w1 board "Aracati · #184 · implementing · sonnet · 3"
waiting_session "input needed"
check "W4 a slice implementing with a waiting session shows needs and the text stays implementando" "$(val "$(agent "$(snap)" Aracati)" '[.status, .status_text] | join(" ")')" 'needs implementando'
reset
one_agent Aracati
note w1 board "# board"
session "$T/claude-a" s1 "$CWD" idle $(( NOW * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}
EOF
check "W5 idle with a pending AskUserQuestion in the transcript is needs, as before" "$(val "$(agent "$(snap)" Aracati)" '[.status, .status_text] | join(" ")')" 'needs parado'
rm "$T/claude-a/projects" -r
check "W6 idle with nothing pending is stopped and parado, as before" "$(val "$(agent "$(snap)" Aracati)" '[.status, .status_text] | join(" ")')" 'stopped parado'
session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
check "W7 busy stays trabalhando" "$(val "$(agent "$(snap)" Aracati)" '[.status, .status_text] | join(" ")')" 'running trabalhando'
session "$T/claude-a" s1 "$CWD" shell $(( NOW * 1000 ))
check "W7 shell stays rodando comando" "$(val "$(agent "$(snap)" Aracati)" '[.status, .status_text] | join(" ")')" 'running rodando comando'
reset
workspace w1 "ProjA" "$(terminal Calmo claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-2")" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1")"
note w1 board "# board"
session "$T/claude-a" s2 "$(roledir "$T/code/proj-a-2" AAAA-EXEC)" idle $(( NOW * 1000 ))
waiting_session "input needed"
state_file claude-a "$NOW" 200000
serve_start
dom=$(page)
has "W8 the waiting row comes first in the project" "$(grep -o '<td class="c-name">[^<]*' <<<"$dom" | head -1)" 'Aracati'
has "W8 the waiting row is hot on the page" "$(grep -o '<tr class="[a-z]*"><td class="c-mark"><span class="mark needs">!' <<<"$dom")" 'hot'
serve_stop

mkdir -p "$T/nojq"
for tool in bash python3 dirname readlink date; do ln -s "$(command -v "$tool")" "$T/nojq/$tool"; done
SERVE_PATH="$T/nojq" serve_start
check "S9 a snapshot that fails returns an error status" "$(code_of)" 500
has "S14 the page says the refresh failed" "$(page)" 'role="status">Atualização falhou'
serve_stop

snapshots_alive() { pgrep -f "jq -e . $STATE/stuck.json" | wc -l; }
reset
one_agent Aracati
state_file claude-a "$NOW" 200000
serve_start
mkfifo "$STATE/stuck.json"
started=$(date +%s)
for _ in 1 2 3 4 5 6 7 8; do curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:$PORT/snapshot" >> "$T/burst" & done
sleep 2
check "S10 at most one snapshot at a time: a burst starts one collection" "$(snapshots_alive)" 1
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
check "S9 a stuck snapshot is running before the server stops" "$(snapshots_alive)" 1
serve_stop
sleep 0.5
check "S9 nothing of the snapshot survives the server" "$(snapshots_alive)" 0
rm "$STATE/stuck.json"

PROC=$T/proc
CODEX=$T/codex/sessions
proc() { mkdir -p "$PROC/$1"; printf 'HOME=/x\0MAESTRI_TERMINAL_ID=%s\0PATH=/bin\0' "$2" > "$PROC/$1/environ"; printf '%s\n' "$3" > "$PROC/$1/comm"; }
rollout() {
  local f="$CODEX/2026/11/05/rollout-$1.jsonl"
  mkdir -p "$(dirname "$f")"
  {
    jq -nc --arg c "$2" --arg t "${7:-user}" '{type:"session_meta",payload:{cwd:$c,thread_source:$t}}'
    jq -nc --arg c "$2" --arg m "$3" '{type:"turn_context",payload:{cwd:$c,model:$m}}'
    [ -z "$4" ] || jq -nc --argjson i "$4" --argjson w "$5" '{type:"event_msg",payload:{type:"token_count",info:{last_token_usage:{input_tokens:$i},model_context_window:$w}}}'
  } > "$f"
  touch -d "@$6" "$f"
}
cdx_fields() { val "$(agent "$1" "$2")" '[.model, .context, .since] | join(" ")'; }
sum_all() { find "$T/maestri" "$T/claude-a" "$T/claude-b" "$T/state" "$PROC" "$T/codex" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum; }
export COCKPIT_PROC_DIR="$PROC"

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
proc 100 T1 codex
rollout r1 "$T/code/proj-b" gpt-6.1-sol 79229 475000 $((NOW - 7200))
check "P1 a codex terminal marked stopped with a live process gets a row with model, context and time" "$(cdx_fields "$(snap)" Cdx)" "gpt-6.1-sol 17 2h"

reset
workspace w1 "ProjA" "$(terminal Cdx codex running codex '' "$T/code/proj-b" T2)" "$(terminal Outro codex running codex '' "$T/code/proj-c" T9)"
proc 100 T9 codex
check "P2 a codex terminal marked running with no live process gets no row" "$(agent "$(snap)" Cdx)" ""

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T3)"
proc 100 T3 zsh
check "P3 a live shell carrying the terminal id does not make it live" "$(agent "$(snap)" Cdx)" ""

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T3)"
proc 100 T3 zsh
proc 101 T3 codex-code-mode
check "P3 a codex-code-mode helper carrying the terminal id does not make it live" "$(agent "$(snap)" Cdx)" ""

reset
workspace w1 "ProjA" "$(terminal Cus custom stopped 'zsh -l' '' "$T/code/proj-b" T3)"
proc 100 T3 zsh
check "P3 a shell does not count even as the terminal's own command" "$(agent "$(snap)" Cus)" ""

reset
mkdir -p "$T/claude-c/sessions"
workspace w1 "ProjA" "$(terminal Cus custom stopped "env CLAUDE_CONFIG_DIR=$T/claude-c claude --model sonnet" '' "$T/code/proj-c" T4)"
proc 100 T4 claude
session "$T/claude-c" s1 "$T/code/proj-c" busy $(( NOW * 1000 ))
transcript "$T/claude-c" "$T/code/proj-c" s1 <<EOF
$(usage_line 2 1000 99000)
EOF
state_file claude-c "$NOW" 200000
check "P4 a custom terminal running claude gets the session data from the CLAUDE_CONFIG_DIR of its command" \
  "$(val "$(agent "$(snap)" Cus)" '[.model, .context, .status_text] | join(" ")')" "sonnet 50 trabalhando"

reset
workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1" T5)"
proc 100 T5 claude
session "$T/claude-a" s1 "$CWD" busy $(( (NOW - 7200) * 1000 ))
transcript "$T/claude-a" "$CWD" s1 <<EOF
$(usage_line 2 1000 99000)
EOF
state_file claude-a "$NOW" 200000
out=$(run)
has "P5 a claude terminal prints the row it printed before" "$(row "$out" Aracati)" 'Aracati.*sonnet.*2h.*50%'

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
proc 100 T1 codex
rollout a-new "$T/code/proj-b" new-model 100 1000 $((NOW - 60))
rollout z-old "$T/code/proj-b" old-model 100 1000 $((NOW - 7200))
check "P6 of two rollouts of one directory the newest by modification time counts" "$(cdx_fields "$(snap)" Cdx)" "new-model 10 1m"

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
proc 100 T1 codex
rollout r1 "$T/code/elsewhere" gpt-x 100 1000 $((NOW - 60))
check "P7 a rollout of another directory is not used" "$(cdx_fields "$(snap)" Cdx)" "? ? ?"

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
proc 100 T1 codex
rollout r1 "$T/code/proj-b" gpt-x '' '' $((NOW - 60))
check "P8 a rollout with no token_count shows ? for the context" "$(val "$(agent "$(snap)" Cdx)" '.context')" "?"

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
proc 100 T1 codex
check "P9 with no rollout at all the row exists with ?" "$(cdx_fields "$(snap)" Cdx)" "? ? ?"

reset
WS=$T/code/proj
WS_DIR=$WS workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' '' T1)"
proc 100 T1 codex
rollout r1 "$WS" gpt-x 100 1000 $((NOW - 60))
check "P10 a codex terminal with no directory matches through the workspace's" "$(val "$(agent "$(snap)" Cdx)" '.context')" "10"

reset
workspace w1 "ProjA" "$(terminal Cdx codex running codex '' "$T/code/proj-b" T1)" "$(terminal Parado codex stopped codex '' "$T/code/proj-c" T2)"
proc 100 T1 codex
proc 101 T2 codex
chmod 000 "$PROC"/*/environ
out=$(snap); code=$?
check "P11 an unreadable /proc keeps today's selection and exit code 0" "$code $(val "$out" '[.projects[].agents[].name] | join(",")')" "0 Cdx"
chmod 644 "$PROC"/*/environ

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
proc 100 T1 codex
rollout r1 "$T/code/proj-b" gpt-x 100 1000 $((NOW - 60))
echo '{"OPENAI_API_KEY":"SECRET-OPENAI","tokens":{"access_token":"SECRET-ACCESS"}}' | tee "$T/codex/auth.json" "$CODEX/auth.json" "$CODEX/2026/11/05/auth.json" >/dev/null
check "P12 the fixture produced a row" "$(val "$(agent "$(snap)" Cdx)" '.model')" "gpt-x"
hasnt "P12 an auth.json with a secret leaves no value in the output" "$(snap; bash "$ROOT/bin/cockpit" --once 2>&1)" SECRET

before=$(sum_all); snap >/dev/null; bash "$ROOT/bin/cockpit" --once >/dev/null 2>&1; after=$(sum_all)
check "P13 the checksum of the test directories is unchanged after a round" "$after" "$before"

reset
WS=$T/code/proj
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex AAAA-EXEC "$WS" T1)"
proc 100 T1 codex
rollout wrong "$WS" wrong-model 100 1000 $((NOW - 60))
rollout right "$(roledir "$WS" AAAA-EXEC)" right-model 100 1000 $((NOW - 600))
check "P15 a codex terminal with a role matches through the role's directory" "$(val "$(agent "$(snap)" Cdx)" '.model')" "right-model"

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
note w1 board "Cdx · #184 · merged PR #187 · gpt · 3"
note w1 "for you" "# for you"
proc 100 T1 codex
rollout r1 "$T/code/proj-b" gpt-x 100 1000 $((NOW - 60))
out=$(snap)
check "P16 a codex agent with a merged board line is done and not counted as needing Jonatas" "$(val "$(agent "$out" Cdx)" '.status') $(val "$out" '.pending.total')" "done 0"

reset
workspace w1 "ProjA" "$(terminal Cus custom stopped 'env FOO=1 mytool --flag' '' "$T/code/proj-b" T1)"
proc 100 T1 mytool
check "P17 a custom terminal whose process carries the name of its own command gets a row with ?" "$(cdx_fields "$(snap)" Cus)" "? ? ?"

reset
workspace w1 "ProjA" "$(terminal Cus custom stopped 'a-very-long-command-name' '' "$T/code/proj-b" T1)"
proc 100 T1 a-very-long-com
check "P17 the own command word is cut to 15 characters as comm is" "$(cdx_fields "$(snap)" Cus)" "? ? ?"

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
proc 100 T1 codex
rollout user "$T/code/proj-b" user-model 100 1000 $((NOW - 600))
rollout guardian "$T/code/proj-b" codex-auto-review 100 1000 $((NOW - 60)) guardian_review
check "P18 a rollout with thread_source guardian_review is not used even when it is the newest" "$(val "$(agent "$(snap)" Cdx)" '.model')" "user-model"

reset
workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b/" T1)"
proc 100 T1 codex
rollout r1 "$T/code/proj-b" gpt-x 100 1000 $((NOW - 60))
check "P19 a codex terminal with a trailing slash in its directory matches the rollout" "$(val "$(agent "$(snap)" Cdx)" '.model')" "gpt-x"

reset
workspace w1 "ProjA" "$(terminal Cus custom stopped 'claude --model sonnet' '' "$T/code/proj-c/" T1)"
proc 100 T1 claude
session "$T/claude-a" s1 "$T/code/proj-c" busy $(( NOW * 1000 ))
check "P19 a claude terminal with a trailing slash in its directory matches the session" "$(val "$(agent "$(snap)" Cus)" '.status_text')" "trabalhando"

for order in "100 claude 101 codex" "100 codex 101 claude"; do
  set -- $order
  reset
  workspace w1 "ProjA" "$(terminal Aracati claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-a-1" T1)"
  proc "$1" T1 "$2"; proc "$3" T1 "$4"
  session "$T/claude-a" s1 "$CWD" busy $(( NOW * 1000 ))
  rollout r1 "$CWD" gpt-x 100 1000 $((NOW - 60))
  check "P20 a claude terminal with a codex child keeps the session data ($order)" "$(val "$(agent "$(snap)" Aracati)" '[.model, .status_text] | join(" ")')" "sonnet trabalhando"

  reset
  workspace w1 "ProjA" "$(terminal Cdx codex stopped codex '' "$T/code/proj-b" T1)"
  proc "$1" T1 "$2"; proc "$3" T1 "$4"
  session "$T/claude-a" s1 "$T/code/proj-b" busy $(( NOW * 1000 ))
  rollout r1 "$T/code/proj-b" gpt-x 100 1000 $((NOW - 60))
  check "P20 a codex terminal with a claude child keeps the rollout data ($order)" "$(val "$(agent "$(snap)" Cdx)" '[.model, .context] | join(" ")')" "gpt-x 10"
done
export COCKPIT_PROC_DIR="$T/no-proc"

GH_BIN=$T/gh-bin
GH_ANSWERS=$T/gh-answers
GH_LOG=$T/gh.log
export GH_ANSWERS GH_LOG
mkdir -p "$GH_BIN"
cat > "$GH_BIN/gh" <<'EOF'
#!/bin/bash
for a; do case "$a" in owner=*) owner=${a#owner=} ;; name=*) name=${a#name=} ;; esac; done
printf 'repo=%s/%s %s\n' "${owner:-}" "${name:-}" "$*" >> "$GH_LOG"
[ -f "$GH_ANSWERS/fail" ] && { echo boom >&2; exit 1; }
[ -f "$GH_ANSWERS/slow" ] && sleep 30
for a; do case "$a" in number=*) n=${a#number=} ;; esac; done
if [ -f "$GH_ANSWERS/$n.json" ]; then cat "$GH_ANSWERS/$n.json"; exit 0; fi
echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND"}]}'
exit 1
EOF
chmod +x "$GH_BIN/gh"

gissue() {
  jq -n --argjson n "$1" --arg t "$2" --arg b "$3" --argjson bl "${4:-[]}" --argjson lv "${5:-[]}" --arg s "${6:-OPEN}" \
    '{data:{repository:{issue:{number:$n,title:$t,body:$b,state:$s,repository:{nameWithOwner:"o/r"},subIssues:{nodes:$lv},blockedBy:{nodes:$bl}}}}}' > "$GH_ANSWERS/$1.json"
}
blocker() { jq -nc --argjson n "$1" --arg s "${2:-OPEN}" --arg r "${3:-o/r}" '{number:$n,state:$s,repository:{nameWithOwner:$r}}'; }
gleaf() {
  jq -nc --argjson n "$1" --arg t "$2" --arg b "$3" --argjson bl "${4:-[]}" \
    '{number:$n,title:$t,body:$b,state:"OPEN",repository:{nameWithOwner:"o/r"},blockedBy:{nodes:$bl}}'
}
round_ws() {
  reset
  rm -rf "$GH_ANSWERS" "$T/code/gh"
  mkdir -p "$GH_ANSWERS" "$T/code/gh"
  : > "$GH_LOG"
  git -C "$T/code/gh" init -q
  [ "${1:-}" = none ] || git -C "$T/code/gh" remote add origin "${1:-git@github.com:o/r.git}"
  WS_DIR=$T/code/gh one_agent Aracati
}
refresh() { PATH="$GH_BIN:$PATH" timeout 60 bash "$ROOT/bin/cockpit" --refresh-rounds >/dev/null 2>&1; }
item() { jq -c --arg t "$2" '.rounds[].items[] | select(.ticket == $t)' <<<"$1"; }
tickets() { val "$1" '[.rounds[].items[].ticket] | join(" ")'; }
page_at() { timeout 40 "$CHROME" --headless=new --disable-gpu --no-sandbox --user-data-dir="$T/profile" --window-size="$1,900" --virtual-time-budget="${2:-4000}" --dump-dom "http://127.0.0.1:$PORT/" 2>/dev/null | sed '/<script>/,/<\/script>/d'; }
gh_serve() { SERVE_PATH="$GH_BIN:$PATH" serve_start; }
edges() { grep -o '<path class="edge [a-z]*" data-from="[^"]*" data-to="[^"]*"' <<<"$1" | sed -E 's/<path class="edge ([a-z]*)" data-from="([^"]*)" data-to="([^"]*)"/\1 \2>\3/' | sort | tr '\n' ','; }
cards() { grep -o '<article class="card' <<<"$1" | wc -l; }

round_ws
note w1 round "# round" "" 'The manifest of the open round: a first line `round · <date>`, then `1. ENG-905 (leaf)`, `2. ENG-894 (parent, 4 leaves)`.' "" \
  "round · 2026-11-06" "mode: high autonomy" "1. #264 (leaf)" "2. #238 (parent, 5 leaves)" "3. #201 (leaf of #200)" "4. #204 (leaf of #200, blocked by #201)" "5. ENG-905 (leaf)" "" \
  "Jonatas asks for as much parallel work as the limit allows." "7. #999 (leaf)"
note w1 board "# board" "testes · https://x" "merge: Jonatas autorizou" "Jurema · #264 · implementing · sonnet · 1" "— · #204 · held behind #201 · opus · 5" \
  "Cunha · ENG-2173 PR A · merged · sonnet medium · 3" "Trado · ENG-2173 PR B · CI · opus medium · -" "Pua · #238/slug · reviewing · opus · 2" \
  "status 06/11 18:30 · round open · merged: ENG-1669"
out=$(snap)
check "R0 one rounds entry names the project and the round date" "$(val "$out" '[.rounds[] | .project + " " + .date] | join(",")')" "ProjA 2026-11-06"
check "R0 the manifest starts at the round line and free text after the list is ignored" "$(tickets "$out")" "#264 #201 #204 ENG-905 ENG-2173 PR A ENG-2173 PR B #238/slug"
check "R0 a board line gives state, executor, model and points" "$(val "$(item "$out" '#264')" '[.state, .executor, .model, .points] | join(" ")')" "implementando Jurema sonnet 1"
check "R0 a manifest parent is named" "$(val "$(item "$out" '#201')" '.parent')" "#200"
check "R0 a slug slice names its parent" "$(val "$(item "$out" '#238/slug')" '.parent')" "#238"
check "R0 a points field of - is no points" "$(val "$(item "$out" 'ENG-2173 PR B')" '.points')" "—"

reset
one_agent Aracati
note w1 board "#171/#184 · merged PR #1 · opus"
note w1 round "round · 2026-11-06" "1. #184 (leaf)"
check "R0 a board line with no codename names its ticket's slice" "$(val "$(item "$(snap)" '#184')" '[.state, .parent, .executor] | join(" ")')" "mergeado PR #1 #171 —"

round_ws
note w1 round "round · 2026-11-06" "1. #240 (leaf)" "2. #241 (leaf)"
gissue 240 "Título" "**Rule:** Regra 240." 
gissue 241 "Título" "**Rule:** Regra 241." "[$(blocker 240)]"
before=$(find "$T/maestri" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
refresh; snap >/dev/null
check "R1 a refresh and a snapshot leave the notes untouched" "$(find "$T/maestri" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)" "$before"
hasnt "R1 no gh call writes" "$(cat "$GH_LOG")" 'mutation\|issue \(edit\|comment\|close\)\|--method\|-X '
check "R0 the cache adds no account to the quotas" "$(val "$(snap)" '[.limits[].account] | join(",")')" "claude,codex"

: > "$GH_LOG"
out=$(PATH="$GH_BIN:$PATH" snap)
check "R2 --json does not call gh" "$(wc -l < "$GH_LOG")" 0
check "R2 --json reads the Rule from the cache" "$(val "$(item "$out" '#240')" '.rule')" "Regra 240."
touch "$GH_ANSWERS/slow"
gh_serve
for _ in $(seq 50); do [ -s "$GH_LOG" ] && break; sleep 0.1; done
has "R2 the server refreshes the cache by itself" "$(cat "$GH_LOG")" 'number=240'
start=$(date +%s%N)
code=$(code_of)
check "R2 a slow refresh does not delay the snapshot" "$code $(( ($(date +%s%N) - start) / 1000000000 < 4 ))" "200 1"
serve_stop
sleep 0.5
check "R2 nothing of a slow refresh survives the server" "$(pgrep -fc "$GH_BIN/gh")" 0
rm "$GH_ANSWERS/slow"

gissue 240 "Título" "**Rule:** Regra nova."
refresh
agents=$(val "$(snap)" '.projects')
touch "$GH_ANSWERS/fail"
refresh
out=$(snap)
check "R3 a failed refresh keeps the last data" "$(val "$(item "$out" '#240')" '.rule')" "Regra nova."
check "R3 a failed refresh marks it stale" "$(val "$out" '.rounds[0].stale')" true
check "R3 a failed refresh leaves the agents table alone" "$(val "$out" '.projects')" "$agents"
gh_serve
has "R3 the page marks stale data" "$(visible "$(page)")" 'GitHub desatualizado'
serve_stop
rm "$GH_ANSWERS/fail"
refresh
check "R3 the next good refresh clears the mark" "$(val "$(snap)" '.rounds[0].stale')" false
jq '.refreshed_at = 1' "$STATE/rounds/w1.json" > "$T/s.json" && mv "$T/s.json" "$STATE/rounds/w1.json"
check "R3 a cache nobody refreshed for long is stale" "$(val "$(snap)" '.rounds[0].stale')" true
echo 'not json' > "$STATE/rounds/w1.json"
out=$(snap)
check "R3 a broken cache leaves the agents table alone" "$(val "$out" '.projects')" "$agents"
check "R3 a broken cache keeps the panel, stale" "$(val "$out" '[(.rounds[0].items | length), .rounds[0].stale] | join(" ")')" "2 true"
rm "$STATE/rounds/w1.json"
touch "$GH_ANSWERS/fail"
refresh
out=$(snap)
check "R3 a first refresh that fails is stale with no Rule" "$(val "$out" '[.rounds[0].stale, .rounds[0].items[0].rule] | join(" ")')" "true "

round_ws
note w1 round "round · 2026-11-06" "1. #240 (leaf)" "2. #241 (leaf)" "3. #242 (leaf, blocked by #240)"
note w1 board "Jurema · #240 · implementing · sonnet · 1"
gissue 240 "Título" "**Rule:** Regra 240." "[]" "[]" CLOSED
gissue 241 "Título" "**Rule:** Regra 241." "[$(blocker 240)]"
gissue 242 "Título" "**Rule:** Regra 242."
refresh
out=$(snap)
check "R4 state comes from the board even when GitHub closed the ticket" "$(val "$(item "$out" '#240')" '.state')" "implementando"
check "R4 a board line that says the blocker is not merged keeps it open though GitHub closed it" "$(val "$(item "$out" '#241')" '.state')" "espera #240"
gh_serve
dom=$(page_at 1440)
check "R4 an arrow comes from GitHub, not from the manifest's list" "$(edges "$dom")" "open #240>#241,"
has "R4 the card shows the Rule" "$(visible "$dom")" 'Regra 241.'
serve_stop

round_ws
note w1 round "round · 2026-11-06" "1. #250 (leaf)" "2. #251 (leaf of #200, blocked by #250)" "3. #252 (leaf, blocked by #250)" "4. #253 (leaf, blocked by #254)" "5. #255 (leaf, blocked by #250, #254)"
note w1 board "# board"
out=$(snap)
check "R5 a manifest ticket with no board line reads Na fila" "$(val "$(item "$out" '#250')" '.state')" "Na fila"
check "R5 a blocked by in the manifest reads espera with GitHub out of reach" "$(val "$(item "$out" '#251')" '.state')" "espera #250"
check "R5 two open blockers both read in espera" "$(val "$(item "$out" '#255')" '.state')" "espera #250, #254"
note w1 board "Jurema · #250 · merged PR #9 · sonnet · 1"
check "R5 a merged blocker frees the ticket" "$(val "$(item "$(snap)" '#252')" '.state')" "Na fila"
gissue 253 "T" "**Rule:** R."
gissue 254 "T" "**Rule:** R." "[]" "[]" CLOSED
refresh
check "R5 a blocker off the board counts as GitHub says" "$(val "$(item "$(snap)" '#253')" '.state')" "Na fila"

round_ws
note w1 round "round · 2026-11-06" "1. #260 (leaf)"
gissue 260 "T" "**Rule:** R." "[$(blocker 261)]"
refresh
check "R5 a blocker only GitHub names is enough to wait" "$(val "$(item "$(snap)" '#260')" '.state')" "espera #261"

round_ws
note w1 round "round · 2026-11-06" "1. #200 (parent, 2 leaves)" "2. #201 (leaf of #200, blocked by #199)"
gissue 200 "Pai" "**Rule:** R." "[]" "[$(gleaf 201 F '**Rule:** R.'),$(gleaf 202 F '**Rule:** R.')]"
refresh
check "R5 a leaf also listed under its parent keeps its blocked by" "$(val "$(item "$(snap)" '#201')" '.state')" "espera #199"
note w1 round "round · 2026-11-06" "1. #201 (leaf of #200)" "2. #200 (parent, 2 leaves)"
gissue 200 "Pai" "**Rule:** R." "[$(blocker 150)]" "[$(gleaf 201 F '**Rule:** R.'),$(gleaf 202 F '**Rule:** R.')]"
gissue 201 "F" "**Rule:** R."
refresh
check "R5 a leaf listed before its parent keeps the parent's blocker" "$(val "$(item "$(snap)" '#201')" '.state')" "espera #150"

round_ws
note w1 round "round · 2026-11-06" "1. #1 (leaf)" "2. #2 (leaf)" "3. #3 (leaf)" "4. #4 (leaf)" "5. #5 (leaf)"
note w1 board "— · #1 · held behind PR #260 · opus · 5" "— · #2 · held behind #201 · opus · 5" "Facheiro · #3 · aguarda vaga · opus · 3" "Sisal · #4 · a decidir, pelo Jonatas · opus · 3" "Sisal · #5 · implementing · opus · 3"
out=$(snap)
check "R6 held behind PR #N reads espera PR #N" "$(val "$(item "$out" '#1')" '.state')" "espera PR #260"
check "R6 held behind #N reads espera #N" "$(val "$(item "$out" '#2')" '.state')" "espera #201"
check "R6 an unknown state appears as written" "$(val "$(item "$out" '#3')" '.state')" "aguarda vaga"
check "R6 an unknown state with text appears as written" "$(val "$(item "$out" '#4')" '.state')" "a decidir, pelo Jonatas"

round_ws
note w1 round "round · 2026-11-06" "1. #270 (leaf)" "2. #238 (parent, 2 leaves, blocked by #270)"
note w1 board "Jurema · #239 · implementing · sonnet · 1"
gissue 270 "T" "**Rule:** R."
gissue 238 "Pai" "**Rule:** Regra do pai." "[$(blocker 271)]" "[$(gleaf 239 'F' '**Rule:** Folha 239.'),$(gleaf 241 'F' '**Rule:** Folha 241.' "[$(blocker 239)]")]"
refresh
out=$(snap)
check "R7 a parent is not a node: its leaves are" "$(tickets "$out")" "#270 #239 #241"
check "R7 a leaf names its parent" "$(val "$(item "$out" '#241')" '.parent')" "#238"
check "R7 a leaf has its own Rule" "$(val "$(item "$out" '#239')" '.rule')" "Folha 239."
check "R7 a leaf waits on its own blocker and on its parent's, from the manifest and from GitHub" "$(val "$(item "$out" '#241')" '.state')" "espera #270, #239, #271"
gh_serve
dom=$(page_at 1440); text=$(visible "$dom")
has "R7 the leaf's arrow comes from the sub-issue" "$(edges "$dom")" 'open #239>#241,'
has "R7 the page names the parent" "$text" 'Pais: #238 (2 folhas)'
has "R7 the card names its parent" "$text" 'de #238'
serve_stop
rm "$STATE/rounds/w1.json"
out=$(snap)
check "R7 with no cache a parent is still no node" "$(tickets "$out")" "#270 #239"
check "R7 with no cache the panel still names the parent" "$(val "$out" '.rounds[0].parents[0] | .ticket + " " + (.leaves | tostring)')" "#238 2"

round_ws
note w1 round "round · 2026-11-06" "1. #204 (leaf of #200)" "2. #205 (leaf, blocked by #204)" "3. #238 (parent, 2 leaves)" "4. #206 (leaf)"
note w1 board "Jatobá · #204/banco · merged · opus · 2" "— · #204/telas · implementing · opus · 3" "Pua · #238 · reviewing · opus · 2" "Sisal · #206/extra · implementing · opus · 1"
out=$(snap)
check "R7 a leaf split into slug slices has no card of its own and no parent line of itself" "$(val "$out" '[.rounds[0].items[] | .ticket + " " + (.parent // "-")] | join(",")')" "#204/banco #200,#204/telas #200,#205 -,#206/extra -"
check "R7 a ticket waits while one slice of its blocker is not merged" "$(val "$(item "$out" '#205')" '.state')" "espera #204"

round_ws
note w1 round "round · 2026-11-06" "1. #280 (leaf)" "2. #281 (leaf)"
gissue 280 "Só o título" "**Context:** sem regra aqui."
gissue 281 "T" $'**Context:** algo.\r\n\r\n**Rule:** Regra com CRLF.\r\n\r\n**Risk:** baixo.'
refresh
out=$(snap)
check "R8 a ticket with no Rule line shows its title" "$(val "$(item "$out" '#280')" '.rule')" "Só o título"
check "R8 a Rule line ends at its line" "$(val "$(item "$out" '#281')" '.rule')" "Regra com CRLF."
gh_serve
has "R8 the card shows the title" "$(visible "$(page_at 1440)")" 'Só o título'
serve_stop

round_ws
note w1 round "round · 2026-11-06" "1. #290 (leaf)" "2. #291 (leaf)" "3. #292 (leaf)"
gissue 290 "T" "**Rule:** R." "[$(blocker 300)]"
gissue 291 "T" "**Rule:** R." "[$(blocker 290 OPEN x/y)]"
gissue 292 "T" "**Rule:** R."
note w1 board "Jurema · #290 · implementing · sonnet · 1"
refresh
out=$(snap)
check "R9 a blocker outside the manifest gives no node" "$(tickets "$out")" "#290 #291 #292"
gh_serve
dom=$(page_at 1440)
check "R9 a blocker outside the manifest has no arrow, and neither has a same number in another repository" "$(edges "$dom")" ""
has "R9 the blocker is text on the card" "$(visible "$dom")" 'implementando · Jurema · espera #300'
serve_stop

for form in https://github.com/o/r.git git@github.com:o/r ssh://git@github.com/o/r.git; do
  round_ws "$form"
  note w1 round "round · 2026-11-06" "1. #290 (leaf)"
  gissue 290 "T" "**Rule:** R."
  refresh
  has "R0 the remote $form names the repository" "$(cat "$GH_LOG")" '^repo=o/r '
done

round_ws
note w1 round "round · 2026-11-06" "1. #290 (leaf)" "2. #291 (leaf)"
gissue 290 "T" "**Rule:** R."
refresh
out=$(snap)
check "R0 an issue GitHub does not know is not a failure" "$(val "$out" '[.rounds[0].stale, (.rounds[0].items[0].rule)] | join(" ")')" "false R."

round_ws
note w1 round "round · 2026-11-06" "1. #240 (leaf)" "2. #241 (leaf)"
workspace w2 "ProjB" "$(terminal Outro claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-b")"
note w2 round "round · 2026-11-07" "1. #350 (leaf)"
workspace w3 "ProjC" "$(terminal Mais claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-c")"
note w3 round "# round" "" "(no round open)"
workspace w4 "ProjD" "$(terminal Fim claude_code running 'claude --model sonnet' AAAA-EXEC "$T/code/proj-d")"
note w4 round "round · 2026-11-01" "1. #9 (leaf)" "(no round open)"
rm -rf "$T/copy"; mkdir -p "$T/copy"; cp -r "$ROOT/bin" "$ROOT/templates" "$T/copy/"
sed -i 's|^refresh();$|refresh();\nlet probed = false;\nsetInterval(() => { const name = document.querySelector("#round .round-project")?.textContent; if (!name \|\| probed) return; probed = true; document.body.insertAdjacentHTML("beforeend", `<pre id="probe-first">${name} ${document.querySelector("#round button[data-move=\\"1\\"]").offsetHeight > 0}</pre>`); document.querySelector("#round button[data-move=\\"1\\"]").click(); setTimeout(() => document.body.insertAdjacentHTML("beforeend", `<pre id="probe-moved">${document.querySelector("#round .round-project").textContent}</pre>`), 6000); }, 50);|' "$T/copy/templates/cockpit.html"
check "R10 the panel moves only through projects with a manifest" "$(val "$(snap)" '[.rounds[].project] | join(",")')" "ProjA,ProjB"
ORIG_ROOT=$ROOT; ROOT=$T/copy
serve_start
for width in 1440 390; do
  dom=$(page_at "$width" 9000)
  has "R10 the page opens on the first project with its arrow in sight at $width" "$dom" '<pre id="probe-first">ProjA true'
  has "R10 the arrow moves to the next project and a refresh keeps it there at $width" "$dom" '<pre id="probe-moved">ProjB'
done
ROOT=$ORIG_ROOT
serve_stop

round_ws
note w1 round "round · 2026-11-06" "1. #240 (leaf)"
serve_start
hasnt "R10 with one manifest there is no arrow" "$(page)" 'data-move'
serve_stop

round_ws
note w1 round "# round" "" 'The manifest: a first line `round · <date>`, then lines.' "" "(no round open)"
check "R11 with no manifest rounds is empty" "$(val "$(snap)" '.rounds | length')" 0
for width in 1440 390; do
  serve_start
  dom=$(page_at "$width")
  check "R11 with no manifest anywhere the panel is one line at $width" "$(visible "$(grep -oP 'id="round">\K.*?(?=</section>)' <<<"$dom")")" ' Sem rodada aberta '
  serve_stop
done
note w1 round "round · 2026-11-06" "text only, no list"
check "R11 a round line with no list is no manifest" "$(val "$(snap)" '.rounds | length')" 0

round_ws
note w1 round "round · 2026-11-05" "1. ENG-1669 (leaf)" "2. ENG-2148 (parent, 18 leaves)" "3. ENG-2190 (leaf, blocked by ENG-1669)"
note w1 board "Trena · ENG-1669 · reviewing · sonnet low · 1" "Prego · ENG-2166 · merged · opus medium · 2"
refresh
out=$(snap)
check "R12 an ENG project calls no gh" "$(wc -l < "$GH_LOG")" 0
check "R12 an ENG ticket shows number, state and executor" "$(val "$(item "$out" 'ENG-1669')" '[.ticket, .state, .executor] | join(" ")')" "ENG-1669 revisando Trena"
check "R12 an ENG ticket has no Rule" "$(val "$(item "$out" 'ENG-1669')" '.rule')" "null"
check "R12 an ENG ticket waits on its manifest blocker" "$(val "$(item "$out" 'ENG-2190')" '.state')" "espera ENG-1669"
check "R12 an ENG leaf the board names is a node" "$(val "$(item "$out" 'ENG-2166')" '.state')" "mergeado"
serve_start
dom=$(page_at 1440)
check "R12 an ENG project has no arrows on the page" "$(edges "$dom")" ""
has "R12 an ENG project shows its cards" "$(visible "$dom")" 'ENG-1669'
serve_stop

round_ws none
note w1 round "round · 2026-11-06" "1. #240 (leaf)"
refresh
check "R12 a workspace with no GitHub remote calls no gh" "$(wc -l < "$GH_LOG")" 0
round_ws https://gitlab.com/o/r.git
note w1 round "round · 2026-11-06" "1. #240 (leaf)"
refresh
check "R12 a workspace with another host's remote calls no gh" "$(wc -l < "$GH_LOG")" 0

round_ws
XSS='<img src=x onerror=alert(1)>'
note w1 round "round · 2026-11-06" "1. #310 (leaf)" "2. #311 (leaf)"
note w1 board "$XSS · #310 · $XSS · $XSS · 1" "Sisal · #313 \"><img src=x> · implementing · opus · 1"
gissue 310 "T" "**Rule:** $XSS"
gissue 311 "$XSS" "sem regra" "[$(blocker 312 OPEN "$XSS")]"
refresh
gh_serve
dom=$(page_at 1440)
hasnt "R13 issue text never reaches the page as markup" "$dom" '<img'
has "R13 issue text is shown as text" "$dom" '&lt;img'
serve_stop

graph() {
  round_ws
  note w1 round "round · 2026-11-06" "1. #240 (leaf)" "2. #241 (leaf)" "3. #242 (leaf)" "4. #243 (leaf)" "5. #244 (leaf)" "6. #245 (leaf)" "7. #246 (leaf)"
  note w1 board "Jurema · #240 · implementing · sonnet · 1" "Cumaru · #241 · PR open · sonnet · 1" "— · #242 · held behind #241 · opus · 5" \
    "Facheiro · #243 · aguarda vaga · opus · 3" "Sisal · #244 · a decidir, ainda · opus · 3" "Marmeleiro · #246 · merged · sonnet · 2"
  gissue 240 "T" "**Rule:** Regra 240."
  gissue 241 "T" "**Rule:** Regra 241."
  gissue 242 "T" "**Rule:** Regra 242." "[$(blocker 241)]"
  gissue 243 "T" "**Rule:** Regra 243." "[$(blocker 246 CLOSED)]"
  gissue 244 "T" "**Rule:** Regra 244."
  gissue 245 "T" "**Rule:** Regra 245." "[$(blocker 242)]"
  gissue 246 "T" "**Rule:** Regra 246." "[]" "[]" CLOSED
  refresh
}
graph
gh_serve
dom=$(page_at 1440)
check "R14 what runs together is only a count and the numbers: in progress is board_step 1 to 6" "$(grep -oP '<p class="together">\K[^<]*' <<<"$dom")" '2 em andamento juntos: #240 + #241'
check "R15 at 1440 a blocker not merged has a dashed arrow, a merged one a solid arrow" "$(edges "$dom")" "merged #246>#243,open #241>#242,open #242>#245,"
dom=$(page_at 390)
check "R15 below 760 px there are no arrows" "$(edges "$dom")" ""
check "R15 below 760 px every card is there" "$(cards "$dom")" 7
has "R15 below 760 px a waiting card carries espera" "$(visible "$dom")" 'espera #241'
serve_stop

round_ws
note w1 round "round · 2026-11-06" "1. #240 (leaf)" "2. #241 (leaf)"
note w1 board "Jurema · #240 · implementing · sonnet · 1" "Cumaru · #241 · merged · sonnet · 1"
serve_start
hasnt "R14 one ticket running shows no together line" "$(visible "$(page)")" 'juntos'
serve_stop

round_ws
note w1 round "round · 2026-11-06" "1. #330 (leaf)" "2. #331 (leaf)" "3. #332 (leaf)" "4. #333 (leaf)" "5. #334 (leaf)"
gissue 330 "T" "**Rule:** R."
gissue 331 "T" "**Rule:** R." "[$(blocker 330)]"
gissue 332 "T" "**Rule:** R." "[$(blocker 331)]"
gissue 333 "T" "**Rule:** R." "[$(blocker 332)]"
gissue 334 "T" "**Rule:** R." "[$(blocker 333)]"
refresh
rm -rf "$T/copy"; mkdir -p "$T/copy"; cp -r "$ROOT/bin" "$ROOT/templates" "$T/copy/"
sed -i 's|^refresh();$|refresh();\nlet probed = false;\nsetInterval(() => { const box = document.querySelector(".graph-scroll"); if (probed \|\| !box) return; probed = true; box.scrollLeft = 40; setTimeout(() => document.body.insertAdjacentHTML("beforeend", `<pre id="probe-scroll">${document.querySelector(".graph-scroll").scrollLeft}</pre>`), 6000); }, 50);|' "$T/copy/templates/cockpit.html"
ORIG_ROOT=$ROOT; ROOT=$T/copy
serve_start
dom=$(page_at 800 9000)
ROOT=$ORIG_ROOT
serve_stop
check "R15 a refresh keeps the graph's sideways scroll" "$(grep -oP '<pre id="probe-scroll">\K[0-9]+' <<<"$dom")" 40

round_ws
note w1 round "round · 2026-11-06" "1. #320 (leaf)" "2. #321 (leaf)"
gissue 320 "T" "**Rule:** R." "[$(blocker 321)]"
gissue 321 "T" "**Rule:** R." "[$(blocker 320)]"
refresh
gh_serve
dom=$(page_at 1440)
check "R15 a blocker cycle stays inside the graph's columns" "$(grep -oP '\-\-columns:\K[0-9]+' <<<"$dom")" "$(( $(grep -oP 'data-depth="\K[0-9]+' <<<"$dom" | sort -n | tail -1) + 1 ))"
check "R15 a blocker cycle still draws every card" "$(cards "$(page_at 1440)")" 2
serve_stop

round_ws
note w1 round "round · 2026-11-06" "1. #240 (leaf)" "2. #241 (leaf)"
note w1 board "Jurema · #240 · implementing · sonnet · 1" "Cumaru · #240 · implementing · opus · 2" "Sisal · #241 · implementing"
gissue 240 "T" "**Rule:** R."
gissue 241 "T" "**Rule:** R." "[$(blocker 240)]"
refresh
gh_serve
dom=$(page_at 1440)
check "R15 two slices of one ticket each have their own arrow" "$(grep -oP '<path class="edge [^>]* d="\K[^"]*' <<<"$dom" | sort -u | wc -l)" 2
hasnt "R0 a board line with no model and no points shows neither" "$(visible "$dom")" '? pts'
serve_stop

graph
gh_serve
rm -rf "$T/copy"; mkdir -p "$T/copy"; cp -r "$ROOT/bin" "$ROOT/templates" "$T/copy/"
serve_stop
sed -i 's|^refresh();$|refresh();\nlet probed = false;\nsetInterval(() => { if (probed \|\| !document.querySelector("#round .card")) return; probed = true; setTimeout(() => document.body.insertAdjacentHTML("beforeend", `<pre id="probe-width">${Math.max(document.documentElement.scrollWidth, document.querySelector(".graph-scroll").scrollWidth)} ${Math.min(innerWidth, document.querySelector(".graph-scroll").clientWidth + 100000 * (document.querySelector(".graph-scroll").scrollWidth <= document.querySelector(".graph-scroll").clientWidth))}</pre><pre id="probe-together">${document.querySelector(".together").offsetHeight > 0}</pre><pre id="probe-indent">${getComputedStyle(document.querySelector(".card[data-depth=\\"2\\"]")).marginLeft}</pre>`), 300); }, 50);|' "$T/copy/templates/cockpit.html"
ORIG_ROOT=$ROOT; ROOT=$T/copy
SERVE_PATH="$GH_BIN:$PATH" serve_start
dom=$(page_at 390)
ROOT=$ORIG_ROOT
serve_stop
check "R14 at 390 the together line is in sight" "$(grep -oP '<pre id="probe-together">\K[^<]*' <<<"$dom")" true
check "R15 below 760 px a card indents by depth" "$(grep -oP '<pre id="probe-indent">\K[^<]*' <<<"$dom")" 32px
check "R15 below 760 px there is no sideways scroll" "$(grep -oP '<pre id="probe-width">\K[0-9]+ [0-9]+' <<<"$dom" | awk '{print ($1 <= $2) ? "fits" : $0}')" fits

check "S12 the --once output for the existing fixtures is unchanged" "$(cat "$T/once-changed")" ""

exit $failed
