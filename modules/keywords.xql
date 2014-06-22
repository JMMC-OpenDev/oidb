xquery version "3.0";

(:~
 : Return as JSON a list of keywords.
 : 
 : Parameter 'search' is the pattern to find in keywords.
 :)

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "application/json";

let $search := request:get-parameter("search", "")

let $keywords := collection($config:data-root || '/keywords')//keyword[contains(upper-case(.), upper-case($search))]/text()

(: reformat sequence to JavaScript array :)
return concat(
    "[",
    string-join(for $kw in $keywords return '"' || $kw || '"', ','),
    "]")
