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



import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-eso="http://exist.jmmc.fr/jmmc-resources/eso";


declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";

(: path to the VOTABLE file in database when running from scheduler (job parameter) :)
declare variable $local:resource external;
(: job name :)
declare variable $local:name external;

(: the special collection name for ESO/VLTI imports :)
declare variable $local:collection := 'eso_vlti_import';

(:~
 : Remove all Vega records from a previous import.
 : 
 : @param $handle a database connection handle
 :)
declare function local:delete-collection($handle as xs:long) {
    app:clear-cache(),
    sql-utils:execute($handle, "DELETE FROM " || $config:sql-table || " WHERE obs_collection='" || $local:collection || "';", false())
};


(:~
 : Turn a row observation into a metadata fragment for upload.
 : 
 : @param $row an observation 
 : @return a 'metadata' element for the observation
 :)
declare function local:metadata($row as node(), $col-indexes as map(xs:string, xs:integer)) as node() {
(:    let $idx-DEJ2000:=1 (:  :):)
(:    let $idx-ObsName:=2 (: Observation name (3) :):)
(:    let $idx-Rel_date:=3 (: Release date of data :):)
(:    let $idx-tExp:=4 (:  Exposure time :):)
(:    let $idx-Filter:=5 (: Filter Path (4) :):)
(:    let $idx-Slit:=6 (: Slit Path (4) :):)
(:    let $idx-InstrID:=7 (: Instrument identification :):)
(:    let $idx-Obs:=8 (: Observation start date (UT) :):)
(:    let $idx-naxis2:=9 (:  Detector size in Y direction :):)
(:    let $idx-naxis1:=10 (:  Detector size in X direction :):)
(:    let $idx-ProgID:=11 (: Program identification :):)
(:    let $idx-recno:=12 (: Record number assigned by the VizieR team. Should Not be used for identification. :):)
(:    let $idx-InstMode:=13 (: Instrument mode (4) :):)
(:    let $idx-Grism:=14 (: Grism Path (4) :):)
(:    let $idx-Target:=15 (: Target name (3) :):)
(:    let $idx-Grating:=16 (: Grating Path (4) :):)
(:    let $idx-TelID:=17 (: Code which refers to the ESO telescope (\aW{_340x600}{\glutag{Cat.file,u B/eso/eso-tel.htx}}{list of the codes}) :):)
(:    let $idx-AirMass:=18 (: AirMass :):)
(:    let $idx-ObsTech:=19 (: Observation technique (2) :):)
(:    let $idx-DataID:=20 (: Dataset identification :):)
(:    let $idx-RAJ2000:=21 (:  :):)
    

    let $values := $row/*

    let $target-name   := $values[ map:get($col-indexes,"Target")  ]
    let $ra            := $values[ map:get($col-indexes,"RAJ2000") ]
    let $dec           := $values[ map:get($col-indexes,"DEJ2000") ]
    
    let $ut            := $values[ map:get($col-indexes,"Obs") ]
    let $t-min         := jmmc-dateutil:UTtoMJD($ut,())
    let $t-exp          := $values[ map:get($col-indexes,"tExp") ]
    let $t-exp          := if(string-length($t-exp)>0) then $t-exp else 0
    let $t-max         := try {jmmc-dateutil:UTtoMJD($ut + $t-exp ,())} catch * { $t-min }
    let $release-date  := jmmc-dateutil:JDtoISO8601( $values[ map:get($col-indexes,"Rel_date") ] )
    
    let $facility-name := "VLTI"
    let $prog-id       := $values[ map:get($col-indexes,"ProgID") ]
    let $obs-id        := $values[ map:get($col-indexes,"DataID") ]
    let $obs-creator   := "ESO"
    
    (:    let $data-pi       := if( exists($prog-id)) then jmmc-eso:get-pi-from-progid($prog-id) else ():)
    (: decided to be left blank on 2018-dec with XH :)
    let $data-pi       := ""
    let $bib-ref       := "" (: if( exists($prog-id)) then http://telbib.eso.org/api.php?programid= :)
    
    
    let $ins-name      := $values[ map:get($col-indexes,"InstrID") ]
(:    let $tel-conf    := "NOT USED in ObsCore schema" (: We could resolv TelId :):)
    
    let $ins-mode      :=  $values[ map:get($col-indexes,"InstMode") ]
    let $nb-channels   := -1 (: get it from InstMode x AsprocConf + Filter :)
    let $em-min        := 0 
    let $em-max        := 0
    
    
    return <metadata> {
        (: all entries are L0 :)
        <calib_level>0</calib_level>,
        <target_name>{ $target-name }</target_name>,
        <datapi>{ $data-pi }</datapi>,
        <obs_collection>{ $local:collection }</obs_collection>,
        <obs_creator_name>{ $obs-creator}</obs_creator_name>,
        <obs_release_date>{ $release-date}</obs_release_date>,
        <obs_id>{ $obs-id }</obs_id>,
        <progid>{ $prog-id }</progid>,
        <s_ra>  { $ra } </s_ra>,
        <s_dec> { $dec } </s_dec>,
        <t_min> { $t-min } </t_min>,
        <t_max> { $t-max } </t_max>,
        <t_exptime>{ $t-exp }</t_exptime>, (: FIXME :)
        <em_min>{ $em-min }</em_min>,
        <em_max>{ $em-max }</em_max>,
        <em_res_power>-1</em_res_power>, (: FIXME :)
        <facility_name>{$facility-name}</facility_name>,
        <instrument_name>{$ins-name}</instrument_name>,
        <instrument_mode>{ $ins-mode }</instrument_mode>,
        <nb_channels>{$nb-channels}</nb_channels>,
        (: FIXME  below :)
        (: nb_vis, nb_vis2 and nb_t3 left empty :)
        <data_rights>public</data_rights>,
        <access_url>-/-</access_url> (: FIXME no file :)
    } </metadata>
};

(:~
 : Push observation logs from votable in the database.
 : 
 : @param $handle a database connection handle
 : @param $votable observation logs from TapVizier:B/eso
 : @return a list of the ids of the new granules
 :)
declare function local:upload($handle as xs:long, $votable as node()*) as item()* {
    (: remove old data from db :)
    let $delete := local:delete-collection($handle)
    
    let $col-indexes := map:merge(  for $f at $pos in $votable//*:FIELD return map:entry(data($f/@name), $pos)  )
 
    let $rows := $votable//votable:TR
    
    let $nb-rows := count($rows)
    
    (: insert new granules in db :)
(:    for $tr at $pos in subsequence($votable//votable:TR,1,10) :)
    for $tr at $pos in $rows
    return try {
        let $log := if ( ( $pos mod 100 ) = 0 ) then util:log("info", "add new meta for eso ("|| $pos || "/" || $nb-rows || ")") else ()
        return 
        <id>{ granule:create(local:metadata($tr, $col-indexes), $handle) }</id>
    } catch * {
        <warning>Failed to convert observation log to granule (row[{$pos}]:{  serialize($tr) }): { $err:description } { $err:value }</warning>
    }
};

let $stime := util:system-time()
let $response :=
    <response> {
        try {
            <success> {
                let $check-access := if(collection:has-access($local:collection, 'w')) then true() else error(xs:QName('granule:unauthorized'), 'Permission denied, can not write into '|| $local:collection ||'.')
                let $new := doc($local:resource)
                let $ids := <ids>{sql-utils:within-transaction(local:upload(?, $new))}</ids> 
(:                let $ids := <ids></ids>:)
                let $duration := seconds-from-duration(util:system-time()-$stime)
                return (<info>{count($ids/id) || " granules injected properly"}  in {$duration}sec, { count($ids/*) div $duration }req/sec</info>, $ids/warning, <granuleOkCount>{count($ids/id)}</granuleOkCount>, <method>{$local:name}</method>)
(:                return $ids:)
            } </success>
        } catch * {
            <error> { $err:code, $err:description } </error>
        }
    } </response>

return ( log:submit($response), $response )
