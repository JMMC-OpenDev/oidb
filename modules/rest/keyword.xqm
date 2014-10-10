xquery version "3.0";

(:~
 : This module provides a REST API for querying the collection of keywords.
 :)
module namespace kw="http://apps.jmmc.fr/exist/apps/oidb/restxq/keyword";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";

declare namespace rest="http://exquery.org/ns/restxq";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace json="http://www.json.org";

(:~
 : The path to the keyword collection.
 :)
declare variable $kw:keywords-uri := $config:data-root || '/keywords';

(:~
 : Return as a JSON array a list of keywords matching a query or all keywords.
 : 
 : @param $q the pattern to search in keywords
 : @return a JavaScript array of keywords (after JSON serialization)
 :)
declare
    %rest:GET
    %rest:path("/oidb/keyword")
    %rest:query-param("q", "{$q}")
    %output:method("json")
function kw:list($q as xs:string*) {
    let $all := collection($kw:keywords-uri)//keyword
    let $keywords := if (exists($q)) then
            $all[contains(upper-case(.), upper-case($q))]
        else
            $all
    (: prepare for serialization as JavaScript array :)
    return <keywords> {
        for $kw in $keywords
        return <json:value>{ $kw/text() }</json:value>
    } </keywords>
};
