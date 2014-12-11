xquery version "3.0";

(:~
 : This module provides a REST API to add comments to granules.
 :)
module namespace comment="http://apps.jmmc.fr/exist/apps/oidb/restxq/comment";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";
import module namespace login="http://apps.jmmc.fr/exist/apps/oidb/login" at "../login.xqm";

import module namespace xmldb="http://exist-db.org/xquery/xmldb";

declare namespace rest="http://exquery.org/ns/restxq";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

(: the resource path for comments :)
declare variable $comment:comments := $config:data-root || '/comments/comments.xml';

(:~
 : Build a comment and save it to the database.
 : 
 : @param $parent     the id of the parent comment, empty if toplevel)
 : @param $granule-id the if of the granule the comment is for
 : @param $author     the comment author
 : @param $text       the text of the comment
 : @return the UUID of the new comment
 : @error Failed to save the comment or no parent comment
 :)
declare %private function comment:save($parent as xs:string?, $granule-id as xs:integer, $author as xs:string, $text as xs:string) {
    let $comments := doc($comment:comments)/comments
    let $parent := if ($parent) then $comments//comment[@granule-id=$granule-id][@id=$parent] else $comments

    return if ($parent) then
        let $id := util:uuid()
        let $comment :=
            <comment id="{ $id }" granule-id="{ $granule-id }">
                <author>{ $author }</author>
                <date>{ current-dateTime() }</date>
                <text>{ $text }</text>
            </comment>
        return ( update insert $comment into $parent, $id )
    else
        error()
};

(:~
 : Save a comment from a user to a granule in the database.
 : 
 : @param $comment the comment to save
 : @return see HTTP status code
 :)
declare
    %rest:POST("{$comment}")
    %rest:path("/oidb/comment")
    %output:media-type("text/plain")
    %output:method("text")
function comment:store-comment($comment as node()) {
    let $comment := $comment/comment

    (: FIXME do not use email for user id :)
    let $author := login:user-email()
    let $granule-id := data($comment/@granule-id)
    let $parent := data($comment/@parent)

    return <rest:response> {
        if (not(sm:has-access(xs:anyURI($comment:comments), 'w'))) then
            <http:response status="401"/> (: Unauthorized :)
        else
            try {
                <http:response status="201">
                    <http:body><data>{ comment:save($parent, $granule-id, $author, $comment/text[1]/text()) }</data></http:body>
                </http:response>
            } catch * {
                util:log('warn', $err:description),
                <http:response status="400"/> (: Bad Request :)
            }
    } </rest:response>
};
