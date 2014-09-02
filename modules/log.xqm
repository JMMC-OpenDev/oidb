xquery version "3.0";

module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log";

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at 'config.xqm';
import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth" at "/db/apps/jmmc-resources/content/jmmc-auth.xql" ;

declare variable $log:submits := $config:data-root || '/log/submits.xml';

(:~
 : Add an element to the submits log detailing the request parameters and the
 : response.
 : 
 : @param $response
 : @return ignore
 :)
declare function log:submit($response as node()) {
    update
        insert
            <submit time="{ current-dateTime() }" user="{ request:get-attribute('user') }">
                <request> {
                    for $n in request:get-parameter-names()
                    return element { $n } { request:get-parameter($n, '') }
                } </request>
                { $response }
            </submit>
        into doc($log:submits)/submits
};

(:~
 : Generate a report on last recorded submissions
 :  TODO improve presentation and various cases coverage 
 : (mixed valid/invalid granules, link to a popup that give more info in a modal window...)
 : 
 : @param $maxcount define the max number of record to report (10 by default)
 : @return ignore
 :)
declare function log:report($max as xs:integer)as node(){
    let $thead := <tr><th>Date</th><th>#Granules</th><th>Method</th><th>Submit by</th></tr>
    let $nbCols := count($thead//th)
    let $items := subsequence(reverse(doc($log:submits)//submit),1,$max)
    let $trs := for $item in $items
        let $time := data($item/@time)
        let $success := if( $item//success ) then true() else false()
        let $class := if( $success ) then "success" else "danger"
        let $by := jmmc-auth:getObfuscatedEmail($item/@user)
        let $granulesOk := count($item//id)
        let $method := if($item//file) then "xml" else if ($item//urls) then "Oifits uploads" else "VizieR"
        return (
            <tr class="{$class}"> <td>{$time}</td> <td>{$granulesOk}</td> <td>{$method}</td> <td>{$by}</td> </tr>,
            if($success) then ()  else <tr class="{$class}"> <td colspan="{$nbCols}"> <ol>{for $e in $item//error return <li>{data($e)} {let $url := data($e/@url) return if($url) then <a href="{data($url)}">({data($url)})</a> else ()}</li>}</ol> </td> </tr>
        )
    return 
    <div>
        <table class="table table-condensed">
            {$thead,$trs}
        </table>
    </div>
};