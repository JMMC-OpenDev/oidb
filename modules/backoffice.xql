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
 : @param $do refers to action name to launch TODO protect and check that user is granted for this action
 : @return the form and status for each action requested
 :)
declare function backoffice:main($node as node(), $model as map(*), $do as xs:string*) {
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
        
        <div class="row">
            <div class="col-md-6">
                <div class="panel panel-default">
                  <div class="panel-heading">
                    <h3 class="panel-title"><i class="glyphicon glyphicon-book"/> Documentation</h3>
                  </div>
                  <div class="panel-body">
                    <form method="post" class="form-inline" role="form">
                        <button type="submit" name="do" value="doc-update" class="btn btn-default">Update doc</button>
                        <div class="form-group"><b>Last update</b>: -</div>
                    </form>
                  </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="panel panel-default">
                  <div class="panel-heading">
                    <h3 class="panel-title"><i class="glyphicon glyphicon-upload"/> Vega L0 upload</h3>
                  </div>
                  <div class="panel-body">
                    <form method="post" class="form-inline" role="form">
                        <button type="submit" name="do" value="vega-update" class="btn btn-default disabled">Update vega logs</button>
                        <div class="form-group"><b>Last update</b>: -</div>
                    </form>
                  </div>
                </div>
            </div>
        </div>
        
        <div class="panel panel-default">
          <div class="panel-heading">
            <h3 class="panel-title"><i class="glyphicon glyphicon-upload"/> Submission dashboard</h3>
          </div>
          <div class="panel-body">
            <form method="post" class="form-inline" role="form">
                <div class="form-group">TBD</div>
            </form>
          </div>
        </div>
        
        
        
    </div>
};

