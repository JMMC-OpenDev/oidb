xquery version "3.0";

(:~
 : This modules interacts with the Obsportal Web service to query and retrieve
 : data from their database.
 :)
module namespace obsportal="http://apps.jmmc.fr/exist/apps/oidb/obsportal";

import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "/db/apps/oidb/modules/collection.xqm";
import module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/granule" at "granule.xqm";


declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.4";

(: Service's base url :)
declare variable $obsportal:OBSPORTAL_URL := "http://obs.jmmc.fr/search.votable";

(: the special collection name for ObsPortal imports : we fake ESO L0 at first but may have to manage multiple ones in the future :)
declare variable $obsportal:collection := 'eso_vlti_import';

(:~
 : Remove all records from previous import.
 : 
 : @param $handle a database connection handle
 :)
declare function obsportal:delete-collection-records($handle as xs:long) {
    collection:delete-granules( $obsportal:collection, $handle )
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
declare function obsportal:get-observations() as node()* {
(:    let $votable := doc($obsportal:OBSPORTAL_URL):)
    let $votable := doc("/obs.xml")
    return 
        subsequence(obsportal:votable-observations($votable),1,1000)
};


(:~
 : Turn an observation into a granule fragment for upload.
 : 
 : @param $observation an observation
 : @return a 'metadata' element for the observation
 :)
declare function obsportal:metadata($observation as node()) as node() {
    
    let $calib_level := "0"
    let $target-name := data($observation/target_name)
    let $obs_id := data($observation/exp_header_id)
    let $obs_creator_name := "jmmc-tech-group - Bourgès"
(:TODO    let $obs_release_date := data($observation/release_date):)
    let $data_rights := "secure"
    let $access_url := "http://archive.eso.org/wdb/wdb/eso/eso_archive_main/query?dp_id="||$observation/exp_header_id
    let $s_ra := data($observation/target_ra)
    let $s_dec := data($observation/target_dec)
    let $t_min := data($observation/exp_mjd_start)
    let $t_max := data($observation/exp_mjd_end)
    let $t_exptime := seconds-from-duration(($t_max - $t_min)*xs:dayTimeDuration('PT24H'))
    let $t_exptime := round-half-to-even($t_exptime,3)
(:TODO    let $em_min := data($observation/em_min):)
(:TODO    let $em_max := data($observation/em_max):)
(:TODO    let $em_res_power := data($observation/em_res_power):)
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

(:TODO cache programId -> datapi :)
    
    return <metadata> {
        (: all entries are L0 :)
        <calib_level>{ $calib_level }</calib_level>,
        <target_name>{ $target-name }</target_name>,
(:NOT TODO here but to cache for later l2 associations  <datapi>{ $data-pi }</datapi>,:)
        <obs_collection>{ $obsportal:collection }</obs_collection>,
        <obs_creator_name>{ $obs_creator_name } </obs_creator_name>,
(:TODO        <obs_release_date>{ $obs_release_date } </obs_release_date>,:)
        <obs_id>{ $obs_id }</obs_id>,
        <data_rights>{ $data_rights }</data_rights>,
        <access_url>{ $access_url }</access_url>,
        <s_ra>  { $s_ra } </s_ra>,
        <s_dec> { $s_dec } </s_dec>,
        <t_min> { $t_min } </t_min>,
        <t_max> { $t_max } </t_max>,
        <t_exptime>{ $t_exptime }</t_exptime>, 
(:TODO        <em_min>{ $em_min }</em_min>,:)
(:TODO        <em_max>{ $em_max }</em_max>,:)
(:TODO        <em_res_power>{ $em_res_power }</em_res_power>,:)
        <facility_name>{ $facility_name }</facility_name>,
        <instrument_name>{ $instrument_name }</instrument_name>,
        <instrument_mode>{ $instrument_mode }</instrument_mode>,
        <progid>{ $progid }</progid>,
        <interferometer_stations>{ $interferometer_stations}</interferometer_stations>,
        <nb_channels>{$nb_channels}</nb_channels>
    } </metadata>
};


(:~
 : Push observation logs in the database.
 : 
 : @param $handle a database connection handle
 : @param $observations observation logs from ObsPortal
 : @return a list of the ids of the new granules
 :)
declare function obsportal:upload($handle as xs:long, $observations as node()*) as item()* {
    (: remove old data from db :)
    let $delete := obsportal:delete-collection-records($handle)
    let $log := util:log("info", "start of obsportal collection upload")
    (: insert new granules in db :)
    
    let $ret := for $o in $observations
    return try {
        <id>{ granule:create(obsportal:metadata($o), $handle) }</id>
    } catch * {
        (
	        <warning>Failed to convert observation log to granule (ObsPortal ID { $o/ID/text() }): { $err:description } { $err:value }</warning>,
            util:log("error", serialize(<warning>Failed to convert observation log to granule (ObsPortal ID { $o/ID/text() }): { $err:description } { $err:value }</warning>))
	    )
    }
    
    let $log := util:log("info", "end of obsportal collection upload")
    return $ret
};