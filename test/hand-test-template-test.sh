#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME=$(command -v google-chrome || command -v google-chrome-stable || command -v chromium) || { echo "red: needs Google Chrome"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

sed -e 's|^<script>$|<script src="setup.js"></script>\n<script>|' -e 's|</body>|<script src="assert.js"></script></body>|' "$ROOT/templates/hand-test.html" > "$T/page.html"
cat > "$T/setup.js" <<'JS'
(function(){
  var s=document.getElementById("eng-0000"), c=s.cloneNode(true);
  c.id="eng-0001"; s.after(c);
  var e=s.cloneNode(true); e.id="eng-0002"; e.querySelector("ol").innerHTML=""; c.after(e);
  var a=document.querySelector('nav.toc a[href="#eng-0000"]'), b=a.cloneNode(true), d=a.cloneNode(true);
  b.href="#eng-0001"; b.textContent="2 · App #M outro título"; a.after(b);
  d.href="#eng-0002"; d.textContent="3 · App #K sem passos"; b.after(d);
})();
JS
cat > "$T/assert.js" <<'JS'
(function(){
  var out=[];
  function check(name,cond){out.push((cond?"RESULT ok    ":"RESULT FAIL  ")+name)}
  function link(id){return document.querySelector('nav.toc a[href="#'+id+'"]').textContent.trim()}
  function boxes(id){return [].slice.call(document.querySelectorAll('#'+id+' input[type=checkbox]'))}
  function ticked(id){return /✓$/.test(link(id))}
  if(location.search==="?phase=fresh"){
    check("fresh page shows no check in the sidebar", !ticked("eng-0000") && !ticked("eng-0001"));
    check("a section without steps shows no check", !ticked("eng-0002"));
    boxes("eng-0000").forEach(function(b){b.click()});
    check("every step ticked puts a check on that section's sidebar entry", ticked("eng-0000"));
    check("the other section stays without a check", !ticked("eng-0001"));
    boxes("eng-0000")[1].click();
    check("unticking one step removes the check", !ticked("eng-0000"));
    boxes("eng-0000")[1].click();
    document.getElementById("reset").click();
    check("Desmarcar tudo removes the check", !ticked("eng-0000"));
    boxes("eng-0000").forEach(function(b){b.click()});
  }else{
    check("the check survives a reload", ticked("eng-0000") && !ticked("eng-0001"));
  }
  var pre=document.createElement("pre"); pre.textContent=out.join("\n"); document.body.appendChild(pre);
})();
JS

run() { "$CHROME" --headless=new --disable-gpu --no-sandbox --user-data-dir="$T/profile" --dump-dom "file://$T/page.html?phase=$1" 2>/dev/null | grep -o 'RESULT [^<]*'; }
results="$(run fresh; run reload)"
printf '%s\n' "$results" | sed 's/^RESULT //'
if [ "$(printf '%s\n' "$results" | wc -l)" = 7 ] && ! printf '%s\n' "$results" | grep -q FAIL; then echo "all green"; else echo "red"; exit 1; fi
