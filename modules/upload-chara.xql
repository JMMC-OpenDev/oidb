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
import module namespace utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";
import module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame" at "sesame.xqm";
import module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/granule" at "granule.xqm";

import module namespace jmmc-cache="http://exist.jmmc.fr/jmmc-resources/cache";

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

(: path to the CSV file in database when running from scheduler (job parameter) :)
declare variable $local:resource external;

(: the special collection name for CHARA imports :)
declare variable $local:collection := 'chara_import';

(: the path to the ASPRO XML configuration in the database :)
declare variable $local:asproconf-uri := '/db/apps/oidb-data/instruments';

(:  prepare a cache for target resolutions :)
declare variable $local:cache :=
    try {
        let $doc := doc($config:data-root || '/tmp/upload-chara.xml')
        let $doc := if($doc) then $doc else doc(xmldb:store($config:data-root || '/tmp', 'upload-chara.xml', <cache/>))
        return $doc/cache
    } catch * {
        error(xs:QName('error'), 'Failed to create cache for upload-chara.xql: ' || $err:description, $err:value)
    };
declare variable $local:cache-insert   := jmmc-cache:insert($local:cache, ?, ?);
declare variable $local:cache-get      := jmmc-cache:get($local:cache, ?);
declare variable $local:cache-contains := jmmc-cache:contains($local:cache, ?);
declare variable $local:cache-destroy  := function() { true() (: xmldb:remove($config:data-root || '/tmp', 'upload-chara.xml') :) };

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
 : It makes use of a temporary cache of previous name resolutions to avoid
 : excessive requests to Sesame.
 : 
 : @param $name a target name
 : @return a target description
 : @error unknown target
 :)
declare function local:resolve-target($name as xs:string) {
    let $target :=
        (: search in cache first :)
        if ($local:cache-contains($name)) then
            (: hit :)
            $local:cache-get($name)
        else
            (: miss, resolve by name and cache the results for next time :)
            let $target := try { sesame:resolve($name)/target } catch sesame:resolve { () }
            let $target :=  if( $target ) then 
                                $target 
                            else if(ends-with($name, "_A")) then 
                                try { sesame:resolve(substring-before($name,"_A"))/target } catch sesame:resolve { () } 
                            else if(ends-with($name, "Ab")) then 
                                try { sesame:resolve(substring-before($name,"Ab"))/target } catch sesame:resolve { () } 
                            else ()
            return ( $local:cache-insert($name, $target), $target )
    return if($target) then $target else error(xs:QName('error'), 'Unknown target - '|| $name, $name)
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
    tokenize($pi, '[^\c\s&#x27;]')[1]
};

(:~
 : Check main validity point of CHARA observation log.
 : 
 : @param $type object type
 : @param $b1 baseline length
 : @param $b2 baseline length 
 : @param $b3 baseline length 
 : @return true() if all test passes else throw an error
 : @error unsupported object type, missing baseline, non numeric baseline value, negative baseline value
 :)
declare function local:check-validity($type as xs:string, $b1 as xs:double, $b2 as xs:double, $b3 as xs:double) {
    let $check-mode := if( $type = ('OBJ', 'CAL1', 'CAL2', 'CHK', 'UNKNO')) then () else error(xs:QName('error'), 'Unsupported object type', ( $type ))
    let $baseline-lengths := ($b1, $b2, $b3)
    let $baseline-sum := sum($baseline-lengths)
    let $check-baselines := if( $baseline-sum = 0 ) then error(xs:QName('error'), 'missing baseline', $baseline-lengths) else ()
    let $check-baselines := if( string(sum($baseline-sum))='NaN' ) then error(xs:QName('error'), 'non numeric baseline value', $baseline-lengths) else ()
    let $check-baselines := for $b in $baseline-lengths return if( $b < 0 ) then error(xs:QName('error'), 'negative baseline value', $baseline-lengths) else ()
    return true()
};

(:~
 : Turn a CHARA observation into a metadata fragment for upload.
 : 
 : @param $observation an observation
 : @return a 'metadata' element for the observation
 :)
declare function local:metadata($observation as xs:string*) as node() {
    (: leading and trailing whitespaces significant in CSV (RFC4180) but annoying here :)
    let $observation := for $e in $observation return normalize-space($e)
    
    let $type        := $observation[$local:TYPE]
    let $b1          := $observation[$local:B1]
    let $b2          := $observation[$local:B2]
    let $b3          := $observation[$local:B3]
    let $main-test   := local:check-validity($type, $b1, $b2, $b3)
    (: resolve star coordinates from star name :)
    let $target-name := $observation[$local:STAR]
    let $star        := local:resolve-target($target-name)
    let $ra          := number($star/@s_ra)
    let $dec         := number($star/@s_dec)
    let $data-pi     := local:resolve-pi($observation[$local:PI])
    let $program     := $observation[$local:PROGRAM]
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
        <datapi>{ $data-pi }</datapi>,
        <obs_collection>{ $local:collection }</obs_collection>,
        <obs_creator_name>Theo ten Brummelaar</obs_creator_name>,
        <obs_id>{ $program }</obs_id>,
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
        <nb_channels> -1 </nb_channels>
        (: leave nb_vis, nb_vis2 and nb_t3 empty :)
    } </metadata>
};

(:~
 : Return records from CSV data.
 : 
 : @note It does not support multi line records.
 : 
 : @param $data the CSV content
 : @return a sequence of CSV records
 :)
declare function local:csv-records($data as xs:string) as xs:string* {
    tokenize($data, '\n')
};

(:~
 : Return items of the first escaped field from a tokenized CSV record.
 : 
 : @param $tokens remaining items from a tokenized record
 : @return the items of a CSV escaped field
 :)
declare function local:csv-escaped-field($tokens as xs:string*) as xs:string* {
    let $head := head($tokens)
    return (
        $head,
        if(empty($head) or matches($head, '[^"]"\s*$')) then () else local:csv-escaped-field(tail($tokens))
    )
};

(:~
 : Parse a tokenized CSV record.
 : 
 : @params $tokens a tokenized CSV record
 : @return a sequence of CSV fields
 :)
declare function local:csv-fields($tokens as xs:string*) as xs:string* {
    (: check for escaped field :)
    let $escaped := matches($tokens[1], '^\s*"')
    let $field := if ($escaped) then local:csv-escaped-field($tokens) else head($tokens)
    let $rest  := subsequence($tokens, count($field) + 1)
    (: reassemble and unescape field if necessary :)
    let $field := if ($escaped) then replace(replace(string-join($field, ','), '^\s*"|"\s*$', ''), '""', '"') else $field

    return ( $field, if (empty($rest)) then () else local:csv-fields($rest) )
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

    (: crude parser for CSV data: one log per line, assume header and skip it... :)
    (: FIXME nasty, write a real parser :)
    let $records := tail(local:csv-records($observations))
    for $record at $line in $records
    let $fields := local:csv-fields(tokenize($record, ','))
    (: ignore empty lines :)
    where exists($fields)
    return try {
        <id>{ granule:create(local:metadata($fields), $handle) }</id>
    } catch error {
        <warning>{ 'Failed to convert observation log to granule (line ' || $line || '): ' || $err:description || ': ' || string-join($err:value, ', ') }</warning>
    }
};


(: get the data from a resource in the database, the data in POST request or from filled-in form :)
let $data :=
    (: check $local:resource is defined :)
    if (try { $local:resource } catch err:XPDY0002 { false() }) then
        (: called from scheduler, use resource :)
        util:base64-decode(xs:string(util:binary-doc($local:resource)))
        (: discard document? :)
    else if (request:is-multipart-content()) then
        util:base64-decode(xs:string(request:get-uploaded-file-data('file')))
    else
        request:get-data()

let $response :=
    <response> {
        try {
            let $ids := utils:within-transaction(local:upload(?, $data))
            return $ids
        } catch * {
            <error> { $err:code, $err:description, $err:value, " module: ", $err:module, "(", $err:line-number, ",", $err:column-number, ")" } </error>
        }
    } </response>

return ( $local:cache-destroy(), log:submit($response), $response )
