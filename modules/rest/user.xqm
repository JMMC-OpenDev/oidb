xquery version "3.0";

(:~
 : This module provides a REST API to manage user in the xml db.
 :)
module namespace user="http://apps.jmmc.fr/exist/apps/oidb/restxq/user";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "../app.xql";

import  module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth" at "/db/apps/jmmc-resources/content/jmmc-auth.xql";

declare namespace rest="http://exquery.org/ns/restxq";
declare namespace http="http://expath.org/ns/http-client";

declare variable $user:people-doc := doc($config:data-root||"/people/people.xml");

(:~
 : Link a people entry with the given ID to a new alias in the database.
 :
 : @param $id             the id of the user to update
 : @param $id             the id of the user to update
 : @return ignore, see HTTP status code
 :)
declare
    %rest:PUT("{$unused}")
    %rest:path("/oidb/user/{$id}/addlink/{$alias}")
function user:addlink($id as xs:string, $alias as xs:string) {
    let $id := xmldb:decode($id)
    let $alias := xmldb:decode($alias)
    let $log := util:log("info", "user:addlink to "||$id||" with "|| $alias)

    let $people := $user:people-doc//person[alias=$id]

    let $status :=
        try {
            let $assert-admin := if(app:user-admin()) then () else error(xs:QName('user:unauthorized'), 'Permission denied')

            let $path :=
                if ($people) then
                    (: update user if required :)
                    if($people/alias[.=$alias]) then ()
                    else
                        let $update := update insert <alias>{$alias}</alias> into $people
                        let $update-email := user:check($alias)
                        return util:document-name($people)
                else
                    ()
            return if ($people and $path) then
                201 (: Created :)
            else if ($people) then
                204 (: No Content :)
            else
                (500 (: Internal Server Error :),"Somehow failed to apply action")
        } catch user:unauthorized {
            401 (: Unauthorized :), $err:description
        } catch * {
            let $log := util:log("error", "user:failed during addlink to "||$id||" with "|| $alias||" : "||$err:description)
            return
            (500 (: Internal Server Error :),"can't link "||$id||" with "|| $alias||" : "||$err:description)
        }
    return (<rest:response><http:response status="{ $status[1] }"/></rest:response>, if(exists($status[2])) then <response>{$status[2]}</response> else ())
};

(:~
 : Link a people entry with the given ID to a new alias in the database.
 :
 : @param $id             the id of the user to update
 : @param $id             the id of the user to update
 : @return ignore, see HTTP status code
 :)
declare
    %rest:POST("{$info}")
    %rest:path("/oidb/user/{$id}")
function user:adduser($id as xs:string, $info as document-node()) {
    let $id := xmldb:decode($id)

    let $people := $user:people-doc//person[alias=$id]

    let $status :=
        try {
            let $assert-admin := if(app:user-admin() or true()) then () else error(xs:QName('user:unauthorized'), 'Permission denied')
            let $assert-not-present := if($people) then error(xs:QName('user:conflict'), 'User already present') else ()
            let $path :=
                        let $names := tokenize($id, " ")
                        let $firstname := if(exists($info//firstname)) then $info//firstname else <firstname>{$names[1]}</firstname>
                        let $lastname := if(exists($info//lastname)) then $info//lastname else <lastname>{string-join($names[position()>1]," ")}</lastname>
                        let $valid-email := exists($info//email) and contains($info//email,'@')
                        let $email := if(exists($valid-email)) then attribute {'email'} {data($info//email)} else ()
                        let $new-people := <person>{($firstname, $lastname)}<alias>{$email}{$id}</alias></person>
                        let $create := update insert $new-people into $user:people-doc/*
                        return util:document-name($user:people-doc/*)
            let $update-email := user:check($id)
            return if ($path) then
                201 (: Created :)
            else
                (500 (: Internal Server Error :),"Somehow failed to apply action")
        } catch user:unauthorized {
            401 (: Unauthorized :), $err:description
        } catch user:conflict {
            406 (: Not Acceptable :), $err:description
        } catch * {
            500 (: Internal Server Error :),"can't add "||$id||" : "||$err:description
        }
    return (<rest:response><http:response status="{ $status[1] }"/></rest:response>, if(exists($status[2])) then <response>{$status[2]}</response> else ())
};


(:~
 : Link a people entry with the given ID to a new alias in the database.
 :
 : @param $id             the id of the user to update
 : @param $id             the id of the user to update
 : @return ignore, see HTTP status code
 :)
declare
    %rest:GET("")
    %rest:path("/oidb/user/check/{$name}")
function user:check($name as xs:string?) {
    let $name := if($name) then xmldb:decode($name) else ()
    let $people := if($name) then $user:people-doc//person[alias=$name] else $user:people-doc//person

    let $status :=
        try {
            let $scan := for $p in $people[not(alias/@email)]
                for $a in $p/alias
                    let $info := jmmc-auth:get-info($a)
                    let $valid-email := exists($info/email) and contains($info/email,'@')
                    let $update := if($valid-email) then update insert attribute {"email"} {$info/email} into $a else ()
                    return if(exists($info/email)) then <update>{$a}{$info/email}</update> else ()
            return
            (200 (: OK :),$scan)
        } catch user:unauthorized {
            401 (: Unauthorized :), $err:description
        } catch user:conflict {
            406 (: Not Acceptable :), $err:description
        } catch * {
            500 (: Internal Server Error :),$err:description
        }
    return (<rest:response><http:response status="{ $status[1] }"/></rest:response>, <response>{$status}{$name}</response> )
};

declare function user:get-email($name as xs:string){
    let $email := ($user:people-doc//person[alias[normalize-space(.)=normalize-space($name)]]//@email) [1]
    return  data($email)
};

declare function user:check($node as node(), $model as map(*)) as map(*) {
    map:merge(($model, map:entry('updated', user:check(()))))
};


declare
    %rest:GET("")
    %rest:path("/oidb/user/{$name}/delegations")
function user:get-delegations($name){
    <delegations>{
        $user:people-doc//person[alias[lower-case(normalize-space(.))=lower-case(normalize-space($name))]]//delegation
    }</delegations>
};
