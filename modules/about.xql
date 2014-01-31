xquery version "3.0";

(:~
 : This module contains a set of functions for templating in the About page
 : of the application.
 : 
 : It makes use of the changelog element from the deployment descriptor of the
 : application (repo.xml).
 :)

module namespace about="http://apps.jmmc.fr/exist/apps/oidb/about";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

(:~
 : Put the list of changes of the application into the current model for
 : subsequent uses by other templating functions.
 : 
 : @param $node
 : @param $model
 : @return a map with changes to be added to current $model map.
 :)
declare
    %templates:wrap
function about:changelog($node as node(), $model as map(*)) as map(*) {
    let $changes := doc($config:app-root || '/repo.xml')//change
    return map { "changes" := $changes }
};

(:~
 : Return the current version number of the application.
 : 
 : It makes use of the current $model map to get the list of changes.
 : 
 : @param $node
 : @param $model
 : @return the current version of the application as string.
 :)
declare 
    %templates:wrap
function about:version($node as node(), $model as map(*)) as xs:string {
    let $changes := $model("changes")
    (: Note: turn version into number for comparison :)
    (: force version number format to all numbers and single dot and XX.9 after XX.10 :)
    return $changes[@version=max($changes/@version)]/@version
};

(:~
 : Return the changelog associated with a verion.
 : 
 : It makes use of the current $model map to get the change.
 : 
 : @param $node
 : @param $model
 : @return a HTML fragment with changelog.
 :)
declare function about:change($node as node(), $model as map(*)) as node()* {
    (: change is a HTML fragment in repo.xml, return children :)
    $model("change")/*
};
