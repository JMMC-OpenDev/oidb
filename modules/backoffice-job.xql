xquery version "3.0";

(:~
 : This script starts updating jobs as response from the HTML forms on the
 : backoffice page.
 : 
 : @note
 : It is required because it seems possible to process a multipart content
 : from a submitted HTML form neither directly in the controller (content not
 : parsed) nor within a templating function.
 : 
 : @see http://sourceforge.net/p/exist/mailman/message/31598566/
 : @see eXist-db's XQueryURLRewrite.java
 :)
import module namespace scheduler="http://exist-db.org/xquery/scheduler";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace flash="http://apps.jmmc.fr/exist/apps/oidb/flash" at "flash.xqm";
import module namespace backoffice="http://apps.jmmc.fr/exist/apps/oidb/backoffice" at "backoffice.xql";

(:~
 : Start a job in the background through the scheduler with parameters.
 : 
 : @note
 : It evaluates a script that creates the background job if not already running.
 : This script is setuid to elevate privileges to dba role (required for 
 : starting scheduler jobs).
 : 
 : @param $resource path to the resource for the job
 : @param $name     name of the job
 : @param $params   the parameters to pass to the job
 : @return flag indicating successful scheduling
 :)
declare %private function local:start-job($resource as xs:string, $name as xs:string, $params as map(*)) as xs:boolean {
    let $params := <parameters> {
        for $key in map:keys($params)
        return <param name="{ $key }" value="{ map:get($params, $key) }"/>
    } </parameters>
    let $status := util:eval(xs:anyURI('schedule-job.xql'), false(), (
        xs:QName('resource'), $resource,
        xs:QName('name'),     $name,
        xs:QName('params'),   $params))
    return name($status) = 'success'
};

(:~
 : Start a new documentation update job in background.
 : 
 : @return false() if it failed to schedule the job or there is already another job running.
 :)
declare %private function local:update-doc() {
    local:start-job($config:app-root || '/modules/update-doc.xql', $backoffice:update-doc, map {})
};

(:~
 : Start a new VEGA update job from VegaObs in background.
 : 
 : @return false() if it failed to schedule the job or there is already another job running.
 :)
declare %private function local:update-vega() {
    local:start-job($config:app-root || '/modules/upload-vega.xql', $backoffice:update-vega, map {})
};

(:~
 : Start a new CHARA update job in background from an uploaded file.
 : 
 : @param $resource the path to the uploaded file with observations.
 : @return false() if it failed to schedule the job or there is already another job running.
 :)
declare %private function local:update-chara() {
    let $data := request:get-uploaded-file-data('file')
    let $path := xmldb:store('/db/apps/oidb-data/tmp', 'upload-chara.dat', $data, 'text/csv')

    return local:start-job($config:app-root || '/modules/upload-chara.xql', $backoffice:update-chara, map { 'resource' := $path })
};

(: 
 : Helper to prefix info flash message with action status.
 : 
 : @param $msg the rest of the message.
 : @return empty
 :)
declare %private function local:info($msg as item()*) as empty() {
    flash:info((<strong xmlns="http://www.w3.org/1999/xhtml">Action started !</strong>, ' ', $msg))
};

(: 
 : Helper to prefix error flash message with action status.
 : 
 : @param $msg the rest of the message.
 : @return empty
 :)
declare %private function local:error($msg as item()*) {
    flash:error((<strong xmlns="http://www.w3.org/1999/xhtml">Action failed !</strong>, ' ', $msg))
};

let $action := request:get-parameter('do', '')
return (
    switch ($action)
        case "doc-update" return
            if(local:update-doc()) then
                local:info(<span xmlns="http://www.w3.org/1999/xhtml"><a href="doc.html">Main documentation</a> is being updated from the <a href="{$config:maindoc-twiki-url}">twiki page</a>.</span>)
            else
                local:error(<span xmlns="http://www.w3.org/1999/xhtml"><a href="doc.html">Main documentation</a> failed to be properly updated. Can't find remote source <a href="{$config:maindoc-twiki-url}">twiki page</a>. See log for details.</span>)
    
       case "vega-update" return
            if(local:update-vega()) then
                local:info(<span xmlns="http://www.w3.org/1999/xhtml">VEGA observation logs are being updated from <a href="http://vegaobs-ws.oca.eu/">VegaObs</a>.</span>)
            else
                local:error(<span xmlns="http://www.w3.org/1999/xhtml">VEGA observation logs is already running or failed to be properly updated. See log for details.</span>)
    
        case "chara-update" return
            if(local:update-chara()) then
                local:info(<span xmlns="http://www.w3.org/1999/xhtml">CHARA observation logs are being updated from file.</span>)
            else
                local:error(<span xmlns="http://www.w3.org/1999/xhtml">CHARA observation logs is already running or failed to be properly updated. See log for details.</span>)

        default return
            flash:error(<span xmlns="http://www.w3.org/1999/xhtml"><strong>Action {$action} not supported !</strong> Please report this error if you think that it should not have occured.</span>),
    (: redirect after post :)
    response:redirect-to(xs:anyURI('../backoffice.html'))
)
