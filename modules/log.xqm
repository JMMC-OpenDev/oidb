xquery version "3.0";

module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log";

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at 'config.xqm';
import module namespace comments="http://apps.jmmc.fr/exist/apps/oidb/comments" at 'comments.xql';
import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth" at "/db/apps/jmmc-resources/content/jmmc-auth.xql" ;

declare variable $log:downloads := $config:data-root || '/log/downloads.xml';
declare variable $log:searches := $config:data-root || '/log/searches.xml';
declare variable $log:submits := $config:data-root || '/log/submits.xml';
declare variable $log:visits := $config:data-root || '/log/visits.xml'; (: This may be disabled in the futur if nb of records is too much :)

declare variable $log:files := ( $log:downloads, $log:searches, $log:submits, $log:visits, $comments:comments );

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
            let $stats := if ($doc-available) then <span> <i class="glyphicon glyphicon-ok"/>&#160;{count(doc($f)//success)}&#160;-&#160;<i class="glyphicon glyphicon-remove"/>{count(doc($f)//error)}&#160;</span> else ()
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
                if ($message/@user)   then () else attribute { 'user' }   { 
                    let $user := request:get-attribute('fr.jmmc.oidb.login.user')
                    (: throw a NPE (fixed on git but not released) let $user := if($user) then $user else data(sm:id()//*:real/*:username)  sm:id is use for scheduled jobs with setuid :)
                    let $user := if($user) then $user else xmldb:get-current-user()
                    return $user
                    },
                (: prefer XFF because ProxyPass makes request:get-remote-host() always returns localhost :)
                if ($message/@remote) then () else attribute { 'remote' } { request:get-remote-host() }
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
        let $v := if ($n = 'password') then 'XX' else request:get-parameter($n, '')
        return element { $n } { $v }
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
 : Add an event to the visit log.
 : 
 : The payload is built from the request and the possible error message.
 : 
 : @return empty
 :)
declare function log:visit() as empty() {
    let $message := <visit path="{ request:get-attribute("exist:path") }"> {
            log:serialize-request(),
            let $error := request:get-attribute("org.exist.forward.error")
            return if ($error) then
                <error>{ try { util:parse($error)//message/string() } catch * { $error } } </error>
            else
                <success/>
        } </visit>
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
    let $submits := if($successful) then doc($log:submits)//submit[.//success] else doc($log:submits)//submit[.//error or .//warning]
    let $items := subsequence(reverse($submits),1,$max)
    let $trs := for $item in $items
        let $time := data($item/@time)
        let $time := if($item//info) then  <span>{$time} <br/>({data($item//info)})</span> else $time 
        let $errors := count($item//error)
        let $warnings := count($item//warning)
        let $success := ($errors+$warnings) = 0
        let $class := if( $success ) then "success" else if( $item//warning) then "warning" else "danger"
        let $by := if ($item/@user) then jmmc-auth:get-obfuscated-email($item/@user) else ''
        let $granulesOk := count($item//id) + (xs:int($item//granuleOkCount),0)[1] 
        let $method := if($item//method) then data($item//method) else if($item//file) then "xml" else if ($item//urls) then "Oifits uploads" else "VizieR"
        return (
            <tr class="{$class}"> <td>{$time}</td> <td>{$granulesOk} / {$errors} errors / {$warnings} warnings</td> <td>{$method}</td> <td>{$by}</td> </tr>,
            if($success) then ()  else <tr class="{$class}"> <td colspan="{$nbCols}"> 
            <ol>{for $e in $item//error return <li>{data($e)} {let $url := data($e/@url) return if($url) then <a href="{data($url)}">({data($url)})</a> else ()}</li>}</ol>
            
            { 
                let $unknown-targets := for $e in $item//warning let $v := substring-after($e, "target:") return if($v) then <a>{$v}</a> else ()
                let $unknown-modes := for $e in $item//warning let $v := substring-after($e, "mode:") return if($v) then <a>{$v}</a> else ()
                return
                    <ul>
                        <li>
                            {
                                let $str := string-join( for $e in $unknown-targets group by $v := $e/text()    return count($e) || " " ||$v ," , ") 
                                return if ($str) then "Unknown targets : "|| $str else ()
                            }
                        </li>
                        <li>
                            {
                                let $str := string-join( for $e in $unknown-modes group by $v := $e/text()    return count($e) || " " ||$v ," , ") 
                                return if ($str) then "Unknown modes : "|| $str else ()
                            }
                        </li>
                    </ul>
            }
            
            <ol>
                {for $e in $item//warning return <li>{data($e)} {let $url := data($e/@url) return if($url) then <a href="{data($url)}">({data($url)})</a> else ()}</li>}</ol>
            </td> </tr>
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
 : @todo 
 :   remove duplicated logs ( searches.xml now duplicates visit.xml )
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
        <!--
            <search time="2014-12-21T19:32:07.498+01:00" session="r376gqfgfizvriglp435r81k" user="" remote="127.0.0.1">
            <request>
                <order>instrument_name</order>
                <wavelengthband>mid-ir,B</wavelengthband>
                <perpage>25</perpage>
            </request>
            <success/>
            </search>   
            -->
    </div>
};

(:~
 : Generate a report with statistics on visits
 : 
 : @param $max define the max number of record to report
 : @return ignore
 :)
declare function log:report-visits($max as xs:integer)
as node()
{
    let $visits := subsequence(doc($log:visits)//visit,1,$max)
    let $total-hits := count($visits)
    let $items := subsequence(reverse($visits),1,$max)
    let $sessions := <sessions>
                    { 
                        for $visit in $visits group by $session:=$visit/@session/string() return 
                            <session>
                                <visit>{count($visit)}</visit>
                                <duration>{
                                if(count($visit)>1)  then  minutes-from-duration(xs:dateTime($visit[last()]/@time) - xs:dateTime($visit[1]/@time ))
                                else 0
                                }</duration>
                            </session>
                    }
                </sessions>
    return
    <div>
        { $total-hits } Hits ({ count($visits//error) } failed ), {count($sessions/session)} visits.  More details to come in the futur ...<br/>
        <div class="row">
        <div class="col-md-4">
            <table class="table table-hover table-bordered table-condensed"><tr><th class="col-xs-4"></th><th>paths</th><th>count</th><th>error</th></tr>
            {
                for $visit in $visits
                where not(starts-with($visit/@path, '/_'))
                group by $path := $visit/@path/string()
                order by count($visit) descending
                    return
                        let $count := count($visit)
                        let $count-error := count($visit[.//error])
                        let $percent := xs:integer(100 * $count div $total-hits)
                        let $percent-error := xs:integer(100 * $count-error div $total-hits)
                        return 
                            <tr>
                                <td>
                                    <div class="progress" style="margin-bottom:0px;">
                                        <div class="progress-bar progress-bar-success" role="progressbar" aria-valuenow="{$percent}" aria-valuemin="0" aria-valuemax="100"  style="width: {$percent}%;"></div>
                                        
                                        {
                                            if($count-error > 0) then <div class="progress-bar progress-bar-danger" role="progressbar" aria-valuenow="{$percent}" aria-valuemin="0" aria-valuemax="100"  style="width: {$percent-error}%;"></div>
                                       else ()
                                        }
                                    </div>
                                </td>
                                <td>{$path}</td>                
                                <td>{$count}</td>
                                <td>{$count-error}</td>
                            </tr>
            }</table>
        </div>
        <div class="col-md-4">
            <table class="table table-hover table-bordered table-condensed"><tr><th>Nb hit per visit</th><th>#count</th></tr>
            {
                let $ranges := map {"1":(0,2), "2":(1,3), "3":(2,4), "4":(3,5),"5-9":(4,10),"10+":(9,100000)}
                return 
                    for $e in map:keys($ranges)
                        let $r:=$ranges($e)
                        order by $r[1]
                        return 
                            <tr><th>{$e}</th><td>{count($sessions//session[$r[1] < visit and visit < $r[2]])}</td></tr>
            }</table>
        </div>
        <div class="col-md-4">
            <table class="table table-hover table-bordered table-condensed"><tr><th>Duration of visit</th><th>#count</th></tr>
            {
                let $ranges := map {"< 1 min":(-1,1), "1-2 min":(0,3), "2-5 min":(1,6), "5-30 min":(3,5),"+30 min":(4,10)}
                return 
                    for $e in map:keys($ranges)
                        let $r:=$ranges($e)
                        order by $r[1]
                        return 
                            <tr><th>{$e}</th><td>{count($sessions//session[ $r[1] < duration and duration < $r[2]])}</td></tr>
            }</table>
        </div>
        </div>
    </div>
};
