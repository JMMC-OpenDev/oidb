xquery version "3.0";

(:~
 : This module provides a REST API to submit granules.
 :)
module namespace granule="http://apps.jmmc.fr/exist/apps/oidb/restxq/granule";

import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "../sql-utils.xql";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "../log.xqm";
import module namespace gran="http://apps.jmmc.fr/exist/apps/oidb/granule" at "../granule.xqm";

import module namespace jmmc-eso = "http://exist.jmmc.fr/jmmc-resources/eso";
import module namespace http = "http://expath.org/ns/http-client";

declare namespace rest="http://exquery.org/ns/restxq";


(:~
 : Return a granule given its granule ID.
 :
 : @param $id the id of the granule to find
 : @return a <granule> element or a 404 status if not found
 :)
declare
    %rest:GET
    %rest:path("/oidb/granule/{$id}")
function granule:get-granule($id as xs:integer) {
    try {
        gran:retrieve($id)
    } catch * {
        <rest:response><http:response status="404"/></rest:response>
    }
};

(:~
 : Update the granule with the given id.
 :
 : @param $id the id of the granule to update
 : @param $granule-doc the new data for the granule
 : @return ignore, see HTTP status code
 :)
declare
    %rest:PUT("{$granule-doc}")
    %rest:path("/oidb/granule/{$id}")
function granule:put-granule($id as xs:integer, $granule-doc as document-node()) {
    let $status := try {
            gran:update($id, $granule-doc/granule), 204 (: No Content :)
        } catch gran:unknown {
            404 (: Not Found :)
        } catch gran:error {
            400 (: Bad Request :)
        } catch gran:unauthorized {
            401 (: Unauthorized :)
        } catch * {
            let $msg := "can't update "||$id||" : "|| string-join( ($err:code, $err:description, $err:value, " module: ", $err:module, "(", $err:line-number, ",", $err:column-number, ")" ), ", ")
            return
             ( 500 (: Internal Server Error :) , util:log("error", $msg) )
        }

    return <rest:response><http:response status="{ $status }"/></rest:response>
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
 : @param $granules the XML granules (may be empty for catalogues without oifits)
 : @return a <response/> document with status for uploaded granules.
 : @error see HTTP status code
 :)
declare
    %rest:POST("{$granules}")
    %rest:path("/oidb/granule")
function granule:save-granules($granules as document-node()?) {
    let $response :=
        <response> {
            try {
                (: abort on error and roll back :)
                sql-utils:within-transaction(
                    function($handle as xs:long) as element(id)* {
                        for $granule in $granules//granule
                        let $id := gran:create($granule, $handle)
                        let $g := gran:retrieve($id, $handle)
                        return (<id>{ $id }</id>, $g)
                    }),
                    <success>Successfully uploaded {count($granules//granule)} granule(s)</success>
            } catch gran:error {
                response:set-status-code(400), (: Bad Request :)
                <error>{ $err:description } { $err:value }</error>
            } catch gran:unauthorized {
                response:set-status-code(401), (: Unauthorized :)
                <error>{ $err:description } { $err:value }</error>
            } catch exerr:EXXQDY0002 {
                (: data is not a valid XML document :)
                response:set-status-code(400), (: Bad Request :)
                <error>Failed to parse granule file: { $err:description } { $err:value }.</error>
            } catch * {
                response:set-status-code(500), (: Internal Server Error :)
                <error>{ $err:code, $err:description, $err:value, " module: ", $err:module, "(", $err:line-number, ",", $err:column-number, ")" }  </error>
            }
        } </response>
    let $log := util:log("info", $response)
    return ( log:submit($response), $response )
};

(:~
 : Delete the granule with the given ID from the database.
 :
 : @param $id the id of the granule to delete
 : @return ignore, see HTTP status code
 :)
declare
    %rest:DELETE
    %rest:path("/oidb/granule/{$id}")
function granule:delete-granule($id as xs:string) {
    let $status := try {
            gran:delete($id), 204 (: No Content :)
        } catch granule:unknown {
            404 (: Not Found :)
        } catch granule:error {
            400 (: Bad Request :)
        } catch granule:unauthorized {
            401 (: Unauthorized :)
        } catch * {
            500 (: Internal Server Error :)
        }
    return <rest:response><http:response status="{ $status }"/></rest:response>
};
