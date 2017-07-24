(:~
 : This is the main XQuery which will (by default) be called by controller.xql
 : to process any URI ending with ".html". It receives the HTML from
 : the controller and passes it to the templating system.
 :)
xquery version "3.0";

import module namespace templates="http://exist-db.org/xquery/templates" ;

(: 
 : The following modules provide functions which will be called by the 
 : templating.
 :)
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers" at "templates-helpers.xql";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";
import module namespace backoffice="http://apps.jmmc.fr/exist/apps/oidb/backoffice" at "backoffice.xql";
import module namespace query="http://apps.jmmc.fr/exist/apps/oidb/query" at "query.xql";
import module namespace vizier="http://apps.jmmc.fr/exist/apps/oidb/vizier" at "vizier.xql";
import module namespace ads="http://apps.jmmc.fr/exist/apps/oidb/ads" at "ads.xql";
import module namespace oifits="http://apps.jmmc.fr/exist/apps/oidb/oifits" at "oifits.xql";
import module namespace comments="http://apps.jmmc.fr/exist/apps/oidb/comments" at "comments.xql";
import module namespace flash="http://apps.jmmc.fr/exist/apps/oidb/flash" at "flash.xqm";

import module namespace user="http://apps.jmmc.fr/exist/apps/oidb/restxq/user" at "rets/user.xqm";



import module namespace jmmc-about="http://exist.jmmc.fr/jmmc-resources/about";
import module namespace jmmc-web="http://exist.jmmc.fr/jmmc-resources/web";

(: our javascripts requires to get XHTML HTML5 is really a nightmare :)
declare option exist:serialize "method=xhtml media-type=text/html omit-xml-declaration=yes indent=yes";

let $config := map {
    $templates:CONFIG_APP_ROOT := $config:app-root,
    $templates:CONFIG_STOP_ON_ERROR := true()
}
(:
 : We have to provide a lookup function to templates:apply to help it
 : find functions in the imported application modules. The templates
 : module cannot see the application modules, but the inline function
 : below does see them.
 :)
let $lookup := function($functionName as xs:string, $arity as xs:int) {
    try {
        function-lookup(xs:QName($functionName), $arity)
    } catch * {
        ()
    }
}
(:
 : The HTML is passed in the request from the controller.
 : Run it through the templating system and return the result.
 :)
let $content := request:get-data()
return
    templates:apply($content, $lookup, (), $config)
