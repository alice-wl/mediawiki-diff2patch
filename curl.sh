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
ask( ) { echo -ne "\033[30;47m>\033[0m ${@}\n" >&2; read r </dev/tty; echo $r; }
fail( ) { echo -ne "\033[35;47merror:\033[0m ${@}\n" >&2; exit 1; }

token( ) {
    $CURL --request "POST" \
          --data-urlencode "lgname=${USERNAME}" \
          --data-urlencode "lgpassword=${USERPASS}" \
          "${WIKIAPI}?action=login&format=json" \
        | sed -e 's/[{}"]/''/g' \
        | awk -v RS=, -F: ' \
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
          /result/ { print "login: " $3 } \
          /lgusername/ { print "hello " $2 }' \
      || return 1
}
edittoken( ) {
    ## mediawiki > 1.19
    #$CURL --request "POST" \
    #    "${WIKIAPI}?action=query&meta=tokens&format=json" \
    #  | sed -e 's/{/,/g' \
    #  | sed -e 's/[{}\\+"]//g' \
    #  | awk -v RS=, -F: ' \
    #    /csrftoken/ { print $2 }'
    ## mediawiki < 1.20
    $CURL --request "POST" \
        "${WIKIAPI}?action=query&prop=info|revisions&intoken=edit&titles=Hauptseite&format=json" \
      | sed -e 's/{/,/g' \
      | sed -e 's/[{}\\+"]//g' \
      | awk -v RS=, -F: ' \
        /edittoken/ { print $NF }'
}
push( ) {
    local t=$1
    [[ $t != "" ]] || fail edittokenfail

    local f=$2
    local n=${f##intern/}
    local p=`echo "$n" | awk -v RS=foo -F__ '{ print $1 }'`
    local m=`echo "$n" | awk -v RS=foo -F__ '{ print $2 }'`
    local c=`echo "$n" | awk -v RS=foo -F__ '{ print $3 }'`
    local s=`echo "$n" | awk -v RS=foo -F__ '{ print $4 }'`

    [[ $c == "" ]] || m="$m -- $c"
    [[ $s == "ok.out" ]] || m="$m -- ${s%%.out}"

    $CURL --request "POST" \
      --header "Expect:" \
      --form "title=${p}" \
      --form "summary=${m}" \
      --form "text=<${f}" \
      --form "token=${t}+\\" \
      "${WIKIAPI}?action=edit&format=json" \
        | sed -e 's/[{}"]/''/g' \
        | awk -v RS=, -F: ' \
          #{ print $0 > "/dev/stderr" } \
          /result/ { print $NF }'
}

source vars.sh

declare -A st; st=()
cols=$(echo $(tput cols)-10| bc )

filter="*"
[[ $1 ]] && filter="$1"

cat /dev/null > push.log

login || fail "login failed"
token=$(edittoken)

find intern -type f -name "${filter}.out" \
  | while read o; do
    [[ "${o:(-4)}" == ".out" ]] || continue  ### why?!
    [[ -f "${o}.done" ]] && continue

    p=`echo "$o" | awk -v RS=foo -F__ '{ print $1 }'`
    [[ -f "${p}.fail" ]] && continue

    if [[ $(push $token "$o") == "Success" ]]; then
      msg $(printf "push % -*s Success" $cols "$p" )
      cp "$o" "$o.done"
    else
      msg "fail: $o"
      cp "$o" "$p.fail"

      let st[fail]++
      #[[ $c$(ask "continue ...")  == "" ]] || exit

      echo "$o" >> push.log
    fi
done

echo -----
for k in ${!st[@]}; do 
    echo $k ${st[$k]}
done
