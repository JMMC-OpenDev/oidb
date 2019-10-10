xquery version "3.0";

(:~
 : Perform an upload of all observations from VizierTap service querying B/eso catalog (ESO/VLTI).
 :
 : The observations previously imported by the same way are deleted.
 : 
 : All database operations in this script are executed within a 
 : transaction: if any failure occurs, the database is left unchanged.
 : 
 : It returns a <response> fragment with the status of the operation.
 :)

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";
import module namespace sql="http://exist-db.org/xquery/sql";
import module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/granule" at "granule.xqm";
import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";
import module namespace vizier="http://apps.jmmc.fr/exist/apps/oidb/vizier" at "vizier.xql";


import module namespace jmmc-eso="http://exist.jmmc.fr/jmmc-resources/eso";
import module namespace jmmc-vizier="http://exist.jmmc.fr/jmmc-resources/vizier" at "/db/apps/jmmc-resources/content/jmmc-vizier.xql";


declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";

(: job name :)
declare variable $local:name external;

(: the special collection name for ESO/VLTI imports :)
declare variable $local:collection := 'eso_vlti_import';


(:~
 : Push observation logs from votable in the database.
 : 
 : @param $handle a database connection handle
 : @param $votable observation logs from TapVizier:B/eso
 : @return a list of the ids of the new granules
 :)
declare function local:upload($handle as xs:long, $votable as node()*) as item()* {
    let $col-indexes := map:merge(  for $f at $pos in $votable//*:FIELD return map:entry(data($f/@name), $pos)  )
    let $rows := $votable//votable:TR
    let $nb-rows := count($rows)
    
    (: insert new granules in db :)
(:    for $tr at $pos in subsequence($votable//votable:TR,1,10) :)
    for $tr at $pos in $rows
    return try {
        let $log := if ( ( $pos mod 100 ) = 0 ) then util:log("info", "add new meta for eso ("|| $pos || "/" || $nb-rows || ")") else ()
        return 
        <id>{ granule:create(vizier:l0-metadata($tr, $col-indexes, $local:collection), $handle) }</id>
    } catch * {
        <warning>Failed to convert observation log to granule (row[{$pos}]:{  serialize($tr) }): { $err:description } { $err:value }</warning>
    }
};


declare function local:get-max-recno() as xs:integer{
    let $eso-collection := collection:retrieve($local:collection)
    return number($eso-collection//recno)
};

declare function local:update-max-recno($votable as node()) as xs:integer{
    let $eso-collection := collection:retrieve($local:collection)
    let $col-indexes := map:merge(  for $f at $pos in $votable//*:FIELD return map:entry(data($f/@name), $pos)  )
    let $recno-index := map:get($col-indexes,"recno")
    let $recnos := max( $votable//votable:TR/votable:TD[ $recno-index ] ) (: not sure that is is typed as number :)
    let $update := update replace $eso-collection//recno/text() with $recnos
    return $recnos
};

declare function local:get-votable($max-recno){
    let $query := "SELECT * FROM &quot;B/eso/eso_arc&quot; as e WHERE e.ObsTech LIKE '%INTERFEROMETRY%' AND e.recno > "||$max-recno
    return 
        jmmc-vizier:tap-adql-query($jmmc-vizier:TAP-SYNC, $query )
};

(:~
 : Push observation logs from votable in the database.
 : 
 : @param $handle a database connection handle
 : @param $votable observation logs from TapVizier:B/eso
 : @return a list of the ids of the new granules
 :)
declare function local:upload($handle as xs:long, $votable as node()) as item()* {
    let $log := util:log("info", "update eso L0 with given votable")

    let $col-indexes := map:merge(  for $f at $pos in $votable//*:FIELD return map:entry(data($f/@name), $pos)  )
    let $rows := $votable//votable:TR
    let $nb-rows := count($rows)
    
    (: insert new granules in db :)
    (:    for $tr at $pos in subsequence($votable//votable:TR,1,10) :)
    for $tr at $pos in $rows
    return try {
        let $log := if ( ( $pos mod 100 ) = 0 ) then util:log("info", "add new meta for eso ("|| $pos || "/" || $nb-rows || ")") else ()
        return 
(:            <id>FAKE</id>:)
        <id>{ granule:create(vizier:l0-metadata($tr, $col-indexes, $local:collection), $handle) }</id>
    } catch * {
        <warning>Failed to convert observation log to granule (row[{$pos}]:{  serialize($tr) }): { $err:description } { $err:value }</warning>
    }
};


let $stime := util:system-time()
let $log := util:log("info", "start")
let $response :=
    <response> {
        try {
            <success> {
                let $check-access := if(collection:has-access($local:collection, 'w')) then true() else error(xs:QName('granule:unauthorized'), 'Permission denied, can not write into '|| $local:collection ||'.')
                
                let $max-recno := local:get-max-recno() 
                let $log := util:log("info", "maxrecno="||$max-recno)
                let $votable  := local:get-votable($max-recno)
                
                let $ids := <ids>{sql-utils:within-transaction(local:upload(?, $votable))}</ids> 
                let $new-max-recno := if( count($ids/*)>0 ) then local:update-max-recno($votable) else ()
                let $log := util:log("info", "newmaxrecno="||$new-max-recno)

                let $duration := seconds-from-duration(util:system-time()-$stime)
                return (<info>{count($ids/id)} granules injected properly in {$duration} sec, { count($ids/*) div $duration }req/sec, old-max-recno={$max-recno}, new-max-recno={$new-max-recno}</info>, $ids/warning, <granuleOkCount>{count($ids/id)}</granuleOkCount>, <method>{ $local:name }</method>)
            } </success>
        } catch * {
            <error> { $err:code, $err:description } </error>
        }
    } </response>

return ( log:submit($response), $response )
