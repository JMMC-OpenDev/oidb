xquery version "3.0";

(:~
 : This modules interacts with the VegaObs Web service to query and retrieve
 : data from their database.
 :)
module namespace vega="http://apps.jmmc.fr/exist/apps/oidb/vega";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";
declare namespace xsd="http://org.apache.axis2/xsd";

(: Base url for the VegaWS service - HTTP port :)
declare variable $vega:VEGAWS_URL := "http://vegaobs-ws.oca.eu/axis2/services/VegaWs.VegaWsHttpport/VegaWs/";

(:~
 : Make use of the VegaObs web service to retrieve the list of user.
 : (getUserList method)
 : 
 : @return a sequence of <user> elements with id and name
 :)
declare %private function vega:get-users() as node()* {
    let $log := util:log("info", "vega:get-users()")
    let $uri  := concat($vega:VEGAWS_URL, 'getUserList')
    let $data := hc:send-request(<hc:request method="get" href="{$uri}"/>)[2]
    
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
 : Transform the rows of a VOTable into observations.
 : 
 : @param $votable a XML VOTable from VegaObs
 : @return a sequence of 'observation' elements
 :)
declare %private function vega:votable-observations($votable as node()) as node()* {
    let $header_names := $votable//votable:FIELD/@name
    let $rows := $votable//votable:TABLEDATA/votable:TR
    for $row in $rows
    return <observation> {
        for $cell at $i in $row/votable:TD
        return element { $header_names[$i] } { $cell/node() }
    } </observation>
};

(:~
 : Make use of the VegaObs web service to retrieve the observations with a
 : specified data status (getObservationVOTableByDataStatus method).
 : 
 : @param $dataStatus 'WaitProcessing', 'WaitOtherData', 'WaitPublication', 'Published' or 'Trash'
 : @return observations with the specified data status
 :)
declare %private function vega:get-observations-by-data-status($dataStatus as xs:string) as node()* {
    let $uri  := concat($vega:VEGAWS_URL, 'getObservationsVOTableByDataStatus', '?dataStatus=', $dataStatus)
    let $log := util:log("info", "vega:get-observations-by-data-status("||$dataStatus||") at "||$uri)
    let $data := hc:send-request(<hc:request method="get" href="{$uri}"/>)[2]
    let $votable := fn:parse-xml(
        (: remove leading 'null', proper entity escape :)
        replace(substring($data//xsd:return, 5), '&amp;', '&amp;amp;'))

    return vega:votable-observations($votable)
};

(:~
 : Return the number of telescopes used during an observation.
 : 
 : @param $row the description of the observation
 : @return the number of telescopes used
 :)
declare function vega:number-of-telescopes($row as node()) as xs:integer {
    count($row/node()[matches(name(), '^T.$') and .!='OFF'])
};

(:~
 : Return the telescope configuration for an observation.
 : 
 : @param $row the description of the observation
 : @return a string of telescope modes concatenated
 :)
declare function vega:telescopes-configuration($row as node()) as xs:string {
    string-join($row/node()[matches(name(), '^T.$') and .='OFF'], '-')
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
    let $grating   := number($row/Grating)
    let $lambda    := number($row/Lambda)
    let $configcam := $row/ConfigCam/text()
    let $polar     := $row/Polar
    return concat(
        if ($grating=100) then 'LR'
        else if ($grating=300) then 'MR'
        else if ($grating=1800) then 'HR' else '??',
        floor($lambda),
        '-',
        $configcam,
        if ($polar='POL_OFF') then '' else '-Polar')
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
 : Query the VegaObs service and returns all the recorded observations.
 : 
 : @return a sequence of observations
 :)
declare function vega:get-observations() as node()* {
    for $s in ( 'Published', 'WaitPublication', 'WaitOtherData', 'WaitProcessing' )
    return vega:get-observations-by-data-status($s)
};
