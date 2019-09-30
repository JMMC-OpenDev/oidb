xquery version "3.0";

(:~
 : This module provides a REST API to read application status.
 :)
module namespace status="http://apps.jmmc.fr/exist/apps/oidb/restxq/status";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "../app.xql";
import module namespace backoffice="http://apps.jmmc.fr/exist/apps/oidb/backoffice" at "../backoffice.xql";

declare namespace rest="http://exquery.org/ns/restxq";


declare function status:pad-string-to-length
  ( $stringToPad as xs:string? ,
    $length as xs:integer )  as xs:string {
    let  $padChar := " "
   return substring(
     string-join (
       ($stringToPad, for $i in (1 to $length) return $padChar)
       ,'')
    ,1,$length)
 };
(:~
 : Get simple status fragment.
 : 
 : @return ignore, see HTTP status code
 :)
declare
    %rest:GET
    %rest:path("/oidb/status")
function status:status() {
    <status>
        {
            let $main-status := backoffice:main-status(<a/>,map:merge(()))
            let $padlenght := max( for $dt in $main-status//dt return string-length($dt)) +1
            let $summary-items := for $dt in $main-status//dt
                let $data := normalize-space(replace(data(($dt/following-sibling::dd)[1]),"&#160;"," "))
                return status:pad-string-to-length($dt,$padlenght)||"= "||$data
            let $summary := <summary>{ string-join(('',$summary-items,'','report-completed'), '&#10;') }</summary>
            return ($main-status, $summary)
        }
    </status>
};
