def pydef -params 3 %{ eval %sh{
    file="$(mktemp)".py
    pyfifo="$file".pyfifo
    kakfifo="$file".kakfifo
    mkfifo "$pyfifo"
    mkfifo "$kakfifo"
    >$file printf "def line(stdin): %s\n" "$3"
    >>$file printf "while True:
        with open('%s', 'r', 1) as f:
            for s in f:
                try:
                    reply = line(s)
                except Exception as e:
                    reply = 'echo -debug %%~%s error: {}~'.format(e)
                with open('%s', 'w') as r:
                    r.write(reply)" "$pyfifo" "$1" "$kakfifo"
    (python $file) > /dev/null 2>&1 </dev/null &
    pypid=$!
    echo "
        def -override $1 %{
            echo -to-file $pyfifo \"$2\"
            eval %sh{ cat $kakfifo }
        }
        hook -group pydef global KakEnd .* %{ nop %sh{kill "$pypid"; rm -f "$file" "$pyfifo" "$kakfifo"} }
    "
} }

face global EasyMotionBackground rgb:aaaaaa
face global EasyMotionForeground red+b
face global EasyMotionSelected yellow+b

try %{
    decl range-specs em_fg
    decl str em_jumpchars abcdefghijklmnopqrstuvwxyz
    decl -hidden str _scrolloff
}

# e: forward, g: backward
def easy-motion-w -params 0..2 %{ easy-motion-on-regex '\b\w+\b' 'bGl' %arg{1} %arg{2} }
def easy-motion-W -params 0..2 %{ easy-motion-on-regex '\s\K\S+' 'bGl' %arg{1} %arg{2} }
def easy-motion-j -params 0..2 %{ easy-motion-on-regex '^[^\n]+$' 'bGl' %arg{1} %arg{2} }
def easy-motion-f -params 0..2 %{ on-key %{ easy-motion-on-regex "\Q%val{key}\E" 'bGl' %arg{1} %arg{2} } }

def easy-motion-b -params 0..2 %{ easy-motion-on-regex '\b\w+\b' 't' %arg{1} %arg{2} }
def easy-motion-B -params 0..2 %{ easy-motion-on-regex '\s\K\S+' 't' %arg{1} %arg{2} }
def easy-motion-k -params 0..2 %{ easy-motion-on-regex '^[^\n]+$' 't' %arg{1} %arg{2} }
def easy-motion-alt-f -params 0..2 %{ on-key %{ easy-motion-on-regex "\Q%val{key}\E" 't' %arg{1} %arg{2} } }

def easy-motion-word -params 0..2 %{ easy-motion-on-regex '\b\w+\b' 'bglGt' %arg{1} %arg{2} }
def easy-motion-WORD -params 0..2 %{ easy-motion-on-regex '\s\K\S+' 'bglGt' %arg{1} %arg{2} }
def easy-motion-line -params 0..2 %{ easy-motion-on-regex '^[^\n]+$' 'bglGt' %arg{1} %arg{2} }
def easy-motion-char -params 0..2 %{ on-key %{ easy-motion-on-regex "\Q%val{key}\E" 'bglGt' %arg{1} %arg{2} } }

def easy-motion-on-regex -params 1..4 %{
    set-option window _scrolloff %opt{scrolloff}
    set-option window scrolloff 0,0

    exec <space>G %arg{2} <a-\;>s %arg{1} <ret> ) <a-:>
    easy-motion-on-selections %arg{2} %arg{3} %arg{4}

    hook window -once ModeChange pop:.*:normal %{
        set-option window scrolloff %opt{_scrolloff}
    }
}

def _on_key -hidden -params .. %{
    on-key %{ eval %sh{
        while test $# -ge 2; do
            key=$1; shift
            cmd=$1; shift
            if test "$kak_key" = "$key"; then
                echo "$cmd"
                exit;
            fi
        done
        echo "$1"
    }}
}

pydef 'easy-motion-on-selections -params 0..3' '%opt{em_jumpchars}^%val{timestamp}^%arg{1}^%arg{2}^%arg{3}^%val{selections_desc}' %{
    jumpchars, timestamp, direction, callback_chosen, callback_cancel, descs = stdin.strip().split("^")
    if len(jumpchars) <= 1:
        return 'fail em_jumpchars needs length at least two'
    descs = descs.split(" ")
    from collections import OrderedDict, defaultdict
    jumpchars = list(OrderedDict.fromkeys(jumpchars))
    if direction == 't':
        descs.reverse()
    fg = timestamp
    jumps = []
    first = None
    cs = list(jumpchars)
    cs_set = set(cs)
    while len(cs) < len(descs):
        c = cs.pop(0)
        cs += [ c + c2 for c2 in jumpchars ]
        cs_set |= set(cs)
    d = {}
    fgs = defaultdict(lambda: 'set window em_fg ' + timestamp)
    def q(s):
        return "'" + s.replace("'", "''") + "'"
    for chars, desc in zip(cs, descs):
        a, h = desc.split(",")
        l, c = a.split(".")
        a2 = l + "." + str(int(c) + len(chars) - 1)
        fg += " " + q(a + "," + a2 + "|{EasyMotionForeground}" + chars)
        for i in range(1,len(chars)):
            chars_i = chars[:i]
            a1 = l + "." + str(int(c) + len(chars_i) - 1)
            a12 = l + "." + str(int(c) + len(chars_i))
            fgs[chars_i] += " " + q(a + "," + a1 + "|{EasyMotionSelected}" + chars_i)
            fgs[chars_i] += " " + q(a12 + "," + a2 + "|{EasyMotionForeground}" + chars[i:])
        d[chars] = "select " + desc + ';_easy-motion-rmhl;' + callback_chosen
        if first is None:
            first = a + "," + a
    def dfs(chars):
        if chars in d:
            return d[chars]
        out = ['_on_key']
        if chars:
            out = [fgs[chars] + ';' + out[0]]
        for c in jumpchars:
            chars_c = chars + c
            if chars_c not in cs_set:
                break
            out += [q(c), q(dfs(chars_c))]
        return ' '.join(out + [q(';_easy-motion-rmhl;' + callback_cancel)])
    return "\n".join((
        "select " + first,
        "_easy-motion-rmhl",
        "_easy-motion-addhl",
        "set window em_fg " + fg,
        dfs('')))
}

def -hidden _easy-motion-addhl %{
    try %{ addhl window/ fill EasyMotionBackground }
    try %{ addhl window/ replace-ranges em_fg }
}

def -hidden _easy-motion-rmhl %{
    rmhl window/fill_EasyMotionBackground
    rmhl window/replace-ranges_em_fg
}

# user modes can't have dash (yet)
try %{declare-user-mode easymotion}
map global easymotion f     ': easy-motion-f<ret>'     -docstring 'char →'
map global easymotion w     ': easy-motion-w<ret>'     -docstring 'word →'
map global easymotion W     ': easy-motion-W<ret>'     -docstring 'WORD →'
map global easymotion j     ': easy-motion-j<ret>'     -docstring 'line ↓'
map global easymotion <a-f> ': easy-motion-alt-f<ret>' -docstring 'char ←'
map global easymotion q     ': easy-motion-b<ret>'     -docstring 'word ←'
map global easymotion Q     ': easy-motion-B<ret>'     -docstring 'WORD ←'
map global easymotion k     ': easy-motion-k<ret>'     -docstring 'line ↑'
