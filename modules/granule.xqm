xquery version "3.0";

(:~
 : This modules provides functions to manipulate granules and perform
 : conversion from XML granule to SQL row.
 :)
module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/granule";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";
import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";
import module namespace login="http://apps.jmmc.fr/exist/apps/oidb/login" at "login.xqm";


import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";
import module namespace jmmc-eso = "http://exist.jmmc.fr/jmmc-resources/eso";


declare %private function granule:format-nodes-for-sql-statement($data as node()*) as node()*{
    (: filter out the empty fields and datalink(s): keep default value for them :)
    let $nodes := ( $data[./node() and not(name()='datalink')] )

    (: add fail over for HMS DMS format even if obscore ask for deg values :)
    (: http://www.ivoa.net/documents/ObsCore/20170509/REC-ObsCore-v1.1-20170509.pdf  :)
    (: s_ra                   ,deg,double,Central right ascension, ICRS    :)
    (: s_dec                  ,deg,double,Central declination, ICRS        :)
    let $sexa-markers := (" ", ":")
    let $s_ra := normalize-space($data/self::s_ra)
    let $s_ra := element s_ra { if(contains($s_ra,$sexa-markers)) then jmmc-astro:from-hms($s_ra) else $s_ra }
    let $s_dec := normalize-space($data/self::s_dec)
    let $s_dec := element s_dec { if(contains($s_dec,$sexa-markers)) then jmmc-astro:from-dms($s_dec) else $s_dec}

    let $nodes := ( $nodes[not(name() = ("s_ra", "s_dec"))], $s_ra[text()], $s_dec[text()] )

    (: and nb_vis/nb_t3  we encountered N.0 in CHARA data :)

    let $el-names := ("nb_vis","nb_vis2","nb_t3")
    let $nb-els := for $elname in $el-names return
                    let $value := $data[name()=$elname]
                    return
                        if( $value ) then element {$elname} {number($value)} else ()

    let $nodes := ( $nodes[not(name() = $el-names)], $nb-els )

    return $nodes
};

(:~
 : Format a SQL INSERT statement for saving granule.
 :
 : The name of each node in input data is turned into a column name. The text
 : of each node is taken as the new value for the field.
 :
 : @param $data a sequence of nodes with row values
 : @param @try-update-on-conflict indicates to execute an update if "dup_granule_same_col" constraint of oidb db is thrown else keep simple insert statement.
 : @return a SQL INSERT statement
 :)
declare %private function granule:insert-statement($data as node()*, $try-update-on-conflict as xs:boolean) {
    let $nodes := granule:format-nodes-for-sql-statement($data)

    let $columns := for $x in $nodes return name($x)
    let $columns := "( " || string-join($columns, ', ') || " )"
    let $values  := for $x in $nodes return "'" || normalize-space(sql-utils:escape($x)) || "'"
    let $values  := "( " || string-join($values,  ', ') || " )"

    let $update-on-conflict := if($try-update-on-conflict) then
(:            "ON CONFLICT ON CONSTRAINT dup_granule_same_col DO UPDATE SET " || $columns || " = " || $values || ", subdate = DEFAULT":)
            "ON  CONFLICT (obs_id, obs_collection, instrument_mode) WHERE calib_level=0 DO UPDATE SET " || $columns || " = " || $values || ", subdate = DEFAULT"
        else
            ()

    return
        string-join((
            "INSERT INTO",
            $config:sql-table,
            $columns,
            "VALUES",
            $values,
            $update-on-conflict,
            (: Note: PostgreSQL extension :)
            "RETURNING id"
            )," ")
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
    let $values  := ( $id , for $x in $nodes return "'" || sql-utils:escape($x) || "'" )
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


declare function granule:add-datalink($id as xs:integer, $datalink as node(), $handle as xs:long) {
    if (granule:has-access($id, 'w', $handle)) then
        let $statement := granule:insert-datalink-statement($id, $datalink/*)
        let $result := sql-utils:execute($handle, $statement, false())

        return if ($result/name() = 'sql:result') then
            (: row updated successfully :)
            ()
        else if ($result/name() = 'sql:exception') then
            error(xs:QName('granule:error'), 'Failed to update granule ' || $id || ': ' || $result//sql:message/text() )
        else
            error(xs:QName('granule:error'), 'Failed to update granule ' || $id || '.')
    else
        error(xs:QName('granule:unauthorized'), 'Permission denied.')
};

(:~
 : Save a new granule in the SQL database and return the ID of the row.
 :
 : @param $granule the granule contents
 : @return the id of the new granule
 : @error failed to save, unauthorized
 :)
declare function granule:create($granule as node()) as xs:integer {
    granule:create($granule, sql-utils:get-jndi-connection())
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
    granule:do-create($granule, false(), $handle)
};

declare function granule:create-or-update($granule as node(), $handle as xs:long) as xs:integer {
    granule:do-create($granule, true(), $handle)
};


(:~
 : Save a new granule in the SQL database and return the ID of the row.
 :
 : @param $granule the granule contents
 : @param $try-update-on-conflict indicates if sql should add update code on conflict or not
 : @param $handle  the SQL database handle
 : @return the id of the new granule
 : @error failed to save, unauthorized
 :)
declare function granule:do-create($granule as node(), $try-update-on-conflict as xs:boolean, $handle as xs:long) as xs:integer {
    let $collection := xs:string($granule/obs_collection/text())
    let $check-collection := if(exists($collection)) then true() else error(xs:QName('granule:error'), 'obs_collection is not present in given granule.')
    let $check-access := if(collection:has-access($collection, 'w')) then true() else error(xs:QName('granule:unauthorized'), 'Permission denied, can not write into ' || $collection ||'.')

(:
 :  if coltype != 'public' then
 :  1/    set data_rights to 'secure'
 :        get appropriate release_date with embargo (may be in the past) : PIONIER->1Y, suv->2Y
 :        if release_date is in the future and oifits are local files:
 :           limit permissions to the owner
 :           schedule a timer to open data access
 :  TODO :
 :  2/   handle group access
 :)

    let $embargo := collection:get-embargo ($collection)
    let $coltype := collection:get-type($collection)

    let $data_rights :=         if( $granule/data_rights ) then
                                    () (: keep verbatim metadata  :)
                                else if(exists($embargo)) then
                                    <data_rights>secure</data_rights>
                                else
                                    ()

    let $obs_release_date :=    if( $granule/obs_release_date ) then
                                    () (: keep verbatim metadata  :)
                                else if( exists($granule/t_max) and ($granule/data_rights, $data_rights)="secure" ) then
                                    (: FIXME try to get release_date from L0 or fall back to next basic computation relying on t_max :)
                                    let $embargo := if (granule:is-science($granule)) then $embargo else xs:yearMonthDuration('P0Y')
                                    return
                                        <obs_release_date>
                                            {substring(string(jmmc-dateutil:MJDtoISO8601($granule/t_max) + $embargo) , 0, 22) }
                                        </obs_release_date>
                                else
                                    util:log("info", "obs_release_date not present ?? data_rights="||$data_rights)
                                    (: TODO check that this empty case is normal :)


    let $release_date := if( $obs_release_date ) then $obs_release_date else $granule/obs_release_date

    (: do not try to compute datetime from L3 since it is only the associated publication date :)
    let $manage-local-data :=   if( $granule/calib_level != 3 and starts-with($granule/access_url,"/") and exists($release_date) ) then
                                    let $in-future :=   ( xs:dateTime($release_date) - fn:current-dateTime() ) > xs:dayTimeDuration("P0D")
                                    return if ($in-future) then
                                        let $oifits-path := xs:anyURI(replace($granule/access_url, "/exist/apps/oidb-data/", "/db/apps/oidb-data/"))
                                        let $fix-oifits-perm := sm:chmod($oifits-path, "rwx------")
                                        let $log := util:log('info', 'perm restricted for '|| $oifits-path || ' for collection type '||$coltype)
                                        let $todo := util:log('info',"TODO : register a timer for " || $oifits-path)
                                        return
                                            ()
                                    else
                                        let $log := util:log('info', 'perm leaved public for '|| $granule/access_url || ' in collection type '||$coltype|| ' : release_date in past')
                                        return
                                            ()
                                else
                                    ()

    let $datapi := if (exists($granule/datapi/text())) then
            $granule/datapi/text()
        else if($coltype="chara") then
            element {"datapi"} {login:user-name()}
        else
            let $progid := $granule/progid/text()
            (: assume that we are on a eso case with a given progid :)
            let $pi := if($progid) then try{jmmc-eso:get-pi-from-progid($progid)}catch *{login:user-name()} else login:user-name()
            return if($pi) then element {"datapi"} {$pi} else ()


    let $insert-statement := granule:insert-statement(( $granule/*, $data_rights, $obs_release_date, $datapi), $try-update-on-conflict)

    let $result := sql-utils:execute($handle, $insert-statement, false())
    let $id := if ($result/name() = "sql:exception")
        then
            let $info :=  string-join( ("", "granule metadata where:", for $e in $granule/* return name($e)||"="||$e, ""), "&#10;")
            return
            error(xs:QName('granule:error'), 'Failed to upload: ' || $result//sql:message/text() || ', query: ' || $insert-statement || $info)
        else
	    (: may cause an issue if called too quickly :)
            let $clear-cache :=  app:clear-cache()
            return
                (: return the id of the inserted row :)
                $result//sql:field[@name='id'][1]
    let $datalinks := for $datalink in $granule/datalink
            let $insert-statement := granule:insert-datalink-statement($id, $datalink/*)
            let $result := sql-utils:execute($handle, $insert-statement, false())
            return
                if ($result/name() = "sql:exception") then
                    error(xs:QName('granule:error'), 'Failed to upload datalink: ' || $result//sql:message/text() || ', query: ' || $insert-statement)
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
    granule:retrieve($id, sql-utils:get-jndi-connection())
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
    let $result := sql-utils:execute($handle, $statement, false())

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
declare %private function granule:update-statement($id as xs:integer, $data as node()*) as xs:string? {
    if(empty($data)) then "SELECT 1 LIMIT 0"
    else
        let $columns := for $x in $data return name($x)
        let $values  := for $x in $data return if ($x/node()) then "'" || normalize-space(sql-utils:escape($x)) || "'" else "NULL"
        (: TODO we could check that subdate is updated - or maybe add an additional column for that :)
        return string-join((
            "UPDATE", $config:sql-table,
            "SET", string-join(fn:for-each-pair($columns, $values, function ($c, $v) { $c || '=' || $v } ), ', '),
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
declare function granule:update($id as xs:integer, $data as node())  {
    granule:update($id, $data, sql-utils:get-jndi-connection())
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
declare function granule:update($id as xs:integer, $data as node(), $handle as xs:long)  {
    if (granule:has-access($id, 'w', $handle)) then
        (: protect the id column :)
        let $statement := granule:update-statement($id, $data/*[name() != 'id'])
        let $result := sql-utils:execute($handle, $statement, false())

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
declare function granule:delete($id as xs:integer)  {
    granule:delete($id, sql-utils:get-jndi-connection())
};

(:~
 : Remove the granule with the given ID.
 :
 : @param $id     the id of the granule to delete
 : @param $handle the SQL database handle
 : @return empty
 : @error failed to delete, unauthorized
 :)
declare function granule:delete($id as xs:integer, $handle as xs:long)  {
    if (granule:has-access($id, 'w', $handle)) then
        let $statement := granule:delete-statement($id)
        let $result := sql-utils:execute($handle, $statement, false())

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
 : @param $handle the SQL database handle
 : @return true() if current user has access to granule for the mode
 :)
declare function granule:has-access($id-or-granule as item(), $mode as xs:string, $handle as xs:long) {
    if (app:user-admin()) then
        true()
    else
        let $granule :=
            if ($id-or-granule instance of node()) then
                $id-or-granule
            else if ($id-or-granule instance of xs:integer) then
                granule:retrieve($id-or-granule, $handle)
            else
                error(xs:QName('granule:error'), 'Bad granule id ' || $id-or-granule || '.')
        return
            if ($granule/obs_collection/node()) then
                (: granule part of a collection: apply permissions from collection :)
                let $collection := $granule/obs_collection/text()
                return collection:has-access($collection, $mode)
            else
                (: TODO check datapi column and current user? store owner? :)
                false()
};

(:~
 : Tell if given granule describe metadata for a SCIENCE OBJECT.
 :
 : @param $granule the granule to analyse.
 : @return true if dataproduct_category is null or has SCIENCE value, else false
 :)
declare function granule:is-science($granule){
    let $dpcat := $granule/dataproduct_category
    return empty($dpcat) or upper-case($dpcat)=("SCIENCE")
};
