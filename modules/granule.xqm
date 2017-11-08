xquery version "3.0";

(:~
 : This modules provides functions to manipulate granules and perform
 : conversion from XML granule to SQL row.
 :)
module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/granule";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";
import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";

(:~
 : Format a SQL INSERT statement for saving granule.
 : 
 : The name of each node in input data is turned into a column name. The text 
 : of each node is taken as the new value for the field.
 : 
 : @param $data a sequence of nodes with row values
 : @return a SQL INSERT statement
 :)
declare %private function granule:insert-statement($data as node()*) {
    let $obs_release_date :=    if($data/self::obs_release_date) then
                                    () (: node is already in metadata :)
                                else if($data/self::data_rights="secure") then
                                    (: compute obs_release_date with t_max + embargo duration 
                                       TODO put this constant out and make it adjustable by user before submission if consensus 
                                    :)
                                    <obs_release_date>
                                        {substring(string(jmmc-dateutil:MJDtoISO8601($data/self::t_max) + xs:yearMonthDuration('P1Y')) , 0, 22) }
                                    </obs_release_date>
                                else
                                    () (: TODO check that this empty case is normal :)
    (: filter out the empty fields and datalink(s): keep default value for them :)
    let $nodes := ( $data[./node() and not(name()='datalink')], $obs_release_date )
    let $columns := for $x in $nodes return name($x)
    let $values  := for $x in $nodes return "'" || utils:escape($x) || "'"
    return
        concat(
            "INSERT INTO ",
            $config:sql-table,
            " ( " || string-join($columns, ', ') || " ) ",
            "VALUES",
            " ( " || string-join($values,  ', ') || " ) ",
            (: Note: PostgreSQL extension :)
            "RETURNING id")
};


(:~
 : Format a SQL INSERT statement for saving a datalink for a given granule id.
 : 
 : The name of each node in input data is turned into a column name. The text 
 : of each node is taken as the new value for the field.
 : 
 : @param $id granule id
 : @param $data a sequence of nodes with row values
 : @return a SQL INSERT statement
 :)
declare %private function granule:insert-datalink-statement($id as xs:integer, $data as node()*) {
    (: filter out the empty fields: keep default value for them :)
    let $nodes := ( $data[./node()] )
    let $columns := ( 'ID' , for $x in $nodes return name($x) )
    let $values  := ( $id , for $x in $nodes return "'" || utils:escape($x) || "'" )
    return
        concat(
            "INSERT INTO ",
            $config:sql-datalink-table,
            " ( " || string-join($columns, ', ') || " ) ",
            "VALUES",
            " ( " || string-join($values,  ', ') || " ) ",
            (: Note: PostgreSQL extension :)
            "RETURNING id")
};

(:~
 : Save a new granule in the SQL database and return the ID of the row.
 : 
 : @param $granule the granule contents
 : @return the id of the new granule
 : @error failed to save, unauthorized
 :)
declare function granule:create($granule as node()) as xs:integer {
    granule:create($granule, config:get-db-connection())
};

(:~
 : Save a new granule in the SQL database and return the ID of the row.
 : 
 : @param $granule the granule contents
 : @param $handle  the SQL database handle
 : @return the id of the new granule
 : @error failed to save, unauthorized
 :)
declare function granule:create($granule as node(), $handle as xs:long) as xs:integer {
    let $collection := xs:string($granule/obs_collection/text())
    let $check-collection := if(exists($collection)) then true() else error(xs:QName('granule:error'), 'obs_collection is not present in given granule.')
    let $check-access := if(collection:has-access($collection, 'w')) then true() else error(xs:QName('granule:unauthorized'), 'Permission denied, can not write into '|| $collection ||'.')
    
    let $statement := granule:insert-statement($granule/*)
    let $result := sql:execute($handle, $statement, false())
    let $id := if ($result/name() = "sql:exception") 
        then
            error(xs:QName('granule:error'), 'Failed to upload: ' || $result//sql:message/text() || ', query: ' || $statement)
        else
            let $clear-cache :=  app:clear-cache()
            return
                (: return the id of the inserted row :)
                $result//sql:field[@name='id'][1]
    
    let $datalinks := for $datalink in $granule/datalink
            let $statement := granule:insert-datalink-statement($id, $datalink/*)
            let $result := sql:execute($handle, $statement, false())
            return 
                if ($result/name() = "sql:exception") then
                    error(xs:QName('granule:error'), 'Failed to upload datalink: ' || $result//sql:message/text() || ', query: ' || $statement)
                else 
                    ()
    
    
    return $id
};

(:~
 : Format a SQL SELECT request with the given granule id.
 : 
 : @param $id the id of the row to delete
 : @return a SQL SELECT statement
 :)
declare %private function granule:select-statement($id as xs:integer) as xs:string {
    "SELECT * FROM " || $config:sql-table || " AS t WHERE t.id='" || $id || "'"
};

(:~
 : Return a granule given its ID.
 : 
 : @note
 : It returns the values from all columns of the table not only the one exported 
 : through TAP.
 : 
 : @param $id     the id of the granule to find
 : @param $handle the SQL database handle
 : @return a <granule> element for given ID or empty if not found
 : @error no such granule
 :)
declare function granule:retrieve($id as xs:integer) {
    granule:retrieve($id, config:get-db-connection())
};

(:~
 : Return a granule given its ID.
 : 
 : @note
 : It returns the values from all columns of the table not only the one exported 
 : through TAP.
 : 
 : @param $id     the id of the granule to find
 : @param $handle the SQL database handle
 : @return a <granule> element for given ID
 : @error no such granule
 :)
declare function granule:retrieve($id as xs:integer, $handle as xs:long) as node()? {
    let $statement := granule:select-statement($id)
    let $result := sql:execute($handle, $statement, false())
    
    let $granule :=
        if ($result/name() = 'sql:result' and $result/@count = 1) then
            let $row := $result/sql:row
            (: transform row into XML granule :)
            return <granule>{
                for $field in $row/sql:field return element { $field/@name } { $field/text() }
            }</granule>
        else
            (: no matching granule found :)
            error(xs:QName('granule:unknown'), 'No granule found with id ' || $id || '.')

    return $granule
};

(:~
 : Format a SQL UPDATE statement for modifying granule with specified values.
 : 
 : The name of each node in input data is turned into a column name. The text 
 : of each node is taken as the new value for the field.
 : 
 : @param $id   the id of the granule to modify
 : @param $data a sequence of nodes with new values
 : @return a SQL INSERT statement
 :)
declare %private function granule:update-statement($id as xs:integer, $data as node()*) as xs:string {
    let $columns := for $x in $data return name($x)
    let $values  := for $x in $data return if ($x/node()) then "'" || utils:escape($x) || "'" else "NULL"
    (: TODO we could check that subdate is updated - or maybe add an additional column for that :)
    return string-join((
        "UPDATE", $config:sql-table,
        "SET", string-join(map-pairs(function ($c, $v) { $c || '=' || $v }, $columns, $values), ', '),
        "WHERE id='" || $id || "'"
    ), ' ')
};

(:~
 : Modify an existing granule identified by its ID.
 : 
 : @param $id   the id of the granule to modify
 : @param $data the new content of the granule
 : @return empty
 : @error failed to update granule, unauthorized
 :)
declare function granule:update($id as xs:integer, $data as node()) as empty() {
    granule:update($id, $data, config:get-db-connection())
};

(:~
 : Modify an existing granule identified by its ID.
 : 
 : @param $id     the id of the granule to modify
 : @param $data   the new content of the granule
 : @param $handle the SQL database handle
 : @return empty
 : @error failed to update granule, unauthorized
 :)
declare function granule:update($id as xs:integer, $data as node(), $handle as xs:long) as empty() {
    if (granule:has-access($id, 'w')) then
        (: protect the id column :)
        let $statement := granule:update-statement($id, $data/*[name() != 'id'])
        let $result := sql:execute($handle, $statement, false())

        return if ($result/name() = 'sql:result' and $result/@updateCount = 1) then
            (: row updated successfully :)
            app:clear-cache()
        else if ($result/name() = 'sql:exception') then
            error(xs:QName('granule:error'), 'Failed to update granule ' || $id || ': ' || $result//sql:message/text())
        else
            error(xs:QName('granule:error'), 'Failed to update granule ' || $id || '.')
    else
        error(xs:QName('granule:unauthorized'), 'Permission denied.')
};

(:~
 : Format an SQL DELETE request with the given granule id.
 : 
 : @param $id the id of the row to delete
 : @return a SQL DELETE statement
 :)
declare %private function granule:delete-statement($id as xs:integer) as xs:string {
    "DELETE FROM " || $config:sql-table || " WHERE id='" || $id || "'"
};

(:~
 : Remove the granule with the given ID.
 : 
 : @param $id the id of the granule to delete
 : @return empty
 : @error failed to delete, unauthorized
 :)
declare function granule:delete($id as xs:integer) as empty() {
    granule:delete($id, config:get-db-connection())
};

(:~
 : Remove the granule with the given ID.
 : 
 : @param $id     the id of the granule to delete
 : @param $handle the SQL database handle
 : @return empty
 : @error failed to delete, unauthorized
 :)
declare function granule:delete($id as xs:integer, $handle as xs:long) as empty() {
    if (granule:has-access($id, 'w')) then
        let $statement := granule:delete-statement($id)
        let $result := sql:execute($handle, $statement, false())

        return if ($result/name() = 'sql:result' and $result/@updateCount = 1) then
            (: row deleted successfully :)
            app:clear-cache()
        else if ($result/name() = 'sql:exception') then
            error(xs:QName('granule:error'), 'Failed to delete granule ' || $id || ': ' || $result//sql:message/text())
        else
            error(xs:QName('granule:error'), 'Failed to delete granule ' || $id || '.')
    else
        error(xs:QName('granule:unauthorized'), 'Permission denied.')
};

(:~
 : Check whether the current user has access to a granule.
 : 
 : @param $id-or-granule the id of the granule to test or the granule as XML fragment
 : @param $mode the partial mode to check against the granule e.g. 'rwx'
 : @return true() if current user has access to granule for the mode
 :)
declare function granule:has-access($id-or-granule as item(), $mode as xs:string) {
    let $granule :=
        if ($id-or-granule instance of node()) then
            $id-or-granule
        else if ($id-or-granule instance of xs:integer) then
            granule:retrieve($id-or-granule)
        else
            error(xs:QName('granule:error'), 'Bad granule id ' || $id-or-granule || '.')
    return
        if ($granule/obs_collection/node()) then
            (: granule part of a collection: apply permissions from collection :)
            let $collection := $granule/obs_collection/text()
            return collection:has-access($collection, $mode)
        (: authorize dba :)
        (: FIXME stick with old API until fix for upstream bug #388 is released :)
        else if (xmldb:is-admin-user(xmldb:get-current-user())) then
            true()
        (: authorize the application admins :)
        (: FIXME use sm:id() instead when fix for upstream bug #388 is released :)
        else if (sm:get-user-groups(xmldb:get-current-user()) = 'oidb') then
            true()
        else
            (: TODO check datapi column and current user? store owner? :)
            false()
};
