xquery version "3.0";

(:~
 : This module handle backoffice operations.
 : TODO restrict access to authenticated/granted users.
 :)
module namespace backoffice="http://apps.jmmc.fr/exist/apps/oidb/backoffice";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace scheduler="http://exist-db.org/xquery/scheduler";

declare variable $backoffice:update-doc := "OiDB doc updater";
declare variable $backoffice:update-vega := "OiDB VEGA updater";

(:~
 : Start a job in the background through the scheduler.
 : 
 : @param $resource path to the resource for the job
 : @param $name name of the job
 : @return flag indicating successful scheduling
 :)
declare %private function backoffice:start-job($resource as xs:string, $name as xs:string) as xs:boolean {
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name=$resource]
    return if ($job) then
        (: already running? stalled? :)
        (: FIXME check job state :)
        false()
    else
        (: FIXME login in as dba: nasty! :)
        let $login := xmldb:login("", "oidb", "")
        return scheduler:schedule-xquery-periodic-job($resource, 0, $name, <parameters/>, 0, 0)
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
 : Template helper to display the status of the documentation.
 : 
 : @param $node
 : @param $model
 : @return a string with the date the documentation was last updated or status if the job is still running
 :)
declare function backoffice:doc-status($node as node(), $model as map(*)) as xs:string {
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name=$backoffice:update-doc]
    return if ($job) then
        (: currently executing :)
        'Running...'
    else
        (: no logging of operation at the moment :)
        (:instead show last modified date of resource :)
        xs:string(xmldb:last-modified($config:data-root, $config:maindoc-filename))
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
    else
        <div class="alert alert-danger fade in">
            <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
            <strong>Action {$action} not supported ! </strong>
            Please report this error if you think that it should not have occured.
        </div>
};
