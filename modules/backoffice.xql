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
import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";
import module namespace obsportal="http://apps.jmmc.fr/exist/apps/oidb/obsportal" at "obsportal.xqm";


import module namespace jmmc-eso="http://exist.jmmc.fr/jmmc-resources/eso";
import module namespace jmmc-ads="http://exist.jmmc.fr/jmmc-resources/ads";


declare variable $backoffice:update-doc := "OiDB doc updater";
declare variable $backoffice:update-eso := "OiDB ESO updater";
declare variable $backoffice:update-eso-inc := "OiDB ESO incremental updater";
declare variable $backoffice:update-vega := "OiDB VEGA updater";
declare variable $backoffice:update-chara := "OiDB CHARA updater";
declare variable $backoffice:update-obsportal := "OiDB OBSPORTAL updater";


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
                    (<dt><span class="glyphicon glyphicon-warning-sign"/>&#160;Warning</dt>, <dd><span class="label label-danger">you are superuser({sm:id()//*:username})</span></dd>)
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
            <dt>DB Permissions</dt>
            <dd>{backoffice:check-permissions($config:data-root)}</dd>
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


declare function backoffice:eso-recno($node as node(), $model as map(*)) as node()* {
    <span>{number(collection:retrieve('eso_vlti_import')//recno)}</span>
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
 : Template helper to display the status of the incremental ESO update .
 : 
 : @param $node
 : @param $model
 : @return
 :)
declare function backoffice:eso-status-inc($node as node(), $model as map(*)) as xs:string {
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
 : Template helper to display the status of the Obsportal update.
 : 
 : @param $node
 : @param $model
 : @return
 :)
declare function backoffice:obsportal-status($node as node(), $model as map(*)) as xs:string {
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name=$backoffice:update-obsportal]
    return if ($job) then
        (: currently executing :)
        'Running...'
    else
        (: TODO :)
        ""||obsportal:get-last-mod-date(obsportal:get-collection-id("FIXME"))
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
%templates:default("max-detail", 15)
function backoffice:submission-status($node as node(), $model as map(*), $maxSubmissions as xs:integer?, $max-detail as xs:integer?) as node()* {
    log:report-submits($maxSubmissions,  $max-detail)
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

(:~
 : Apply set of permissions to a resource.
 : 
 : If any of the permission items is false or unspecified, the respective 
 : permission of the resource is not modified.
 : 
 : @param $path the path to the resource to modify (relative to package root)
 : @param $perms a sequence of user, group and mods to set
 : @return empty
 :)
declare function backoffice:set-permissions($path as xs:string, $perms as item()*)  {
    let $uri := xs:anyURI($path)
    let $cperm := sm:get-permissions($uri)/*
    return (
        let $user := $perms[1]
        return if ($user and $user != $cperm/@owner)  then sm:chown($uri, $user) else (),
        let $group := $perms[2]
        return if ($group and $group != $cperm/@group) then sm:chgrp($uri, $group) else (),
        let $mod := $perms[3]
        return if ($mod and $mod != $cperm/@mode)   then sm:chmod($uri, $mod) else ()
    )
};

(: create directory tree and set permissions :)

(:~
 : Check of xml db storage permissions.
 : 
 : @param $target root path of data ($config:da)
 : @return an entry per checked point
 :)
declare function backoffice:check-permissions($target as xs:string)  {
    try {
        let $check := (
            (: People :)
             backoffice:set-permissions($target||"/people", (false(), 'oidb', 'r-xr-x--x')),
             backoffice:set-permissions($target||"/people/people.xml", (false(), 'oidb', 'rw-rw-r--')),
        
            (: COLLECTIONS :)
            let $collections := $target||'/collections'
            return (
                backoffice:set-permissions($collections, ( false(), 'jmmc', 'rwxrwxr-x' )),
                (: set permissions of any static collection :)
                for $r in xmldb:get-child-resources($collections)
                return backoffice:set-permissions(concat($collections, '/', $r), ( false(), 'oidb', 'rw-rw-r--'))
                ),
        
            (: TMP :)
            let $tmp := $target|| '/tmp'
            return backoffice:set-permissions($tmp, ( false(), false(), 'rwxrwxrwx' )),
        
        
            (: LOG FILES :)
            let $dir := $target || "/log"
            let $logs := ( 'downloads', 'searches', 'submits', 'visits' )
            return
                for $l in $logs
                return backoffice:set-permissions($dir||"/"||$l||".xml", ( false(), false(), 'rw-rw-rw-' )),
        
            (: OIFITS STAGING :)
            let $staging := $target || '/oifits/staging'
            return backoffice:set-permissions($staging, ( false(), 'jmmc', 'rwxrwxr-x' )),
        
            (: COMMENTS :)
            let $comments := $target || '/comments/comments.xml'
            return backoffice:set-permissions($comments, ( false(), 'jmmc', 'rw-rw-r--' ))    
        )
        return
        <span>Permissions OK</span>
    } catch * {
        <span>Error checking permissions : please ask admin to run backoffice:check-permissions("{$target}")</span>
    }
};

