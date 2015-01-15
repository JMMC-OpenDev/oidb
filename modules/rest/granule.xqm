xquery version "3.0";

(:~
 : This module provides a REST API to submit granules.
 :)
module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/restxq/granule";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";
import module namespace upload = "http://apps.jmmc.fr/exist/apps/oidb/upload" at "../upload.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "../log.xqm";

import module namespace jmmc-eso = "http://exist.jmmc.fr/jmmc-resources/eso";

declare namespace rest="http://exquery.org/ns/restxq";


(:~
 : Push a granule in the database.
 : 
 : @param $handle  a database connection handle
 : @param $granule a XML granule description
 : @return the id of the new granule or error
 : @error unknown collection, failed to upload granule
 :)
declare %private function granule:upload($handle as xs:long, $granule as node()) as xs:integer {
    let $collection := $granule/obs_collection/text()
    return
        (: check that parent collection of granule exists :)
        if (exists($collection) and empty(collection("/db/apps/oidb-data/collections")/collection[@id=$collection])) then
            error(xs:QName('error'), 'Unknown collection id: ' || $collection)
        else
            let $updated-granule := granule:sanitize($granule)
            return upload:upload($handle, $updated-granule/*)
};

(:~
 : Sanitise the given granule.
 : <ul>
 :    <li>ESO case : if datapi is not present and obs_id is provided, retrieve PI from ESO archive and add new datapi element</li>    
 :    <li>TODO handle other rules if any</li>
 : </ul>
 :
 : @param $granule a XML granule description
 : @return the sanitysed granule copy of the given one
 :)
declare %private function granule:sanitize($granule as node()) as node() {
    let $datapi := $granule/datapi/text()
    let $progid := $granule/obs_id/text()
    (: assume that we are on a eso case with a given progid :)
    let $pi := if(empty($datapi) and $progid) then jmmc-eso:get-pi-from-progid($progid) else ()
    
    return element {name($granule)} {
        for $e in $granule/* return $e,
        if($pi) then element {"datapi"} {$pi} else ()
    }
};

(:~
 : Push one or more XML granules into the database.
 : 
 : The set of granules is passed as an XML document either as data in the
 : POST request or as a multipart/form-data content from a HTML form where
 : each granule is serialized as a 'granule' element with children elements
 : whose names are table columns and texts their respective values.
 : 
 : It returns a <response> element containing either a <success> or <error>
 : element. In the first case, the message also contains the ids of the
 : saved granules as <id> elements.
 : 
 : @param $data the XML granules
 : @return a <response/> document with status for uploaded granules.
 : @error see HTTP status code
 :)
declare
    %rest:POST("{$granules}")
    %rest:path("/oidb/granule")
function granule:save-granules($granules as document-node()) {
    let $response :=
        <response> {
            try {
                (: abort on error and roll back :)
                upload:within-transaction(
                    function($handle as xs:long) as element(id)* {
                        for $granule in $granules//granule
                        let $id := granule:upload($handle, $granule)
                        return <id>{ $id }</id>
                    }),
                    <success>Successfully uploaded granule(s)</success>
            } catch * {
                response:set-status-code(400), (: Bad Request :)
                <error> {
                    if ($err:code = 'exerr:EXXQDY0002') then
                        (: data is not a valid XML document :)
                        "Failed to parse granule file: " || $err:description || " " || $err:value
                    else
                        "Failed to upload one granule: " || $err:description || " " || $err:value
                } </error>
            }
        } </response>
    return ( log:submit($response), $response )
};
