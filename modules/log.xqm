xquery version "3.0";

module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log";

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at 'config.xqm';
import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth" at "/db/apps/jmmc-resources/content/jmmc-auth.xql" ;

declare variable $log:downloads := $config:data-root || '/log/downloads.xml';
declare variable $log:searches := $config:data-root || '/log/searches.xml';
declare variable $log:submits := $config:data-root || '/log/submits.xml';
declare variable $log:visits := $config:data-root || '/log/visits.xml'; (: This may be disabled in the futur if nb of records is too much :)

declare variable $log:files := ( $log:downloads, $log:searches, $log:submits, $log:visits );

(: Notes : Records should have success or error to help quick stat computation,  user IP :)

(:~
 : Check log files and create them if not present.
 : 
 : @return the status of log files.
 :)
declare function log:check-files() {
    <table class="table table-condensed">
    {
        for $f in $log:files
            let $doc := util:document-name($f) (: document-name can be empty if doc does not exist:)
            let $doc := if($doc) then $doc else tokenize($f, "/")[last()]
            let $col := util:collection-name($f)
            let $doc-available := doc-available($f)
            let $error-msg := if ( $doc-available ) then () else
                " missing file, please create ( xmldb:store( &quot;" || $col || "&quot;, &quot;"|| $doc || "&quot;, &lt;" || substring-before($doc,'.') || "/&gt;) )"
            let $class := if ($doc-available) then "success" else "danger"
            let $stats := if ($doc-available) then <span> <i class="glyphicon glyphicon-ok"/>&#160;{count(doc($f)//success)} - <i class="glyphicon glyphicon-remove"/>&#160;{count(doc($f)//error)} </span> else ()
            return 
                <tr class="{$class}"><td><span rel="tooltip" title="{$f}">{$doc}</span></td><td>{$error-msg}</td> <td>{$stats}</td></tr>
    }
    </table>
};

(:~
 : Add a message to a given log file.
 : 
 : It adds a timestamp, as well as the username and remote info if a request
 : object is available and the data is missing from the message.
 : 
 : @param $log     the log URI
 : @param $message the message to save as an element
 : @return empty value
 :)
declare %private function log:log($log as xs:string, $message as element()) {
    (: automatically add missing bits to the log message :)
    let $message := element { name($message) } {
        if ($message/@time) then () else attribute { 'time' } { current-dateTime() },
        if (request:exists()) then
            (: HTTP interaction, extract data from request object if missing from message :)
            (
                if ($message/@session)   then () else attribute { 'session' }   { session:get-id() },
                if ($message/@user)   then () else attribute { 'user' }   { request:get-attribute('fr.jmmc.oidb.login.user') },
                (: prefer XFF because ProxyPass makes request:get-remote-host() always returns localhost :)
                if ($message/@remote) then () else attribute { 'remote' } { ( request:get-header("X-Forwarded-For"), request:get-remote-host())[1] }
            )
        else
            (),
        $message/@*,
        $message/*
    }
    return update insert $message into doc($log)/*
};

(:~
 : Turn the request parameters into a <request> element for logging.
 : 
 : @return a <request> element
 :)
declare %private function log:serialize-request() as element() {
    <request> {
        for $n in request:get-parameter-names()
        return element { $n } { request:get-parameter($n, '') }
    } </request>
};

(:~
 : Add an element to the download log detailing the request parameters and the
 : response.
 : 
 : @param $granuleid
 : @param $url
 : @return empty value
 :)
declare function log:get-data($granuleid as xs:integer, $url as xs:string?) {
    let $message := <download>
        { log:serialize-request() }
        { if ($url) then (element {"url"} {$url},<success/>) else <error>no-data</error> }
    </download>
    return log:log($log:downloads, $message)
};
(:~
 : Add an element to the search log detailing the request parameters of searches
 : @param $info optional information fragments to store into the record
 : @return empty value
 :)
declare function log:search($info as node()*) {
    let $message := <search>
                        { log:serialize-request() }
                        { $info }
                    </search>
    return log:log($log:searches, $message)
};

(:~
 : Add an element to the search log detailing a visit to a given path.
 : Called by the controller.xql
 : @param path point to the page resource requested
 : @param $info optional information fragments to store into the record
 : @return empty value
 :)
declare function log:visit($node as node(), $model as map(*)) {
    let $message := <visit>
                        (: FIXME this attribute is not present even if an error occurs :)
                        {if (request:get-attribute("oidb-failed")) then <error/> else <success/>}
                        <path>{request:get-attribute("exist:path")}</path>
                    </visit>
    return log:log($log:visits, $message)
};

(:~
 : Add an event to the submits log.
 : 
 : @param $request
 : @param $response
 : @return empty
 :)
declare function log:submit($request as node()?, $response as node()) {
    log:log($log:submits, <submit>{ $request, $response }</submit>)
};

(:~
 : Add an event to the submits log.
 : 
 : If a request object is available, it tries to serialize its parameters into
 : a <request> element.
 : 
 : @param $response
 : @return empty
 :)
declare function log:submit($response as node()) {
    let $request := if (request:exists()) then log:serialize-request() else ()
    return log:submit($request, $response)
};

declare %private function log:report-submits($max as xs:integer, $successful as xs:boolean)as node()*{
    let $thead := <tr><th>Date</th><th>#Stored granules</th><th>Method</th><th>Submit by</th></tr>
    let $nbCols := count($thead//th)
    let $submits := if($successful) then doc($log:submits)//submit[.//success] else doc($log:submits)//submit[.//error]
    let $items := subsequence(reverse($submits),1,$max)
    let $trs := for $item in $items
        let $time := data($item/@time)
        let $success := if( $item//success ) then true() else false()
        let $class := if( $success ) then "success" else "danger"
        let $by := if ($item/@user) then jmmc-auth:get-obfuscated-email($item/@user) else ''
        let $granulesOk := count($item//id)
        let $method := if($item//file) then "xml" else if ($item//urls) then "Oifits uploads" else "VizieR"
        return (
            <tr class="{$class}"> <td>{$time}</td> <td>{$granulesOk}</td> <td>{$method}</td> <td>{$by}</td> </tr>,
            if($success) then ()  else <tr class="{$class}"> <td colspan="{$nbCols}"> <ol>{for $e in $item//error return <li>{data($e)} {let $url := data($e/@url) return if($url) then <a href="{data($url)}">({data($url)})</a> else ()}</li>}</ol> </td> </tr>
        )
    return (<h4>{if($successful) then "Successful" else "Failed"} submits ({count($items)} over {count($submits)})</h4>,<table class="table table-condensed">{$thead,$trs}</table>)
};
(:~
 : Generate a report on last recorded submissions
 :  TODO improve presentation and various cases coverage 
 : (mixed valid/invalid granules, link to a popup that give more info in a modal window...)
 : 
 : @param $max define the max number of record to report
 : @return ignore
 :)
declare function log:report-submits($max as xs:integer)as node(){
    <div>
        {log:report-submits($max, true())}
        {log:report-submits($max, false())}
    </div>
};

(:~
 : Generate a report with statistics on dowloaded granules
 : 
 : @param $max define the max number of record to report (10 by default)
 : @return ignore
 :)
declare function log:report-downloads($max as xs:integer)as node(){
    let $thead := <tr><th>Date</th><th>#Granules</th><th>Url</th><th>Downloaded by</th></tr>
    let $nbCols := count($thead//th)
    let $downloads := doc($log:downloads)//download
    let $items := subsequence(reverse($downloads),1,$max)
    let $trs := for $item in $items
        let $time := data($item/@time)
        let $success := if( $item//success ) then true() else false()
        let $class := if( $success ) then "success" else "danger"
        let $by := jmmc-auth:get-obfuscated-email($item/@user)
        let $id := data($item//id)
        let $url := if( $success ) then data($item//url) else ()
        return (
            <tr class="{$class}"> <td>{$time}</td> <td><a href="show.html?id={$id}">{$id}</a></td> <td>{$url}</td> <td>{$by}</td> </tr>,
            if($success) then ()  else <tr class="{$class}"> <td colspan="{$nbCols}"> TBD </td> </tr>)
            
    let $last-by-date := <table class="table table-condensed">{$thead,$trs}</table>
    
    let $last-by-count := <table class="table table-condensed">
        <tr><th>Ids</th><th>#Downloads (#Anonymous)</th><th>#Distinct users</th></tr>
        {subsequence(for $d in doc($log:downloads)//download
                            group by $id := $d//id
                            order by count($d) descending
                            return 
                                <tr>
                                    <td><a href="show.html?id={$id}">{$id}</a></td>
                                    <td>{count($d)}({count($d//@user[.=""])})</td>
                                    <td>{count(distinct-values($d/@user))-1}</td>
                                </tr>
                                , 1, $max)
        }</table>
    
    return
    <div>
        <h4>{$max} last downloads</h4> {$last-by-date}
        <h4>{$max} last most requested granules</h4>
        <dl class="dl-horizontal">{$last-by-count}</dl>
    </div>
};
(:~
 : Generate a report with statistics on searches
 : 
 : @param $max define the max number of record to report (10 by default)
 : @return ignore
 :)
declare function log:report-searches($max as xs:integer)as node(){
    let $searches := doc($log:searches)//search
    let $items := subsequence(reverse($searches),1,$max)
    return
    <div>
        {count($searches)} Requests ({count($searches//error)} failed ).  More details to come in the futur...
    </div>
};

(:~
 : Generate a report with statistics on visits
 : 
 : @param $max define the max number of record to report (10 by default)
 : @return ignore
 :)
declare function log:report-visits($max as xs:integer)as node(){
    let $visits := doc($log:visits)//visit
    let $items := subsequence(reverse($visits),1,$max)
    return
    <div>
        {count($visits)} Requests ({count($visits//error)} failed ).  More details to come in the futur...
    </div>
};
