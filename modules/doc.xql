xquery version "3.0";

(:~
 : This module handle inline documentation.
 :)
module namespace doc="http://apps.jmmc.fr/exist/apps/oidb/doc";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

(:~
 : Display documentation extracted from twiki.
 : 
 : @param $node
 : @param $model
 : @param $update TODO add optional param to request a doc update. user must be authentified
 : @return the <div> with main twiki content TODO href and src attributes must be completed
 :)
declare function doc:main($node as node(), $model as map(*), $update as xs:string?) {
    let $store := if($update) then doc:update() else ()    
    return ($store,doc($config:data-root||"/"||$config:maindoc-filename))
};

declare function doc:update() {    
    let $mainDoc := doc($config:maindoc-twiki-url)
    let $contentDiv := $mainDoc//*[@id="natMainContents"]
    let $store := xmldb:store($config:data-root, $config:maindoc-filename, $contentDiv)
    return <div class="alert alert-success">Main documentation updated from twiki page</div>
};
