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
        $lambda,
        '-',
        $configcam,
        if ($polar='POLAR_OFF') then '' else '-Polar')
};

(:~
 : Return a list of all star names in the VEGA dataset with a particular data status.
 : 
 : @param $dataStatus a sequence of status
 : @return a sequence of names
 :)
declare function vega:get-star-hds($dataStatus as xs:string*) as item()* {
    let $collection := collection($vega:data-root)
    let $status := if (empty($dataStatus)) then 
            distinct-values($collection//td[@colname='DataStatus']/text()) 
        else
            $dataStatus
    return distinct-values($collection//td[@colname='DataStatus' and .=$status]/../td[@colname='StarHD']/text())
};

(:~
 : Return a list of all star names in the VEGA dataset.
 : 
 : @return a sequence of names
 :)
declare function vega:get-all-star-hds() as item()* {
    vega:get-star-hds(())
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
