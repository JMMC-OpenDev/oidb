xquery version "3.0";

(:~
 : Perform an upload of all observations from VegaObs service.
 :
 : The observations previously imported by the same way are deleted.
 : 
 : It returns a <response> fragment with the status of the operation.
 :)

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace upload="http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";
import module namespace vega="http://apps.jmmc.fr/exist/apps/oidb/vega" at "vega.xqm";
import module namespace sql="http://exist-db.org/xquery/sql";
import module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame" at "sesame.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";

(: the special collection name for VegaObs imports :)
declare variable $local:collection := 'VegaObs Import';

(:~
 : Remove all Vega records from a previous import.
 : 
 : @param $handle a database connection handle
 :)
declare function local:delete-collection($handle as xs:long) {
    sql:execute($handle, "DELETE FROM " || $config:sql-table || " WHERE obs_collection='" || $local:collection || "';", false())
};

(:~
 : Turn a Vega observation into a metadata fragment for upload.
 : 
 : @param $observation an observation
 : @return a 'metadata' element for the observation
 :)
declare function local:metadata($observation as node()) as node() {
    (: determine wavelength limits from mode and ASPRO config :)
(:    let $mode        := vega:instrument-mode-2($observation/Grating, $observation/Lambda):)
(:    let $minmax-wl   := map(function ($x) { $x div 1e6 }, vega:wavelength-minmax($mode)):)
    let $lambda      := number($observation/Lambda)
    let $data-pi     := vega:get-user-name($observation/DataPI)
    (: resolve star coordinates from star name with Sesame :)
    let $target-name := $observation/StarHD
    let $ra-dec      := data(sesame:resolve($target-name)/target/(@s_ra,@s_dec))
    let $date        := jmmc-dateutil:ISO8601toMJD( 
        (: change the time delimiter in Date for ISO8601 :)
        xs:dateTime(translate($observation/Date, ' ', 'T')))
(:    let $ins-mode    := vega:instrument-mode($observation):)
(:    let $tel-conf    := vega:telescopes-configuration($observation):)
    
    return <metadata> {
        (: all entries are L0, even dataStatus=Published :)
        <calib_level>0</calib_level>,
        <target_name>{ $target-name }</target_name>,
        <obs_creator_name>{ $data-pi }</obs_creator_name>,
        <obs_collection>{ $local:collection }</obs_collection>,
        <data_rights>proprietary</data_rights>, (: FIXME secure + obs_release_date? :)
        <access_url> -/- </access_url>, (: FIXME no file :)
        <s_ra>  { $ra-dec[1] } </s_ra>,
        <s_dec> { $ra-dec[2] } </s_dec>,
        <t_min> { $date } </t_min>, (: FIXME :)
        <t_max> { $date } </t_max>, (: FIXME :)
        <t_exptime>0</t_exptime>, (: FIXME :)
(:        <em_min> { $minmax-wl[1] } </em_min>,:)
        <em_min>{ $lambda * 1e-9 }</em_min>,
(:        <em_max> { $minmax-wl[2] } </em_max>,:)
        <em_max>{ $lambda * 1e-9 }</em_max>,
        <em_res_power>-1</em_res_power>, (: FIXME :)
        <facility_name>MtW.CHARA</facility_name>,
        <instrument_name>VEGA</instrument_name>,
(:        <instrument_mode>{ $ins-mode }</instrument_mode>,:)
(:        <telescope_configuration>{ $tel-conf }</telescope_configuration>,:)
        (: FIXME :)
        <nb_channels> -1 </nb_channels>,
        <nb_vis> -1 </nb_vis>,
        <nb_vis2> -1 </nb_vis2>,
        <nb_t3> -1 </nb_t3>
    } </metadata>
};

let $response :=
    <response> {
        try {
            <success> {
                let $handle := config:get-db-connection()
                let $new := vega:get-observations()
                (: remove old data from db :)
                let $remove := local:delete-collection($handle)
                (: push new data in database :)
                for $x in $new
                return upload:upload($handle, local:metadata($x)/node())
            } </success>
        } catch * {
            <error> { $err:code, $err:description } </error>
        }
    } </response>

return (log:submit($response), $response)
