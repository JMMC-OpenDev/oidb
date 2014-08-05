xquery version "3.0";

(:~
 : Perform an upload of observation logs from CHARA data.
 : 
 : The observations previously imported by the same way are deleted.
 : 
 : All database operations in this script are executed within a 
 : transaction: if any failure occurs, the database is left unchanged.
 : 
 : It returns a <response> fragment with the status of the operation.
 : 
 : WARNING: This is a basic importer with a crude parser for the current 
 : format of observation logs: the data is extracted from a CSV file sent in
 : the request and mapped to the columns of the OiDB model. The definition of
 : the input format is a work in progress by Theo ten Brummelaar at CHARA.
 :)

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace util = "http://exist-db.org/xquery/util";

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace upload = "http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";

import module namespace jmmc-simbad="http://exist.jmmc.fr/jmmc-resources/simbad";

(: column indices from source CSV file :)
declare variable $local:UT-DATE  := 1;
declare variable $local:STAR     := 2;
declare variable $local:PI       := 3;
declare variable $local:PROGRAM  := 4;
declare variable $local:COMBINER := 5;
declare variable $local:TYPE     := 6;
declare variable $local:MJD      := 7;
declare variable $local:FILTER   := 8;
declare variable $local:SCOPES   := 9;
declare variable $local:B1       := 10;
declare variable $local:B2       := 11;
declare variable $local:B3       := 12;
declare variable $local:T0_OBS   := 13;
declare variable $local:T0_500nm := 14;

(: the special collection name for CHARA imports :)
declare variable $local:collection := 'CHARA Import';

(: the path to the ASPRO XML configuration in the database :)
declare variable $local:asproconf-uri := '/db/apps/oidb-data/instruments';

(:~
 : Remove all CHARA records from a previous import.
 : 
 : @param $handle a database connection handle
 :)
declare function local:delete-collection($handle as xs:long) {
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
    let $target := jmmc-simbad:resolve-by-name($name)
    return if ($target) then $target[1] else error(xs:QName('error'), 'Unknown target', $name)
};

(:~
 : Match fingerprint from CHARA observation log to full ASPRO description.
 : 
 : @param $insname a combiner name from CHARA obs log
 : @param $modname a filter name from CHARA obs log
 : @return the mode description from ASPRO conf
 : @error unknown mode
 :)
declare function local:resolve-mode($insname as xs:string, $modname as xs:string) {
    let $mode := collection($local:asproconf-uri)//description[name='CHARA']/focalInstrument[name=$insname]/mode[name=$modname]
    return if ($mode) then $mode else error(xs:QName('error'), 'Unknown mode', ( $insname, $modname ))
};

(:~
 : Return the PI name from CHARA observation log data.
 : 
 : @param $pi a PI description from CHARA obs log
 : @return the PI name
 :)
declare function local:resolve-pi($pi as xs:string) as xs:string {
    (: mostly dummy, pick first name as main pi :)
    (: TODO match identifier to real names + full contact info :)
    (: TODO share names with other uploaders (VEGA) :)
    tokenize($pi, '/')[1]
};

(:~
 : Turn a CHARA observation into a metadata fragment for upload.
 : 
 : @param $observation an observation
 : @return a 'metadata' element for the observation
 :)
declare function local:metadata($observation as xs:string*) as node() {
    (: resolve star coordinates from star name :)
    let $star := local:resolve-target($observation[$local:STAR])
    let $target-name := $star/name/text()
    let $ra          := $star/ra
    let $dec         := $star/dec
    let $data-pi     := local:resolve-pi($observation[$local:PI])
    let $date        := $observation[$local:MJD]
    let $ins-name    := $observation[$local:COMBINER]
    let $ins-mode    := $observation[$local:FILTER]
    (: determine wavelength limits from mode and ASPRO config :)
    let $mode := local:resolve-mode($ins-name, $ins-mode)
    let $wl-min      := $mode/waveLengthMin
    let $wl-max      := $mode/waveLengthMax

    return <metadata> {
        (: all entries are L0 :)
        <calib_level>0</calib_level>,
        <target_name>{ $target-name }</target_name>,
        <obs_creator_name>{ $data-pi }</obs_creator_name>,
        <obs_collection>{ $local:collection }</obs_collection>,
        <data_rights>proprietary</data_rights>, (: FIXME secure + obs_release_date? :)
        <access_url> -/- </access_url>, (: FIXME no file :)
        <s_ra>  { $ra } </s_ra>,
        <s_dec> { $dec } </s_dec>,
        <t_min> { $date } </t_min>, (: FIXME :)
        <t_max> { $date } </t_max>, (: FIXME :)
        <t_exptime>0</t_exptime>, (: FIXME :)
        <em_min> { number($wl-min) * 1e-6 } </em_min>,
        <em_max> { number($wl-max) * 1e-6} </em_max>,
        <em_res_power>-1</em_res_power>, (: FIXME :)
        <facility_name>MtW.CHARA</facility_name>,
        <instrument_name>{ $ins-name }</instrument_name>,
        <instrument_mode>{ $ins-mode }</instrument_mode>,
(:        <telescope_configuration>{ $tel-conf }</telescope_configuration>,:)
        (: FIXME :)
        <nb_channels> -1 </nb_channels>,
        <nb_vis> -1 </nb_vis>,
        <nb_vis2> -1 </nb_vis2>,
        <nb_t3> -1 </nb_t3>
    } </metadata>
};

(:~
 : Push observation logs in the database.
 : 
 : @param $handle a database connection handle
 : @param $observations observation logs from CHARA
 : @return a list of the ids of the new granules
 :)
declare function local:upload($handle as xs:long, $observations as xs:string) as item()* {
    (: remove old data from db :)
    let $delete := local:delete-collection($handle)

    (: crude parser for CSV data: one log per line, no quoted fields, assume header and skip it, trim fields... :)
    (: FIXME nasty, write a real parser :)
    let $records := subsequence(tokenize($observations, '\n'), 2)
    for $record at $line in $records
    let $fields := tokenize($record, '\s*,\s*')
    (: ignore empty lines :)
    where exists($fields)
    return try {
        <id>{ upload:upload($handle, local:metadata($fields)/node()) }</id>
    } catch error {
        <warning>{ 'Failed to convert observation log to granule (line ' || $line || '): ' || $err:description || ': ' || $err:value }</warning>
    }
};

(: get the data from the request: data in POST request or from filled-in form :)
let $content-type := request:get-header('Content-Type')
let $data :=
    if (starts-with($content-type, 'multipart/form-data')) then
        util:base64-decode(xs:string(request:get-uploaded-file-data('file')))
    else
        request:get-data()

let $response :=
    <response> {
        try {
            let $ids := upload:within-transaction(local:upload(?, $data))
            return $ids
        } catch * {
            <error> { $err:code, $err:description, $err:value, " module: ", $err:module, "(", $err:line-number, ",", $err:column-number, ")" } </error>
        }
    } </response>

return $response
