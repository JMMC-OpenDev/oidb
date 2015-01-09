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
        if ($id and collection:retrieve($id)) then
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
 :)
declare function collection:update($id as xs:string, $collection as node()) {
    let $resource-name := util:document-name(collection:retrieve($id))
    (: TODO check collection contents :)
    let $collection := <collection> {
        attribute { "id" } { $id },
        (: update (!) the 'updated' attribute with current time :)
        attribute { "updated" } { current-dateTime() },
        $collection/@*[name()!=( 'updated', 'id' )],
        $collection/*
    } </collection>

    return xmldb:store($collection:collections-uri, $resource-name, $collection)
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
    else if (not(sm:has-access(document-uri(root($collection)), 'w'))) then
        error(xs:QName('collection:unauthorized'), 'Permission denied.')
    else
        (: TODO also remove the granules :)
        xmldb:remove(util:collection-name($collection), util:document-name($collection))
};

(:~
 : Return all collections.
 : 
 : @return a sequence of <collection> elements.
 :)
declare function collection:list() as element(collection)* {
    collection($collection:collections-uri)/collection
};
