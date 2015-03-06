#!/usr/bin/env bash
 
CURL="curl -k -s -S \
        --location \
        --retry 2 \
        --retry-delay 5 \
        --cookie .mwcookie \
        --cookie-jar .mwcookie \
        --user-agent ntmrw_ai_at_m32.notomorrow.de \
        --keepalive-time 60 \
        --compressed"

msg( ) { echo -ne "\033[30;47m>\033[0m ${@}\n" >&2; }
fail( ) { echo -ne "\033[35;47merror:\033[0m ${@}\n" >&2; exit 1; }

token( ) {
    $CURL --request "POST" \
          --data-urlencode "lgname=${USERNAME}" \
          --data-urlencode "lgpassword=${USERPASS}" \
          "${WIKIAPI}?action=login&format=json" \
        | sed -e 's/[{}"]/''/g' \
        | awk -v RS=, -F: ' \
          { print > "/dev/stderr" } \
          /token/ { print $2 }' \
      || return 1
  
}
login( ) {
    t=$(token)
    $CURL --request "POST" \
          --data-urlencode "lgname=${USERNAME}" \
          --data-urlencode "lgpassword=${USERPASS}" \
          --data-urlencode "lgtoken=${t}" \
          "${WIKIAPI}?action=login&format=json" \
        | sed -e 's/[{}"]/''/g' \
        | awk -v RS=, -F: ' \
          { print > "/dev/stderr" } \
          /result/ { print "login: " $3 } \
          /lgusername/ { print "hello " $2 }' \
      || return 1
}
edittoken( ) {
    $CURL --request "POST" \
        "${WIKIAPI}?action=query&meta=tokens&format=json" \
      | sed -e 's/{/,/g' \
      | sed -e 's/[{}\\+"]//g' \
      | awk -v RS=, -F: ' \
        { print > "/dev/stderr" } \
        /csrftoken/ { print $2 }'
}
push( ) {
    t=$(edittoken)
    [[ $t != "" ]] || fail edittokenfail

    p=`basename "$1" | awk -v RS=foo -F__ '{ print $1 }'`
    m=`echo "$1" | awk -v RS=foo -F__ '{ print $2 }'`
    c=`echo "$1" | awk -v RS=foo -F__ '{ print $3 }'`
    s=`echo "$1" | awk -v RS=foo -F__ '{ print $4 }'`
    [[ $c == "" ]] || m="$m -- $c"
    [[ $s == "ok.out" ]] || m="$m -- ${s%%.out}"

    r=$( $CURL --request "POST" \
      --header "Expect:" \
      --form "title=${p}" \
      --form "summary=${m}" \
      --form "text=<${o}" \
      --form "token=${t}+\\" \
      "${WIKIAPI}?action=edit&format=json" \
        | sed -e 's/[{}"]/''/g' \
        | awk -v RS=, -F: ' \
          { print > "/dev/stderr" } \
          /result/ { print $3 }' )
    msg $(printf "create %-60s %s\n" $p $r)

    [[ $r == "Success" ]] || echo "$1" >> push.log
}

source vars.sh

login || fail "login failed"
[[ $1 ]] || fail "usage: $0 pathtofiles"
[[ -d "$1" ]] || fail "path not found"

find "$1" -print0 -name '*.out' | while read -d $'\0' o; do
  [[ "$o" != "intern" ]] || continue
  push "$o"
done;

