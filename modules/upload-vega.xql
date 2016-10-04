xquery version "3.0";

(:~
 : Perform an upload of all observations from VegaObs service.
 :
 : The observations previously imported by the same way are deleted.
 : 
 : All database operations in this script are executed within a 
 : transaction: if any failure occurs, the database is left unchanged.
 : 
 : It returns a <response> fragment with the status of the operation.
 :)

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";
import module namespace vega="http://apps.jmmc.fr/exist/apps/oidb/vega" at "vega.xqm";
import module namespace sql="http://exist-db.org/xquery/sql";
import module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame" at "sesame.xqm";
import module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/granule" at "granule.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";


import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-cache="http://exist.jmmc.fr/jmmc-resources/cache";

(: the special collection name for VegaObs imports :)
declare variable $local:collection := 'vegaobs_import';

(:  prepare a cache for target resolutions :)
declare variable $local:cache :=
    try {
        doc(xmldb:store($config:data-root || '/tmp', 'upload-vega.xml', <cache/>))/cache
    } catch * {
        error(xs:QName('error'), 'Failed to create cache for upload-vega.xql: ' || $err:description, $err:value)
    };
declare variable $local:cache-insert   := jmmc-cache:insert($local:cache, ?, ?);
declare variable $local:cache-get      := jmmc-cache:get($local:cache, ?);
declare variable $local:cache-contains := jmmc-cache:contains($local:cache, ?);
declare variable $local:cache-destroy  := function() { xmldb:remove($config:data-root || '/tmp', 'upload-vega.xml') };

(:~
 : Remove all Vega records from a previous import.
 : 
 : @param $handle a database connection handle
 :)
declare function local:delete-collection($handle as xs:long) {
    app:clear-cache(),
    sql:execute($handle, "DELETE FROM " || $config:sql-table || " WHERE obs_collection='" || $local:collection || "';", false())
};

(:~
 : Search for a target by name.
 : 
 : @param $name a target name
 : @return a target description
 : @error unknown target
 :)
declare function local:resolve-target($name as xs:string) {
    (: search in cache first :)
    if ($local:cache-contains($name)) then
        (: hit :)
        $local:cache-get($name)
    else
        (: miss, resolve by name and cache the results for next time :)
        let $target :=
            try {
                sesame:resolve($name)
            } catch * {
                error(xs:QName('error'), 'Unable to resolve target: ' || $err:description, $err:value)
            }
        return ( $local:cache-insert($name, $target), $target )
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
    let $target      := local:resolve-target($target-name)
    let $ra          := data($target/target/@s_ra)
    let $dec         := data($target/target/@s_dec)
    let $date        := jmmc-dateutil:ISO8601toMJD( 
        (: change the time delimiter in Date for ISO8601 :)
        xs:dateTime(translate($observation/Date, ' ', 'T')))
    let $ins-mode    := vega:instrument-mode($observation)
(:    let $tel-conf    := vega:telescopes-configuration($observation):)
    let $program     := $observation/ProgNumber
    
    return <metadata> {
        (: all entries are L0, even dataStatus=Published :)
        <calib_level>0</calib_level>,
        <target_name>{ $target-name }</target_name>,
        <datapi>{ $data-pi }</datapi>,
        <obs_collection>{ $local:collection }</obs_collection>,
        <obs_creator_name>Denis Mourard</obs_creator_name>,
        <obs_id>{ $program }</obs_id>,
        <data_rights>proprietary</data_rights>, (: FIXME secure + obs_release_date? :)
        <access_url> -/- </access_url>, (: FIXME no file :)
        <s_ra>  { $ra } </s_ra>,
        <s_dec> { $dec } </s_dec>,
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
        <instrument_mode>{ $ins-mode }</instrument_mode>,
(:        <telescope_configuration>{ $tel-conf }</telescope_configuration>,:)
        (: FIXME :)
        <nb_channels> -1 </nb_channels>
        (: leave nb_vis, nb_vis2 and nb_t3 empty :)
    } </metadata>
};

(:~
 : Push observation logs in the database.
 : 
 : @param $handle a database connection handle
 : @param $observations observation logs from VegaObs
 : @return a list of the ids of the new granules
 :)
declare function local:upload($handle as xs:long, $observations as node()*) as item()* {
    (: remove old data from db :)
    let $delete := local:delete-collection($handle)
    (: insert new granules in db :)
    for $o in $observations
    return try {
        <id>{ granule:create(local:metadata($o), $handle) }</id>
    } catch * {
        <warning>Failed to convert observation log to granule (VegaObs ID { $o/ID/text() }): { $err:description } { $err:value }</warning>
    }
};

let $response :=
    <response> {
        try {
            <success> {
                let $new := vega:get-observations()
                let $ids := utils:within-transaction(local:upload(?, $new))
                return $ids
            } </success>
        } catch * {
            <error> { $err:code, $err:description } </error>
        }
    } </response>

return ( $local:cache-destroy(), log:submit($response), $response )
