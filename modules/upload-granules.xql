xquery version "3.0";

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
 :)

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace util = "http://exist-db.org/xquery/util";

import module namespace upload = "http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";


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
            let $granules := if ($data instance of document-node()) then $data else util:parse($data)
            (: abort on error and roll back :)
            return upload:within-transaction(
                function($handle as xs:long) as element(id)* {
                    for $granule in $granules//granule
                    return <id>{ upload:upload($handle, $granule/*) }</id>
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
