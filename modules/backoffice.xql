xquery version "3.0";

(:~
 : This module handle backoffice operations.
 : TODO restrict access to authenticated/granted users.
 :)
module namespace backoffice="http://apps.jmmc.fr/exist/apps/oidb/backoffice";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace doc="http://apps.jmmc.fr/exist/apps/oidb/doc" at "doc.xql";

(:~
 : Display main form and handle action if provided.
 : 
 : @param $node
 : @param $model
 : @param $update TODO add optional param to request a doc update. user must be authentified
 : @return the <div> with main twiki content TODO href and src attributes must be completed
 :)
declare function backoffice:main($node as node(), $model as map(*), $do as xs:string?) {
    <div>
        {
            for $action in $do return 
                if($action="doc-update") then
                    doc:update()
                else
                    <div class="alert alert-danger fade in">
                        <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                        <h4>Action {$action} not supported !</h4>
                        <p>Please report this error if you think that it should not have occured.</p>                
                    </div> 
        }
        <form method="post">            
              <button type="submit" name="do" value="doc-update" class="btn btn-default">Update doc</button>
        </form>
    </div>
};

