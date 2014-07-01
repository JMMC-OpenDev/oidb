xquery version "3.0";

(:~
 : This module handle backoffice operations.
 : TODO restrict access to authenticated/granted users.
 :)
module namespace backoffice="http://apps.jmmc.fr/exist/apps/oidb/backoffice";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

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
        let $status := util:eval(xs:anyURI('update-doc.xql'))
        return if ($status//success) then
            <div class="alert alert-success fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <h4>Action successful !</h4>
                <p><a href="doc.html">Main documentation</a> updated from <a href="{$config:maindoc-twiki-url}">twiki page</a></p>
            </div>
        else
            <div class="alert alert-danger fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <h4>Action failed !</h4>
                <p>
                    <a href="doc.html">Main documentation</a> was not updated properly. Can't find remote source <a href="{$config:maindoc-twiki-url}">twiki page</a><br/>
                    <em>Error: { $status//error/text() }</em>
                </p>
            </div>
    else
        <div class="alert alert-danger fade in">
            <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
            <h4>Action {$action} not supported !</h4>
            <p>Please report this error if you think that it should not have occured.</p>
        </div>
};
