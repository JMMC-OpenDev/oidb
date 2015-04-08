xquery version "3.0";

(:~
 : This modules provides functions to manipulate XML collection files for
 : granules.
 :)
module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

(: Root directory where collections are stored :)
declare variable $collection:collections-uri := $config:data-root || '/collections';

(:~
 : Save a new collection under the specified ID.
 : 
 : If no id is provided, the function creates one from a generated UUID.
 : 
 : @param $id         the id of the new collection or empty
 : @param $collection the collection contents
 : @return the path to the new resource for the collection
 : @error collection with same id already exists
 :)
declare function collection:create($id as xs:string?, $collection as node()) as xs:string {
    (: TODO check collection contents :)
    let $id :=
        if (not(sm:has-access(xs:anyURI($collection:collections-uri), 'w'))) then
            error(xs:QName('collection:unauthorized'), 'Permission denied')
        else if ($id and collection:retrieve($id)) then
            (: do not recreate existing collections, use :update instead :)
            error(xs:QName('collection:error'), 'Collection already exists')
        else if ($id) then
            $id
        else
            util:uuid()
    (: build the collection from passed data :)
    let $collection := <collection> {
        attribute { "id" }      { $id },
        attribute { "created" } { current-dateTime() },
        $collection/*
    } </collection>
    return xmldb:store($collection:collections-uri, (), $collection)
};

(:~
 : Return a collection given its ID.
 : 
 : @param $id the id of the collection to find
 : @return the <collection> element with the given ID or empty if not found
 :)
declare function collection:retrieve($id as xs:string) as node()? {
    collection($collection:collections-uri)/collection[@id eq $id]
};

(:~
 : Modify an existing collection identified by its ID.
 : 
 : @param $id         the id of the collection to modify
 : @param $collection the collection new contents
 : @return the path to the updated resource or empty if modification failed.
 : @error not found, not authorized
 :)
declare function collection:update($id as xs:string, $collection as node()) {
    (: TODO check collection contents :)
    let $collection := <collection> {
        attribute { "id" } { $id },
        (: update (!) the 'updated' attribute with current time :)
        attribute { "updated" } { current-dateTime() },
        $collection/@*[not(name()=( 'updated', 'id' ))],
        $collection/*
    } </collection>

    let $old-collection := collection:retrieve($id)
    return if (empty($old-collection)) then
        (: also may not be available to current user :)
        error(xs:QName('collection:error'), 'No such collection.')
    else if (not(collection:has-access($old-collection, 'w'))) then
        error(xs:QName('collection:unauthorized'), 'Permission denied.')
    else
        xmldb:store($collection:collections-uri, util:document-name($old-collection), $collection)
};

(:~
 : Remove a collection given its ID.
 : 
 : The XML resource for the collection is deleted.
 : 
 : @param $id the id of the collection to delete
 : @return empty
 : @error collection not found, not authorized
 :)
declare function collection:delete($id as xs:string) {
    let $collection := collection:retrieve($id)
    return if (empty($collection)) then
        error(xs:QName('collection:error'), 'No such collection.')
    else if (not(collection:has-access($collection, 'w'))) then
        error(xs:QName('collection:unauthorized'), 'Permission denied.')
    else
        (: TODO also remove the granules :)
        xmldb:remove(util:collection-name($collection), util:document-name($collection))
};

(:~
 : Return all collections.
 : 
 : It returns only the collections that are readable by the current user.
 : 
 : @return a sequence of <collection> elements.
 :)
declare function collection:list() as element(collection)* {
    for $c in collection($collection:collections-uri)/collection
    where collection:has-access($c, 'r')
    return $c
};

(:~
 : Check whether the current user has access to collection.
 : 
 : @param $id-or-collection the id of the collection to test or the collection as XML fragment
 : @param $mode the partial mode to check against the collection e.g. 'rwx'
 : @return true() if current user has access to collection for the mode
 :)
declare function collection:has-access($id-or-collection as item(), $mode as xs:string) {
    let $collection :=
        if ($id-or-collection instance of node()) then
            $id-or-collection
        else if ($id-or-collection instance of xs:string) then
            collection:retrieve($id-or-collection)
        else
            error(xs:QName('collection:error'), 'Bad collection id ' || $id-or-collection || '.')
    return if (empty($collection)) then
        error(xs:QName('collection:error'), 'No such collection')
    else
        (: check access to collection XML file :)
        sm:has-access(document-uri(root($collection)), $mode)
};
