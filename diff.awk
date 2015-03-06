#!/usr/bin/awk -f
BEGIN {
  RS="<tr[^>]*>"
  FS="<td[^>]*>"
  lines[""]=0
  lineno[""]=0
  lcnt=0
  pos[""]=0
  pos["1"]=""
  len[""]=0
  cnt=0
}
END {
  if( cnt ) {
    out=substr( FILENAME, 0, index( FILENAME, "__" )-1) 
    lineno[lcnt++]="@@ -" pos[1] "," len[1] " +" pos[2] "," len[2] " @@"
    lcnt=0
    print "--- " out ".work"
    print "+++ " FILENAME
    print lineno[lcnt++]
    for(i=0; i < cnt ;i++) {
      if( lines[i] == "lineno" ) {
        print lineno[lcnt++]
      } else {
        print lines[i]
      }
    }
  }
}

/diff-lineno/ {
  FS="<td colspan=\"2\" class=\"diff-lineno\">Zeile "
  $0=$0
  if( pos[1] != "" ) {
    lines[cnt++]="lineno"
    lineno[lcnt++]="@@ -" pos[1] "," len[1] " +" pos[2] "," len[2] " @@"
  }
  len[1]=0; len[2]=0
  pos[1]=substr( $2, 0, index( $2, ":" )-1 )
  pos[2]=substr( $3, 0, index( $3, ":" )-1 )
}

/<td class='diff-marker'>/ {
  FS="<td class='diff-marker'>"
  $0=$0
  for( i=2; i<=NF ;i++ ) {
    a=substr( $i, 0, 1 )
    s=substr( $i, 2 )
    gsub( /<\/tr>.*/, "", s )
    gsub( /<[^>]*>/, "", s )
    gsub( /&?#160;/, "", s )
    gsub( /&quot;/, "\"", s )
    gsub( /&lt;/, "<", s )
    gsub( /&gt;/, ">", s )
    gsub( /&amp;/, "\\&", s )

    if( a == "+" ) {
	if( $i ~ /<\/tr>/ ) {
	  len[2]++;
	} else {
	  len[1]++;
        }
        lines[cnt++]="+" s
    }
    if( a == "−" ) {
	len[1]++;
        lines[cnt++]="-" s
    }
    if( a == "&" ) {
      lines[cnt++]=" " s

      len[1]++;
      len[2]++;
      break
    }
  }
}
