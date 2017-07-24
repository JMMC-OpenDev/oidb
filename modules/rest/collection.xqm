xquery version "3.0";

(:~
 : This module provides a REST API to add and query collections of granules.
 :)
module namespace coll="http://apps.jmmc.fr/exist/apps/oidb/restxq/collection";

import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "../collection.xqm";

declare namespace rest="http://exquery.org/ns/restxq";
declare namespace http="http://expath.org/ns/http-client";

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
        for $c in collection:list()
        return <collection id="{$c/@id}" created="{$c/@created}"/>
    }
    </collections>
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
    let $collection := collection:retrieve(xmldb:decode($id))
    return 
        if ($collection) then $collection
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
    let $collection := collection:retrieve($id)
    let $status :=
        try {
            let $path :=
                if ($collection) then
                    (: update collection :)
                    collection:update($id, $collection-doc/collection)
                else
                    (: new collection :)
                    collection:create($id, $collection-doc/collection)
            return if ($collection and $path) then
                204 (: No Content :)
            else if ($path) then
                201 (: Created :)
            else
                (: somehow failed to save the document :)
                500 (: Internal Server Error :)
        } catch collection:unauthorized {
            401 (: Unauthorized :)
        } catch * {
            500 (: Internal Server Error :)
        }
    return <rest:response><http:response status="{ $status }"/></rest:response>
};

(:~
 : Create a new collection and return its id.
 : 
 : It saves a new collection under a new id from a generated UUID.
 : 
 : @param $collection-doc the data for the collection
 : @return the new id in response body if success, also see HTTP status code
 :)
declare
    %rest:POST("{$collection-doc}")
    %rest:path("/oidb/collection")
function coll:post-collection($collection-doc as document-node()) {
    let $response :=
        try {
            let $collection := collection:create((), $collection-doc/collection)
            return if ($collection) then
                let $id := data(doc($collection)/collection/@id)
                (: FIXME relative location? :)
                let $location := xmldb:encode($id)
                return <http:response status="201">
                    <http:header name="Location" value="{ $location }"/>
                    <http:body><response><id>{ $id }</id></response></http:body>
                </http:response>
            else
                <http:response status="500"/> (: Internal Server Error :)
        } catch collection:error {
            <http:response status="409"/> (: Conflict :)
        } catch collection:unauthorized {
            <http:response status="401"/> (: Unauthorized :)
        } catch * {
            <http:response status="500"/> (: Internal Server Error :)
        }

    return <rest:response>{ $response }</rest:response>
};

(:~
 : Delete a collection with the given ID in the database.
 : 
 : @param $id the id of the collection to delete
 : @return ignore, see HTTP status code
 :)
declare
    %rest:DELETE
    %rest:path("/oidb/collection/{$id}")
function coll:delete-collection($id as xs:string) {
    let $status := try {
            collection:delete(xmldb:decode($id)), 204 (: No Content :)
        } catch collection:error {
            404 (: Not Found :)
        } catch collection:unauthorized {
            401 (: Unauthorized :)
        } catch * {
            500 (: Internal Server Error :)
        }
    return <rest:response><http:response status="{ $status }"/></rest:response>
};