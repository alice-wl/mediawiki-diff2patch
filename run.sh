#!/usr/bin/env bash                                                                                                                              

# reads mediawiki feedreader dump 
# and creates patches

source vars.sh

PAGEID="$1"
#FORCEDL="true"

declare -A st
st=()

function fetch {
  p="$1";  url="$2"; d=`dirname "$p"`
  [[ -d "$d" ]] || mkdir -p "$d"

  [[ $FORCEDL || ! -f "${p}.fetch" ]] && curl -# --fail "${url}" \
    | recode h..latin1 \
    | perl -0pi -e 's,^.*<textarea [^>]*>(.*)</textarea>.*$,\1,s' \
    > "${p}.fetch"

  if [[ -f "${p}.fix" ]]; then cp "${p}.fix" "${p}.work"
  else 
    if grep -q '<span dir="auto">Anmeldung erforderlich</span>' "${p}.fetch"; then
        let st[fetch_fail]++
        echo "${p} -- ${url}" >> fetch.log
        echo "${url}<br />" >> "${p}.notfound"
    else
        let st[fetch]++
        cp "${p}.fetch" "${p}.work"
    fi
  fi
}

cat /dev/null > fetch.log
cat /dev/null > patch.log

[ -d out ] && find out -name '*.change' -exec rm {} \;
[ -d out ] && find out -name '*.work' -exec rm {} \;
[ -d out ] && find out -name '*.patch' -exec rm {} \;
[ -d out ] && find out -name '*.html' -exec rm {} \;
[ -d out ] && find out -name '*.orig' -exec rm {} \;
[ -d out ] && find out -name '*.rej' -exec rm {} \;
[ -d out ] && find out -name '*.notfound' -exec rm {} \;

rm -r intern/*
rm -r patch/*
rm -r html/*

while read i; do 
  url=`echo $i | cut -d '\`' -f 4`
  user=`echo $i | cut -d '\`' -f 13 | cut -d '-' -f1`
  date=`echo $i | cut -d '\`' -f 5`

  title=`echo $i | cut -d '\`' -f 2`
  n=`echo $url | perl -pe 's,.*?title=([^&]*).*,\1,'`   ## name in url format
  ts=`echo $date | sed -r 's/[^A-Za-z0-9]+//g' | sed -r 's/2014//'`  ## date shorter
  id=`echo $url | perl -pe 's,.*?diff=([^&]*).*,\1,'`   ## diff id
  od=`echo $url | perl -pe 's,.*?oldid=([^&]*).*,\1,'`   ## old id
  meta="__${ts}-${user}"
  p=""; o=""                                          ## path, workfile

  if [[ $LASTEDIT ]]; then
    [[ "$LASTEDIT" == "Vollkorn double edit" ]] && LASTEDIT="";
    [[ "$LASTEDIT" == "$date" ]] && LASTEDIT="Vollkorn double edit";
    continue
  fi

  [[ $PAGEID && "$n" != "${PAGEID}" ]] && continue

  if [[ "x$n" == "x" ]]; then
    let st[empty]++
    continue
  elif [[ "$n" == "Diskussion:"* ]]; then
    let st[discussion]++
    continue
  elif [[ "$n" == "Datei:"* ]]; then
    let st[discussion]++
    continue
  elif [[ $i == *"Weiterleitung nach"* ]]; then
    let st[forward]++
    continue
  elif [[ $i == *"lud"* ]]; then 
    let st[file]++
    continue
  elif [[ $i == *"wurde erstellt"* ]]; then 
    let st[user]++
    continue
  elif [[ $i == *"verschob Seite"* ]]; then 
    let st[move]++

    user=`echo $i | perl -pe 's,.*?Benutzer:([^"]*).*,\1,' | cut -d '-' -f1`

    n=`echo $i | perl -pe 's,.*verschob.*?title=([^&]*).*,\1,'`
    new=`echo $i | perl -pe 's,.* nach .*?"/intern/([^"]*).*,\1,'`
    p="out/${n}"; 
    t="out/${new}"

    #comment=`echo $i | perl -pe 's,.* nach .*?</a> ([^<]*).*,\1,'`
    #meta="__w__${date}-${user}-${comment}"

    o="${p}${meta}.move"

    [[ -f "${p}.work" || -f "${p}.notfound" ]] || fetch "$p" "$BASEURL${n}"
    [[ -f "${p}.notfound" ]] && {
      let st[notfound]++
      continue
      state="file_notfound"
      touch ${p}.work 
    }

    echo "$i" > "$o"

    d=`dirname "${t}"`
    [[ -d "$d" ]] || mkdir -p "$d"
    mv "${p}.work" "${t}.work"
    #mv "${p}.html" "${t}.html"
    p="${t}"
  elif [[ $i == *"löschte Seite"* ]]; then 
    let st[delete]++
    continue
  elif [[ $i == *"<b>Neue Seite</b>"* ]]; then
    let st[create]++

    p="out/${n}"
    o="${p}${meta}.create"
    d=`dirname "$p"`
    [[ -d "$d" ]] || mkdir -p "$d"

    echo "$i" | sed -f unesc.sed > "$o"
    cp "$o" "${p}.work"
  else
    let st[change]++

    p="out/${n}"
    o="${p}${meta}.change"

    comment=`echo $i | cut -d '\`' -f 6 | perl -pe 's,.*?>([^<]+)<.*,\1,' \
                  | tr -d "\n" | sed -f unesc.sed`
    state="ok"

    c=0;
    while [[ -f "${o}.patch" ]]; do
      (( c++ ))
      o="out/${n}${meta}-${c}.change"
    done;

    [[ -f "${p}.work" || -f "${p}.notfound" ]] || fetch "$p" "$BASEURL${n}"
    [[ -f "${p}.notfound" ]] && {
      let st[notfound]++
      continue
      state="file_notfound"
      touch ${p}.work 
    }

    d=`dirname "$o"`
    [[ -d "$d" ]] || mkdir -p "$d"
    echo "$i" | perl -0pi -e 's,^.*<table [^>]*>(.*)</table>.*$,\1,s' > "$o"
    ./diff.awk "$o" > "${o}.patch"

    [[ -s "${o}.patch" ]] &&
      patch -s -f -p0 < "${o}.patch" || { 
        let st[change_fail]++
        state="patch_failed"
        [[ -f "${p}.work.rej" ]] && mv "${p}.work.rej" "${o}.work.rej"
        [[ -f "${p}.work.orig" ]] && mv "${p}.work.orig" "${o}.work.orig"

        echo "-- ${o}.work.rej"
      }

    patch="patch/${n}__${od}-${id}__${date}__${comment}__${meta}-${state}.diff"
    d=`dirname "$patch"`
    [[ -d "$d" ]] || mkdir -p "$d"
    cat "${o}.patch" > "$patch"

    change="intern/${title}__${date}-${user}__${comment}__${state}.out"
    d=`dirname "$change"`
    [[ -d "$d" ]] || mkdir -p "$d"
    cat "${p}.work" > "$change"
    echo $change


    if [[ $state != "ok" ]]; then
      l="html/${title}__${date}-${user}__${comment}__${state}.html"
      d=`dirname "$l"`
      [[ -d "$d" ]] || mkdir -p "$d"
      echo "${HTMLSTART}" > "$l"
      echo "<table class='diff diff-contentalign-left'>" >> "$l"
      cat "${o}" >> "$l"
      echo "</table></body></html>" >> "$l"
    fi
  fi

done <<EOF
$( cat $FILE | sort -t '`' -k5 )
EOF

echo -----
for k in ${!st[@]}; do 
    echo $k ${st[$k]}
done

