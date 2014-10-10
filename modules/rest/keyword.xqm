xquery version "3.0";

(:~
 : This module provides a REST API for querying the collection of keywords.
 :)
module namespace kw="http://apps.jmmc.fr/exist/apps/oidb/restxq/keyword";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";

declare namespace rest="http://exquery.org/ns/restxq";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

(:~
 : The path to the keyword collection.
 :)
declare variable $kw:keywords-uri := $config:data-root || '/keywords';

(:~
 : Return as JSON a list of keywords matching a query or all.
 : 
 : @param $q the pattern to search in keywords
 : @return a JavaScript array of keywords
 :)
declare
    %rest:GET
    %rest:path("/oidb/keyword")
    %rest:query-param("q", "{$q}")
    %output:method("text")
    %output:media-type("application/json")
function kw:list($q as xs:string*) as xs:string {
    let $all := collection($kw:keywords-uri)//keyword
    let $keywords := if (exists($q)) then
            $all[contains(upper-case(.), upper-case($q))]/text()
        else
            $all/text()
    (: reformat sequence as JavaScript array :)
    return concat(
        "[",
        string-join(for $kw in $keywords return '"' || $kw || '"', ','),
        "]")
};
