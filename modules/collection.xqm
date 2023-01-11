xquery version "3.0";

(:~
 : This modules provides functions to manipulate XML collection files for
 : granules.
 :)
module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";
import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";


(: Root directory where collections are stored :)
declare variable $collection:collections-uri := $config:data-root || '/collections';

declare variable $collection:VIZIER_COLTYPE := "VizieR";
declare variable $collection:PUBLIC_COLTYPE := "public";
declare variable $collection:SIMULATION_COLTYPE := "simulation";




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
    let $owner := data(sm:id()//*:real/*:username)
    let $collection := <collection> {
        attribute { "id" }      { $id },
        attribute { "created" } { current-dateTime() },
        attribute { "owner" } {$owner},
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
    collection(xs:anyURI($collection:collections-uri))/collection[@id eq $id]
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
        error(xs:QName('collection:error'), 'No such collection.('||$id||')')
    else if (not(collection:has-access($old-collection, 'w'))) then
        error(xs:QName('collection:unauthorized'), 'Permission denied.')
    else
        xmldb:store($collection:collections-uri, util:document-name($old-collection), $collection)
};

(:~
 : Remove a collection given its ID with associated granules in SQL db.
 : 
 : The XML resource for the collection and sql records are deleted.
 : 
 : @param $id the id of the collection to delete
 : @return empty
 : @error failed to delete, collection not found, not authorized
 :)
declare function collection:delete($id as xs:string) {
    let $collection := collection:retrieve($id)
    return if (empty($collection)) then
        error(xs:QName('collection:error'), 'No such collection.('||$id||')')
    else if (not(collection:has-access($collection, 'w'))) then
        error(xs:QName('collection:unauthorized'), 'Permission denied.')
    else
        (
            collection:delete-granules($id),
            xmldb:remove(util:collection-name($collection), util:document-name($collection))
        )
};


(:~
 : Format an SQL DELETE request with the given collection id to remove associated datalinks & granules.
 : 
 : @param $collection-id the id of the collection to delete
 : @return a SQL DELETE statement
 :)
declare %private function collection:delete-granules-statement($collection-id as xs:string) as xs:string {
    "DELETE FROM " || $config:sql-datalink-table || " WHERE id IN ( SELECT id FROM " || $config:sql-table || " WHERE obs_collection='" || $collection-id || "')"
    || " ; " ||
    "DELETE FROM " || $config:sql-table || " WHERE obs_collection='" || $collection-id || "'"
};


(:~
 : Get the granules associated to the given collection ID.
 : 
 : @param @param $collection-id the id of the collection to list
 : @return granules element
 :)
declare function collection:get-granules($collection-id as xs:string)  {
    collection:get-granules($collection-id, sql-utils:get-jndi-connection())
};

(:~
 : Get the granules associated to the given collection ID.
 : 
 : @param @param $collection-id the id of the collection to list
 : @param $handle the SQL database handle
 : @return granules element
 :)
declare function collection:get-granules($collection-id as xs:string, $handle as xs:long)  {
        let $statement := adql:build-query(("obs_collection="||$collection-id))
        let $result := sql-utils:execute($handle, $statement, false())

        return if ($result/name() = 'sql:result' and $result/@updateCount >= 0) then ()
        else if ($result/name() = 'sql:exception') then
            error(xs:QName('collection:error'), 'Failed to get granules for collection , sql:exception ' || $collection-id || ': ' || $result//sql:message/text())
        else
            error(xs:QName('collection:error'), 'Failed to get granules for collection ' || $collection-id || ': ' || serialize($result))
};


 (:~
 : Remove the granules associated to the given collection ID.
 : 
 : @param @param $collection-id the id of the collection to delete
 : @return empty
 : @error failed to delete
 :)
declare function collection:delete-granules($collection-id as xs:string)  {
    collection:delete-granules($collection-id, sql-utils:get-jndi-connection())
};

(:~
 : Remove the granules associated to the given collection ID.
 : 
 : @param @param $collection-id the id of the collection to delete
 : @param $handle the SQL database handle
 : @return empty
 : @error failed to delete
 :)
declare function collection:delete-granules($collection-id as xs:string, $handle as xs:long)  {
    let $statement := collection:delete-granules-statement($collection-id)
    let $result := sql-utils:execute($handle, $statement, false())

    return if ($result/name() = 'sql:result' and $result/@updateCount >= 0) then
        (: rows deleted successfully :)
        app:clear-cache()
    else if ($result/name() = 'sql:exception') then
        error(xs:QName('collection:error'), 'Failed to delete granules for collection , sql:exception ' || $collection-id || ': ' || $result//sql:message/text())
    else
            error(xs:QName('collection:error'), 'Failed to delete granules for collection ' || $collection-id || ': ' || serialize($result))
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
 : Check whether the current user has access to collection or is superuser.
 : TODO make it work using string as input arg
 : @param $id-or-collection the id of the collection to test or the collection as XML fragment
 : @param $mode the partial mode to check against the collection e.g. 'rwx'
 : @return true() if current user has access to collection for the mode
 :)
declare function collection:has-access($id-or-collection as item(), $mode as xs:string) {
    let $collection := collection:get($id-or-collection)
    return if (empty($collection)) then
        error(xs:QName('collection:error'), 'No such collection.('||$id-or-collection||')')
    else
        (: check access to collection XML file :)
        let $path := document-uri(root($collection)) 
        return app:user-admin() or  ( if(exists($path)) then  sm:has-access($path , $mode) else false() )
};

(:~
 : Test if a collection is from a VizieR astronomical catalog.
 :
 : @param $c a <collection> element
 : @return true if the collection is from a VizieR catalog
 : 
 : Note: first catalogs have no coltype. OiDB V2.0.9 now replace source by coltype.
 :   We may update db content to avoir strats-with test
 :)
declare function collection:vizier-collection($c as element(collection)) as xs:boolean {
    $c/coltype=$collection:VIZIER_COLTYPE or starts-with(data($c/source), 'http://cdsarc.u-strasbg.fr/viz-bin/Cat')
};

(:~
 : Get collection type.
 : @param $id-or-collection the id of the collection to test or the collection as XML fragment
 : @return the value of coltype element or $collection:PUBLIC_COLTYPE if not present
 :)
declare function collection:get-type($id-or-collection as item()) as xs:string {
    let $collection := collection:get($id-or-collection)
    return if (empty($collection)) then
        error(xs:QName('collection:error'), 'No such collection.('||$id-or-collection||')')
    else
        let $type := $collection/coltype
        let $type := 
            if ($type) then 
                $type 
            else if (collection:vizier-collection($collection)) then 
                $collection:VIZIER_COLTYPE 
            else 
                $collection:PUBLIC_COLTYPE
        return $type[1]
};

declare function collection:get($id-or-collection) {
	if ($id-or-collection instance of xs:string) then
            collection:retrieve($id-or-collection)
        else if ($id-or-collection instance of node()) then
             $id-or-collection
        else
            error(xs:QName('collection:error'), 'Bad collection id ' || $id-or-collection || '.')
};

(:~
 : Get collection embargo period.
 : @param $id-or-collection the id of the collection to test or the collection as XML fragment
 : @return the duration of embargo or P0Y when collection is public 
 :)
declare function collection:get-embargo($id-or-collection as item()) as xs:duration {
    switch (collection:get-type($id-or-collection))
        case "suv" return xs:yearMonthDuration('P2Y')
        case "pionier" return xs:yearMonthDuration('P1Y')
        case "eso" return xs:yearMonthDuration('P1Y')
        case "chara" return xs:yearMonthDuration('P1Y6M')
        default return xs:yearMonthDuration('P0Y')
};

