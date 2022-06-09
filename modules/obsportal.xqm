xquery version "3.0";

(:~
 : This modules interacts with the Obsportal Web service to query and retrieve
 : data from their database.
 :)
 
module namespace obsportal="http://apps.jmmc.fr/exist/apps/oidb/obsportal";

import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "/db/apps/oidb/modules/collection.xqm";
import module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/granule" at "granule.xqm";
import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.4";

(: Service's base url :)
declare variable $obsportal:OBSPORTAL_URL := "http://obs.jmmc.fr/search.votable";

(: Get OiDB collection assocaited to an obsportal subcollection.
 : Will be used in the futur. First implementation fakes ESO L0 at first.
 :)
declare function obsportal:get-collection-id($obs-collection as xs:string) as xs:string 
{   
(:    switch ($obs-collection):)
(:        case "tbdinthefuture" return 'tbd':)
(:        default return :)
            'eso_vlti_import'
};

(:~
 : Remove all records from previous import.
 : 
 : @param $handle a database connection handle
 :)
declare function obsportal:delete-collection-records($collection as xs:string, $handle as xs:long) {
    collection:delete-granules( obsportal:get-collection-id($collection), $handle )
};

(:~
 : Transform the rows of a VOTable into observations.
 : 
 : @param $votable a XML VOTable from VegaObs
 : @return a sequence of 'observation' elements
 :)
declare %private function obsportal:votable-observations($votable as node()) as node()* {
    let $header_names := $votable//votable:FIELD/@name
    let $rows := $votable//votable:TABLEDATA/votable:TR
    for $row in $rows
    return <observation> {
        for $cell at $i in $row/votable:TD
        return element { $header_names[$i] } { $cell/node() }
    } </observation>
};

(:~
 : Query all observations.
 : 
 : @return a sequence of observations
 :)
declare function obsportal:get-observations( ) as node()* {
    obsportal:get-observations( (), () )
};

(:~
 : Query all observations between given interval if given.
 : Timezone are ignored (TBC).
 : 
 : @return a sequence of observations
 :)
declare function obsportal:get-observations( $date_updated_from as xs:dateTime?, $date_updated_to as xs:dateTime?) as node()* {
    (: We have to add tzinfo to avoid a 500 crash :)
    let $tzinfo := "%2B00:00"
    
    let $date_updated_from := if(exists($date_updated_from)) then "date_updated_from="||adjust-dateTime-to-timezone(xs:dateTime(tokenize($date_updated_from,"\.")[1]), ())||$tzinfo else ()
    let $date_updated_to := if(exists($date_updated_to)) then "date_updated_to="||adjust-dateTime-to-timezone(xs:dateTime(tokenize($date_updated_to,"\.")[1]), ())||$tzinfo else ()
    
    let $date-range := if(exists($date_updated_from) or exists($date_updated_to)) then string-join(($date_updated_from,$date_updated_to), "&amp;") else ()
    
    let $votable-url := $obsportal:OBSPORTAL_URL||"?"||$date-range

    let $votable := doc($votable-url)
    let $log := util:log("info", "received votable from url : " || $votable-url)
    
    return 
        obsportal:votable-observations($votable)
};


(:~
 : Turn an observation into a granule fragment for upload.
 : 
 : @param $observation an observation
 : @return a 'metadata' element for the observation
 :)
declare function obsportal:metadata($observations as node()*, $collection as xs:string) as node()* {
    for $observation in $observations
        return 
        let $calib_level := "0"
        let $target-name := normalize-space(data($observation/target_name))
        let $target-name := if (string-length($target-name) > 0) then $target-name else '-' (: WORKARROUND so target_name always present :)
        let $obs_id := data($observation/exp_id) (: WARNING stored obs_id is the one prepared by obsportal and not ESO compatible :)
        let $obs_creator_name := "jmmc-tech-group - Bourgès"
        let $obs_release_date := data($observation/exp_date_release)
        let $data_rights := "secure"
        let $access_url := "http://archive.eso.org/wdb/wdb/eso/eso_archive_main/query?dp_id="||$observation/exp_header_id (: use forwared original obs_id :)
        let $s_ra := data($observation/target_ra)
        let $s_dec := data($observation/target_dec)
        let $t_min := data($observation/exp_mjd_start)
        let $t_max := data($observation/exp_mjd_end)
        let $t_exptime := seconds-from-duration(($t_max - $t_min)*xs:dayTimeDuration('PT24H'))
        let $t_exptime := round-half-to-even($t_exptime,3)
        let $em_min := data($observation/instrument_em_min)
        let $em_max := data($observation/instrument_em_max)
        let $em_res_power := data($observation/instrument_em_res_power)
        let $facility_name := data($observation/interferometer_name)
        let $instrument_name := data($observation/instrument_name)
        let $instrument_mode := data($observation/instrument_mode)
        let $submode := data($observation/instrument_submode)
    (:  lets try with the submdode (present in 15%) :)
        let $instrument_mode := if (exists($submode)) then $instrument_mode || "_" || $submode else $instrument_mode
        let $interferometer_stations := data($observation/interferometer_stations)
    (:TODO    let $nb_channels := $todo:)
        let $nb_channels := "-1"
        let $progid := data($observation/obs_program)
        let $dataproduct_category := upper-case($observation/obs_type)
    
    (:TODO cache programId -> datapi :)
        
        return <metadata> {
            (: all entries are L0 :)
            <calib_level>{ $calib_level }</calib_level>,
            <target_name>{ $target-name }</target_name>,
    (:NOT TODO here but to cache for later l2 associations  <datapi>{ $data-pi }</datapi>,:)
            <obs_collection>{ $collection }</obs_collection>,
            <obs_creator_name>{ $obs_creator_name } </obs_creator_name>,
            <obs_release_date>{ $obs_release_date } </obs_release_date>,
            <obs_id>{ $obs_id }</obs_id>,
            <data_rights>{ $data_rights }</data_rights>,
            <access_url>{ $access_url }</access_url>,
            <s_ra>  { $s_ra } </s_ra>,
            <s_dec> { $s_dec } </s_dec>,
            <t_min> { $t_min } </t_min>,
            <t_max> { $t_max } </t_max>,
            <t_exptime>{ $t_exptime }</t_exptime>, 
            <em_min>{ $em_min }</em_min>,
            <em_max>{ $em_max }</em_max>,
            <em_res_power>{ $em_res_power }</em_res_power>,
            <facility_name>{ $facility_name }</facility_name>,
            <instrument_name>{ $instrument_name }</instrument_name>,
            <instrument_mode>{ $instrument_mode }</instrument_mode>,
            <progid>{ $progid }</progid>,
            <interferometer_stations>{ $interferometer_stations}</interferometer_stations>,
            <nb_channels>{$nb_channels}</nb_channels>,
            <dataproduct_category>{$dataproduct_category}</dataproduct_category>
        } </metadata>
};

(:~
 : Push observation logs in the database.
 : 
 : @param $handle a database connection handle
 : @param $observations observation logs from ObsPortal
 : @return a list of the ids of the new granules
 :)
declare function obsportal:upload($handle as xs:long, $collection as xs:string, $observations as node()*) as item()* {
    (: insert new granules in db :)
    let $nb-observations := count($observations)
    let $each := floor($nb-observations div 10)
    let $ret := for $o at $pos in $observations
    return try {
        (
            <id>{ granule:create-or-update(obsportal:metadata($o, $collection), $handle) }</id>
            , if($pos mod $each = 1) then util:log("info", $pos || " sql insert done over "||$nb-observations||" records") else ()
        )
    } catch * {
        <warning>Failed to convert observation log to granule (ObsPortal ID { $o/exp_id/text() }): { $err:description } { $err:value }</warning>
    }
    
    let $log := util:log("info", "end of obsportal collection upload")
    return $ret
};

declare function obsportal:get-last-mod-date($col-id as xs:string) as xs:dateTime?{
    let $collection := collection:retrieve($col-id)
    return 
        try {
            xs:dateTime($collection//em[@id='last-mod-date'])    
        } catch * {
            ()
        }
};

declare function obsportal:get-last-exp_date_updated($observations as node()*) as xs:dateTime ? {
    let $last-mod-date := (for $obs in $observations let $d := xs:dateTime(translate(normalize-space($obs/exp_date_updated), " ", "T")) order by $d descending return $d)[1]
    return $last-mod-date
};

declare function obsportal:set-last-mod-date($col-id as xs:string, $last-mod-date as xs:dateTime?) {
    if(exists($last-mod-date)) then 
        let $collection := collection:retrieve($col-id)
        let $log := util:log("info", "set '"|| $last-mod-date ||"' as last-mod-date of '"||$col-id||"' collection")
        return 
            update replace $collection//em[@id='last-mod-date']/text() with $last-mod-date
    else
        ()
};


declare function obsportal:sync($collection as xs:string) as item()* {
    (: convert obs collection name to oidb one :)
    let $collection := obsportal:get-collection-id($collection)
    (: try to get associated last_mod_date :)
    let $last-mod-date := obsportal:get-last-mod-date($collection)
    let $from-date := if (exists($last-mod-date)) then $last-mod-date else xs:dateTime("2000-01-01T00:00:00")
    return 
        obsportal:sync($collection, $from-date, current-dateTime())
        
    (: TODO if we get new records, perform a global update  ? :)
    (: If required, do remove private collection or select only automatic ones :)
    (: UPDATE oidb as granule SET obs_release_date = obslog.obs_release_date FROM oidb AS obslog WHERE granule.obs_id=SPLIT_PART(obslog.obs_id,'_',1) AND granule.progid = obslog.progid AND granule.calib_level>0 AND obslog.calib_level=0 ;:)
        
        
};

declare %private function obsportal:sync($col-id as xs:string,  $from as xs:dateTime, $to as xs:dateTime) as item()* {
    (: remove old data from db :)
    (: let $delete := obsportal:delete-collection-records($handle, $col-id):)
    if ($from > current-dateTime()) 
    then
        () (: ignore exp in the future for this collection :)
    else if ($from > $to) 
    then
        util:log("error", "obsportal:sync() $from > $to")
    else 
        let $max-to := $from + xs:yearMonthDuration('P1Y')
        return 
            if($to > $max-to )
            then 
                (
                    util:log("info", "timespan too long ("|| $from ||" - " || $to ||"): spliting requests"),
                    obsportal:sync($col-id, $from, $max-to),
                    obsportal:sync($col-id, $max-to, $to)
                )
            else 
                let $new := obsportal:get-observations($from, $to)
                
                return 
                    if(exists($new)) then 
                        let $log := util:log("info", "start sync  from '"|| $from ||"' to '"|| $to ||"' with "|| count($new))
                        let $ids := sql-utils:within-transaction(obsportal:upload(?, $col-id, $new))
                        let $new-last_mod_date := obsportal:get-last-exp_date_updated($new)
                        let $set-last_mod_date :=  obsportal:set-last-mod-date($col-id, $new-last_mod_date)
                        return 
                            (<period>{string-join(($from, $to), "-")}</period>,$ids)
                    else
                        ()
};

