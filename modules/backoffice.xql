xquery version "3.0";

(:~
 : This module handle backoffice operations.
 :)
module namespace backoffice="http://apps.jmmc.fr/exist/apps/oidb/backoffice";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm"; 
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";
import module namespace scheduler="http://exist-db.org/xquery/scheduler";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";

import module namespace jmmc-eso="http://exist.jmmc.fr/jmmc-resources/eso";
import module namespace jmmc-ads="http://exist.jmmc.fr/jmmc-resources/ads";



declare variable $backoffice:update-doc := "OiDB doc updater";
declare variable $backoffice:update-eso := "OiDB ESO updater";
declare variable $backoffice:update-vega := "OiDB VEGA updater";
declare variable $backoffice:update-chara := "OiDB CHARA updater";

(:~
 : Template helper to display the general status.
 : 
 : @param $node
 : @param $model
 : @return a string with the date the documentation was last updated or status if the job is still running
 :)
declare function backoffice:main-status($node as node(), $model as map(*)) as node()* {
    <div>
        <dl class="dl-horizontal">
            {
                if(app:user-admin()) then 
                    (<dt><span class="glyphicon glyphicon-warning-sign"/>&#160;Warning</dt>, <dd><span class="label label-danger">you are superuser</span></dd>)
                else
                    ()
            }
            <dt>Current datetime</dt>
            <dd>{current-dateTime()}</dd>
            <dt>Uptime</dt>
            <dd>{system:get-uptime()}</dd>
            <dt>Log files</dt>
            <dd>{log:check-files()}</dd>
            <dt>Collections</dt>
            <dd><div>
                {
                    let $data := tap:execute($app:collections-query)
                    let $ids := $data//*:TD/text()
                    let $collections := collection("/db/apps/oidb-data/collections")/collection
                    let $rdbms-cnt := count($ids)
                    let $xmldb-cnt := count($collections)
                    return  if ($rdbms-cnt = $xmldb-cnt) then $rdbms-cnt
                        else <span class="label label-danger"> { $rdbms-cnt || " in RDBMS =! " || $xmldb-cnt || " in xmlDB" } </span>
                }
            </div></dd>
            <dt>TAP service</dt>
            <dd><div>
                {
                    (: TODO templatize :)
                    let $status := tap:status()
                    let $icon := if ($status) then 'glyphicon-remove' else 'glyphicon-ok'
                    let $message := if ($status) then $status else 'OK'
                    return <span><i class="glyphicon { $icon }"/>&#160;{ $message }&#160;</span>
                }
                <br/>
                <em>TODO add link to services</em>
            </div></dd>
        </dl>
    </div>
};

(:~
 : Template helper to display the status of the documentation.
 : 
 : @param $node
 : @param $model
 : @return a string with the date the documentation was last updated or status if the job is still running
 :)
declare function backoffice:doc-status($node as node(), $model as map(*)) as node() {
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name=$backoffice:update-doc]
    let $twiki-link := <a href="{$config:maindoc-twiki-url}" title="visit twiki source page"><i class="glyphicon glyphicon-new-window"/></a>
    return if ($job) then
        (: currently executing :)
        <span>Running...</span>
    else if (doc-available($config:data-root || "/" || $config:maindoc-filename)) then
        (: no logging of operation at the moment :)
        (:instead show last modified date of resource :)
        <span>
        { 
          xs:string(xmldb:last-modified($config:data-root, $config:maindoc-filename))
          , $twiki-link
        }
        </span>
    else
        (: no imported documentation found :)
        <span>No yet present. Visit twiki page {$twiki-link}</span>
};

(:~
 : Template helper to display the cache status.
 : 
 : @param $node
 : @param $model
 : @return a form with information 
 :)
declare function backoffice:cache-status($node as node(), $model as map(*)) as node()* {
        if ($tap:cache/cached) then
            (<span>oldest record :&#160; { data($tap:cache/cached[1]/@date) } &#160; </span>,
            <form action="modules/backoffice-job.xql" method="post" class="form-inline" role="form">
                <button type="submit" name="do" value="cache-flush" class="btn btn-default">Clear cache</button>
            </form>)
        else
            <span>cache empty</span>
};

(:~
 : Template helper to display the eso-cache status.
 : 
 : @param $node
 : @param $model
 : @return a form with information 
 :)
declare function backoffice:eso-cache-status($node as node(), $model as map(*)) as node() {
    <span>{
        count($jmmc-eso:cache/*)
    } record(s)</span>
};

(:~
 : Template helper to display the ads-cache status.
 : 
 : @param $node
 : @param $model
 : @return a form with information 
 :)
declare function backoffice:ads-cache-status($node as node(), $model as map(*)) as node() {
    <span>{
        count($jmmc-ads:cache/*)
    } record(s)</span>
};

(:~
 : Template helper to display the status of the ESO update.
 : 
 : @param $node
 : @param $model
 : @return
 :)
declare function backoffice:eso-status($node as node(), $model as map(*)) as xs:string {
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name=$backoffice:update-eso]
    return if ($job) then
        (: currently executing :)
        'Running...'
    else
        (: TODO :)
        '-'
};

(:~
 : Template helper to display the status of the VEGA update.
 : 
 : @param $node
 : @param $model
 : @return
 :)
declare function backoffice:vega-status($node as node(), $model as map(*)) as xs:string {
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name=$backoffice:update-vega]
    return if ($job) then
        (: currently executing :)
        'Running...'
    else
        (: TODO :)
        '-'
};

(:~
 : Template helper to display the status of the CHARA update.
 : 
 : @param $node
 : @param $model
 : @return
 :)
declare function backoffice:chara-status($node as node(), $model as map(*)) as xs:string {
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name=$backoffice:update-chara]
    return if ($job) then
        (: currently executing :)
        'Running...'
    else
        (: TODO :)
        '-'
};

(:~
 : Template helper to display the submission log summary.
 : 
 : @param $node
 : @param $model
 : @param $maxSubmissions max number of elements to return (optional)
 : @return the report generated by log module
 :)
declare 
%templates:default("maxSubmissions", 10)
function backoffice:submission-status($node as node(), $model as map(*), $maxSubmissions as xs:integer?) as node()* {
    log:report-submits($maxSubmissions)
};

(:~
 : Template helper to display the download log summary.
 : 
 : @param $node
 : @param $model
 : @param $maxDownloads max number of elements to return (optional)
 : @return the report generated by log module
 :)
declare 
%templates:default("maxDownloads", 10)
function backoffice:download-status($node as node(), $model as map(*), $maxDownloads as xs:integer?) as node()* {
    log:report-downloads($maxDownloads)
};

(:~
 : Template helper to display the search log summary.
 : 
 : @param $node
 : @param $model
 : @param $maxSearches max number of elements to return (optional)
 : @return the report generated by log module
 :)
declare 
%templates:default("maxSearches", 10)
function backoffice:search-status($node as node(), $model as map(*), $maxSearches as xs:integer?) as node()* {
    log:report-searches($maxSearches)
};

 (:~
 : Template helper to display the search log summary.
 : 
 : @param $node
 : @param $model
 : @param $maxVisits max number of elements to return (optional, 100 by default)
 : @return the report generated by log module
 :)
declare 
%templates:default("maxVisits", 100)
function backoffice:visit-status($node as node(), $model as map(*), $maxVisits as xs:integer?) as node()* {
    log:report-visits($maxVisits)
};
