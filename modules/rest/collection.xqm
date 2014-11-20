xquery version "3.0";

(:~
 : This module provides a REST API to add and query collections of granules.
 :)
module namespace coll="http://apps.jmmc.fr/exist/apps/oidb/restxq/collection";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";

import module namespace xmldb="http://exist-db.org/xquery/xmldb";

declare namespace rest="http://exquery.org/ns/restxq";

declare variable $coll:collection-uri := $config:data-root || '/collections';

(:~
 : Return a list of all existing collections.
 : 
 : It returns a short description of each collection with only its ID and
 : creation date.
 : 
 : @return a <collections/> element with simple <collection/> as children
 :)
declare
    %rest:GET
    %rest:path("/oidb/collection")
function coll:list() as element(collections) {
    <collections>
    {
        for $c in collection($coll:collection-uri)/collection
        return <collection id="{$c/@id}" created="{$c/@created}"/>
    }
    </collections>
};

(:~
 : Return a collection given its ID.
 : 
 : @param $id the id of the collection to find
 : @return the <collection> element with the given ID or empty if not found
 :)
declare %private function coll:find($id as xs:string) as element(collection)? {
    collection($coll:collection-uri)/collection[@id eq $id]
};

(:~
 : Return a collection given a collection ID.
 : 
 : @param $id the id of the collection to find
 : @return the matching <collection> element or a 404 status if not found
 :)
declare
    %rest:GET
    %rest:path("/oidb/collection/{$id}")
function coll:retrieve-collection($id as xs:string) {
    let $collection := coll:find(xmldb:decode($id))
    return 
        if ($collection) then <collection> { $collection/@*, $collection/* } </collection>
        else <rest:response><http:response status="404"/></rest:response>
};

(:~
 : Save or update a collection with the given ID in the database.
 : 
 : It creates a new collection if the id does not match any previous collection
 : and returns a 201 status. Otherwise, it updates the contents of the previous
 : collection and touches its 'updated' attribute before returning a 204 status.
 : 
 : @param $id             the id of the collection to find
 : @param $collection-doc the data for the collection
 : @return ignore, see HTTP status code
 :)
declare
    %rest:PUT("{$collection-doc}")
    %rest:path("/oidb/collection/{$id}")
function coll:store-collection($id as xs:string, $collection-doc as document-node()) {
    let $id := xmldb:decode($id)
    let $collection := coll:find($id)
    let $filename :=
        if ($collection) then
            (: update collection :)
            document-uri(root($collection))
        else
            (: new collection :)
            ()
    (: prepare a new collection document :)
    let $collection :=
        <collection> {
            if ($collection) then
                (
                    (: update (!) the 'updated' attribute with current time :)
                    $collection/@*[name()!=( 'updated' )],
                    attribute { "updated" } { current-dateTime() }
                )
            else
                (
                    attribute { "id" } { $id },
                    attribute { "created" } { current-dateTime() }
                ),
            $collection-doc/collection/*
        } </collection>
    let $path := xmldb:store($coll:collection-uri, $filename, $collection)
    return <rest:response>
        <http:response> { attribute { "status" } {
            if ($filename and $path) then 204 (: No Content :)
            else if ($path)          then 201 (: Created :)
            else                          400 (: Bad Request :)
        } } </http:response>
    </rest:response>
};
