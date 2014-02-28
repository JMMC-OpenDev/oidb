xquery version "3.0";

(:~
 : This modules interacts with the VegaObs Web service to query and retrieve
 : data from their database.
 : 
 : It locally saves the observation data returned (see vega:pull()) and
 : provides helpers for manipulating the data.
 :)
module namespace vega="http://apps.jmmc.fr/exist/apps/oidb/vega";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace util="http://exist-db.org/xquery/util";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";

import module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame" at "sesame.xqm";
import module namespace upload="http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";
declare namespace xsd="http://org.apache.axis2/xsd";

(: Base url for the VegaWS service - HTTP port :)
declare variable $vega:VEGAWS_URL := "http://vegaobs-ws.oca.eu/axis2/services/VegaWs.VegaWsHttpport/VegaWs/";

(: Base URI for the storage of VEGA data :)
declare variable $vega:data-root := $config:data-root || '/vega';

(:~
 : Make use of the VegaObs web service to retrieve the list of user.
 : (getUserList method)
 : 
 : @return a sequence of <user> elements with id and name
 :)
declare %private function vega:get-users() as node()* {
    let $uri  := concat($vega:VEGAWS_URL, 'getUserList')
    let $data := httpclient:get($uri, false(), <headers/>)//httpclient:body
    
    for $return in $data//xsd:return
        let $tokens := tokenize($return, '\t')
        return element { "user" } {
            attribute { "id" }   { $tokens[1] },
            attribute { "name" } { concat($tokens[3], " ", $tokens[2]) }
        }
};

(: the list of all VegaObs user :)
declare variable $vega:users := vega:get-users();

(:~
 : Returns the name of the user with the specified ID.
 : 
 : @param $id the user id as a string
 : @return the name as a string
 :)
declare function vega:get-user-name($id as xs:string*) as xs:string {
    string($vega:users[./@id=$id]/@name)
};

(:~
 : Make use of the VegaObs web service to retrieve the observation with a
 : specified data status.
 : (getObservationVOTableByDataStatus method)
 : 
 : @param $dataStatus 'WaitProcessing', 'WaitOtherData', 'WaitPublication', 'Published' or 'Trash'
 : @return a <VOTABLE> of observations.
 :)
declare %private function vega:get-observations-by-data-status($dataStatus as xs:string) as node()* {
    let $uri  := concat($vega:VEGAWS_URL, 'getObservationsVOTableByDataStatus', '?dataStatus=', $dataStatus)
    let $data := httpclient:get($uri, false(), <headers/>)//httpclient:body

    return try {
        util:parse(
            (: remove leading 'null' :)
            substring($data//xsd:return/text(), 5))
    } catch * {
        <error/>
    }
};

(:~
 :)
declare %private function vega:nodes-from-field-name($votable as node()?) as node() {
    let $headers := $votable//votable:FIELD
    let $header_names := for $header in $headers return data($header/@name)

    return <votable> {
        for $row in  $votable//votable:TABLEDATA/votable:TR
        return <tr> {
            for $node at $i in $row/votable:TD
            return <td>
                { $node/@*,
                  attribute { "colname" } { $header_names[$i] },
                  $node/node() }
            </td>
        } </tr>
    } </votable>
};

(:~
 : Return the number of telescope used during an observation.
 : 
 : @param $row the description of the observation
 : @return the number of telescopes used
 :)
declare function vega:number-of-telescopes($row as node()) as xs:integer {
    count($row/td[matches(./@colname, '^T.$') and ./text()!='OFF'])
};

(:~
 : Return the telescope configuration for an observation.
 : 
 : @param $row the description of the observation
 : @return a string of telescope modes concatenated
 :)
declare function vega:telescopes-configuration($row as node()) as xs:string {
    string-join($row/td[matches(./@colname, '^T.$') and ./text()!='OFF']/text(), '-')
};

(:~
 : Return a string with instrument node for the given row.
 : 
 : Based on description by Denis Mourard in message on the jmmc-tech-group ML.
 : 
 : @param $row the description of the observation
 : @return a string with instrument mode
 :)
declare function vega:instrument-mode($row as node()) as xs:string {
    let $grating   := number($row/td[@colname='Grating']/text())
    let $lambda    := number($row/td[@colname='Lambda']/text())
    let $configcam := $row/td[@colname='ConfigCam']/text()
    let $polar     := $row/td[@colname='Polar']/text()
    return concat(
        if ($grating=100) then 'LR'
        else if ($grating=300) then 'MR'
        else if ($grating=1800) then 'HR' else '??',
        floor($lambda),
        '-',
        $configcam,
        if ($polar='POL_OFF') then '' else '-Polar')
};

(:~
 : Return a list of all star names in the VEGA dataset.
 : 
 : @return a sequence of names
 :)
declare function vega:get-star-hds() as item()* {
    let $collection := collection($vega:data-root)
    return distinct-values($collection//td[@colname='StarHD']/text())
};

(:~ Vega modes from ASPRO2 configuration :)
declare variable $vega:aspro-modes :=
    doc('http://apps.jmmc.fr/~swmgr/AsproOIConfigurations/ASPRO2-CONF_2013_1015/model/CHARA.xml')//focalInstrument[./name='VEGA_4T']/mode;
(:declare variable $vega:aspro-modes := doc('/db/apps/oidb-data/vega/ASPRO2-CONF_2013_1015_CHARA.xml')//focalInstrument[./name='VEGA_4T']/mode;:)

(:~
 : Find the instrument mode corresponding to the given configuration.
 : 
 : It makes use of ASPRO configuration file and it is matching
 : grating and lambda values to the mode description.
 : 
 : @param $grating grating used for the observation
 : @param $lambda wavelength planified for the observation
 : @return a node from ASPRO configuration with mode description
 : @error instrument mode not found
 :)
declare %private function vega:instrument-mode-2($grating as xs:string, $lambda as xs:string) as node() {
    (: select mode based on gratign and lambda :)
    let $mode := $vega:aspro-modes[./parameter[./name='GRATING' and ./value=$grating] and ./parameter[./name='LAMBDA' and ./value=$lambda]]
    return if (exists($mode)) then
        $mode
    else
        error(xs:QName('vega:error'), 'Instrument mode not found (grating=' || $grating || ',lambda=' || $lambda || ')')
};

(:~
 : Return wavelength limits for given mode.
 : 
 : @param $mode ASPRO mode
 : @return a sequence of min and max wavelength in µm
 :)
declare %private function vega:wavelength-minmax($mode as node()) as item()* {
    ( $mode/waveLengthMin/text(), $mode/waveLengthMax/text() )
};

(:~
 : Turn a data row from VegaObs into an item in the database.
 : 
 : It parses and extracts data from the data row and transform
 : it before uploading to the database.
 : 
 : @param $data a VegaObs data row
 : @return ignore
 : @error unknown instrument mode
 : @error unable to resolve star name
 : @error failed to upload data
 :)
declare %private function vega:upload($handle as xs:long, $data as node()*) {
    (: determine wavelength limits from mode and ASPRO config :)
(:    let $mode        := vega:instrument-mode-2($data/td[@colname='Grating'], $data/td[@colname='Lambda']):)
(:    let $minmax-wl   := map(function ($x) { $x div 1e6 }, vega:wavelength-minmax($mode)):)
    let $lambda      := number($data/td[@colname='Lambda'])
    let $data-pi     := vega:get-user-name($data/td[@colname='DataPI'])
    (: resolve star coordinates from star name with Sesame :)
    let $target-name := $data/td[@colname='StarHD']/text()
    let $ra-dec      := data(sesame:resolve($target-name)/target/(@s_ra,@s_dec))
    let $date        := jmmc-dateutil:ISO8601toMJD( 
        (: change the time delimiter in Date for ISO8601 :)
        xs:dateTime(translate($data/td[@colname='Date'], ' ', 'T')))
    
    (: build a metadata fragment from row data and upload it :)
    return upload:upload($handle, ( 
        (: all entries are L0, even dataStatus=Published :)
        <calib_level>0</calib_level>,
        <target_name>{ $target-name }</target_name>,
        <obs_collection>VegaObs Import</obs_collection>,
        <obs_creator_name>{ $data-pi }</obs_creator_name>,
        <data_rights>proprietary</data_rights>, (: FIXME secure + obs_release_date? :)
        <access_url> -/- </access_url>, (: FIXME no file :)
        <s_ra>  { $ra-dec[1] } </s_ra>,
        <s_dec> { $ra-dec[2] } </s_dec>,
        <t_min> { $date } </t_min>, (: FIXME :)
        <t_max> { $date } </t_max>, (: FIXME :)
        <t_exptime>0</t_exptime>, (: FIXME :)
(:        <em_min> { $minmax-wl[1] } </em_min>,:)
        <em_min>{ $lambda }</em_min>,
(:        <em_max> { $minmax-wl[2] } </em_max>,:)
        <em_max>{ $lambda }</em_max>,
        <em_res_power> -1 </em_res_power>, (: FIXME :)
        <facility_name>MtW.CHARA</facility_name>,
        <instrument_name>VEGA</instrument_name>,
        (: FIXME :)
        <nb_channels> -1 </nb_channels>,
        <nb_vis> -1 </nb_vis>,
        <nb_vis2> -1 </nb_vis2>,
        <nb_t3> -1 </nb_t3>
    ))
};

(:~
 : Import observations from the VegaObs database of the given data status.
 : 
 : @param $dataStatus 'WaitProcessing', 'WaitOtherData', 'WaitPublication', 'Published'
 : @return a <response> element 
 :)
declare function vega:pull-by-status($status as xs:string) {
    <response data-status="{ $status }"> {
        try {
            let $data := vega:nodes-from-field-name(vega:get-observations-by-data-status($status))
            let $handle := upload:getDbHandle()
            for $row in $data//tr
            let $obsid := $row/td[@colname='ID']
            return try {
                ( vega:upload($handle, $row), <success obsid="{ $obsid }"/> )
            } catch * {
                <error obsid="{ $obsid }"> { $err:description } </error>
            }
        } catch exerr:EXXQDY0002 {
            (: XML VOTable parse error :)
            let $message := $err:value//message
            return <error> 
                { $err:description } <br/> { 'Line ' || $message/@line || ", column" || $message/@column || ':' || $err:value//message }
            </error>
        } catch * {
            (: unknown parse error :)
            <error>{ $err:description }</error>
        }
    } </response>
};

(:~
 : Retrieve data from the VegaObs database and store locally.
 : It currently requests all data with status and status different from 'Trash'.
 : 
 : @param $collection destination collection where to put data
 : @return a sequence of path to new resources.
 :)
 declare function vega:pull($collection as xs:string) as item()* {
    let $published        := vega:nodes-from-field-name(vega:get-observations-by-data-status('Published'))
    let $wait-publication := vega:nodes-from-field-name(vega:get-observations-by-data-status('WaitPublication'))
    let $wait-other-data  := vega:nodes-from-field-name(vega:get-observations-by-data-status('WaitOtherData'))
    let $wait-processing  := vega:nodes-from-field-name(vega:get-observations-by-data-status('WaitProcessing'))
    return (
        xmldb:store($collection, "published"        || ".xml", $published),
        xmldb:store($collection, "wait-publication" || ".xml", $wait-publication),
        xmldb:store($collection, "wait-other-data"  || ".xml", $wait-other-data),
        xmldb:store($collection, "wait-processing"  || ".xml", $wait-processing))
};
