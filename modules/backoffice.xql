xquery version "3.0";

(:~
 : This module handle backoffice operations.
 : TODO restrict access to authenticated/granted users.
 :)
module namespace backoffice="http://apps.jmmc.fr/exist/apps/oidb/backoffice";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm"; 
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";
import module namespace scheduler="http://exist-db.org/xquery/scheduler";

declare variable $backoffice:update-doc := "OiDB doc updater";
declare variable $backoffice:update-vega := "OiDB VEGA updater";
declare variable $backoffice:update-chara := "OiDB CHARA updater";

(:~
 : Start a job in the background through the scheduler.
 : 
 : @param $resource path to the resource for the job
 : @param $name name of the job
 : @return flag indicating successful scheduling
 :)
declare %private function backoffice:start-job($resource as xs:string, $name as xs:string) as xs:boolean {
    backoffice:start-job($resource, $name, map {})
};

(:~
 : Start a job in the background through the scheduler with parameters.
 : 
 : @param $resource path to the resource for the job
 : @param $name     name of the job
 : @param $params   the parameters to pass to the job
 : @return flag indicating successful scheduling
 :)
declare %private function backoffice:start-job($resource as xs:string, $name as xs:string, $params as map(*)) as xs:boolean {
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name=$resource]
    return if ($job) then
        (: already running? stalled? :)
        (: FIXME check job state :)
        false()
    else
        let $params := <parameters> {
            for $key in map:keys($params)
            return <param name="{ $key }" value="{ map:get($params, $key) }"/>
        } </parameters>
        return scheduler:schedule-xquery-periodic-job($resource, 0, $name, $params, 0, 0)
};

(:~
 : Start a new documentation update job in background.
 : 
 : @return false() if it failed to schedule the job or there is already another job running.
 :)
declare %private function backoffice:update-doc() as xs:boolean {
    backoffice:start-job($config:app-root || '/modules/update-doc.xql', $backoffice:update-doc)
};

(:~
 : Start a new VEGA update job from VegaObs in background.
 : 
 : @return false() if it failed to schedule the job or there is already another job running.
 :)
declare %private function backoffice:update-vega() as xs:boolean {
    backoffice:start-job($config:app-root || '/modules/upload-vega.xql', $backoffice:update-vega)
};

(:~
 : Start a new CHARA update job in background from an uploaded file.
 : 
 : @param $resource the path to the uploaded file with observations.
 : @return false() if it failed to schedule the job or there is already another job running.
 :)
declare %private function backoffice:update-chara($resource as xs:string) as xs:boolean {
    backoffice:start-job($config:app-root || '/modules/upload-chara.xql', $backoffice:update-chara, map { 'resource' := $resource })
};

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
            <dt>Current datetime</dt>
            <dd>{current-dateTime()}</dd>
            <dt>Uptime</dt>
            <dd>{system:get-uptime()}</dd>
            <dt>Log files</dt>
            <dd>{log:check-files()}</dd>
            <dt>TAP service</dt>
            <dd><div>
                {
                    (: TODO templatize :)
                    let $status := tap:status()
                    let $icon := if ($status) then 'glyphicon-remove' else 'glyphicon-ok'
                    let $message := if ($status) then $status else 'OK'
                    return <span><i class="glyphicon { $icon }"/>&#160;{ $message }</span>
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
 : @param $maxVisits max number of elements to return (optional)
 : @return the report generated by log module
 :)
declare 
%templates:default("maxVisits", 10)
function backoffice:visit-status($node as node(), $model as map(*), $maxVisits as xs:integer?) as node()* {
    log:report-visits($maxVisits)
};

(:~
 : Handle any action for the backoffice page.
 : 
 : @param $node
 : @param $model
 : @param $do a list of action names to perform
 : @return an alert for each action performed (success or error)
 :)
declare
    %templates:wrap
function backoffice:action($node as node(), $model as map(*), $do as xs:string*) as node()* {
    for $action in $do
    return if($action="doc-update") then
        let $status := backoffice:update-doc()
        return if ($status) then
            <div class="alert alert-success fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <strong>Action started ! </strong>
                <a href="doc.html">Main documentation</a> is being updated from the <a href="{$config:maindoc-twiki-url}">twiki page</a>.
            </div>
        else
            <div class="alert alert-danger fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <strong>Action failed ! </strong>
                <a href="doc.html">Main documentation</a> failed to be properly updated. Can't find remote source <a href="{$config:maindoc-twiki-url}">twiki page</a>. See log for details.
            </div>
    else if($action = "vega-update") then
        let $status := backoffice:update-vega()
        return if ($status) then
            <div class="alert alert-success fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <strong>Action started ! </strong>
                VEGA observation logs are being updated from <a href="http://vegaobs-ws.oca.eu/">VegaObs</a>.
            </div>
        else
            <div class="alert alert-danger fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <strong>Action failed ! </strong>
                VEGA observation logs is already running or failed to be properly updated. See log for details.
            </div>
    else if($action = "chara-update") then
        let $resource := '/db/apps/oidb-data/tmp/upload-chara.dat'
        let $status := backoffice:update-chara($resource)
        return if ($status) then
            <div class="alert alert-success fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <strong>Action started ! </strong>
                CHARA observation logs are being updated from file.
            </div>
        else
            <div class="alert alert-danger fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <strong>Action failed ! </strong>
                CHARA observation logs is already running or failed to be properly updated. See log for details.
            </div>
    else
        <div class="alert alert-danger fade in">
            <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
            <strong>Action {$action} not supported ! </strong>
            Please report this error if you think that it should not have occured.
        </div>
};
