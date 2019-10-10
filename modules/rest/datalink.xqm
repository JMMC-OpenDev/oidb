xquery version "3.1";
(:~
 : This module provides a REST API for oidb-datalink and utility functions.
 :)
module namespace datalink="http://apps.jmmc.fr/exist/apps/oidb/restxq/datalink";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "../tap.xqm";
import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "../sql-utils.xql";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "../log.xqm";
import module namespace gran="http://apps.jmmc.fr/exist/apps/oidb/granule" at "../granule.xqm";



declare namespace rest="http://exquery.org/ns/restxq";

(: 
known non conformances :
- semantics can be null even if it is a required param
 
notes/feedback on datalink:
- content_length unit not standardized in datalink but obscore

Internal notes:
- why not to gather common links given a collection id instead of granule ID
- we could also provide some links fro every granule : look at simbad
- this modules mix rest and application code (could be splitted if too big)

:)

(:~
 : Get votable records for a given id
 : 
 : @param $id the granule id key used to retrieve associated records
 : @return votable datalink links
 :)
declare
    %rest:GET
    %rest:path("/oidb/datalink")
    %rest:query-param("id", "{$id}")
function datalink:datalink($id as xs:int) {
    let $query := "SELECT * FROM oidb_datalink AS t WHERE t.id='" || $id || "'"
(:    let $query := "SELECT * FROM " || $config:sql-table || " AS t WHERE t.id='" || $id || "'":)
    (: send query by TAP :)
    let $votable := tap:execute($query)   
    (: :)
    
    return $votable
};

(:~
 : Add a new datalink record for a given granule 
 : 
 : @param $id the granule id to be assocaited with the given datalink record.
 : @return a <response/> document with status for uploaded datalink.
 :)
declare
    %rest:POST("{$datalinks-doc}")
    %rest:path("/oidb/datalink/{$id}")
function datalink:add-datalink($id as xs:int, $datalinks-doc as document-node()) {
    let $response :=
        <response> {
            try {
                (: abort on error and roll back :)
                sql-utils:within-transaction(
                    function($handle as xs:long) as element(id)* {
                        for $datalink in $datalinks-doc//datalink
                            return gran:add-datalink($id,$datalink, $handle)
                    }),
                    <success>Successfully uploaded datalink(s) for '{$id}'granule id</success>
            } catch gran:error {
                response:set-status-code(400), (: Bad Request :)
                <error>{ $err:description } { $err:value }</error>
            } catch gran:unauthorized {
                response:set-status-code(401), (: Unauthorized :)
                <error>{ $err:description } { $err:value }</error>
            } catch exerr:EXXQDY0002 {
                (: data is not a valid XML document :)
                response:set-status-code(400), (: Bad Request :)
                <error>Failed to parse input file: { $err:description } { $err:value }.</error>
            } catch * {
                response:set-status-code(500), (: Internal Server Error :)
                <error>{ $err:description } { $err:value }</error>
            }
        } </response>
    return ( log:submit($response), $response )
};

(:~
 : Add datalinks record from given document
 : 
 : @return a <response/> document with status for uploaded datalink.
 :)
declare
    %rest:POST("{$datalinks-doc}")
    %rest:path("/oidb/datalink")
function datalink:add-datalinks($datalinks-doc as document-node()) {
    let $datalinks := $datalinks-doc//datalink
    let $nb-datalinks := count($datalinks)
    let $response :=
        <response> {
            try {
                (: abort on error and roll back :)
                sql-utils:within-transaction(
                    function($handle as xs:long) as element(id)* {
                        for $datalink at $pos in $datalinks
                            let $log := if ( ( $pos mod 100 ) = 0 ) then util:log("info", "add new datalink ("|| $pos || "/" || $nb-datalinks || ")") else ()
                            let $id := $datalink/@id
                            return gran:add-datalink($id,$datalink, $handle)
                    }),
                    <success>Successfully uploaded ({count($datalinks)}) datalinks </success>
            } catch gran:error {
                response:set-status-code(400), (: Bad Request :)
                <error>{ $err:description } { $err:value }</error>
            } catch gran:unauthorized {
                response:set-status-code(401), (: Unauthorized :)
                <error>{ $err:description } { $err:value }</error>
            } catch exerr:EXXQDY0002 {
                (: data is not a valid XML document :)
                response:set-status-code(400), (: Bad Request :)
                <error>Failed to parse input file: { $err:description } { $err:value }.</error>
            } catch * {
                response:set-status-code(500), (: Internal Server Error :)
                <error>{ $err:description } { $err:value }</error>
            }
        } </response>
    return ( log:submit($response), $response )
};

(:~
 : Return datalink capabilities
 : TODO finish implementation
 : @return 
 :)
declare
    %rest:GET
    %rest:path("/oidb/datalink/capabilities")
function datalink:capabilities() {
    <capabilities>TBD - copy tap's one</capabilities>
};

(:~
 : Return datalink availability
 : TODO finish implementation
 : @return 
 :)
declare
    %rest:GET
    %rest:path("/oidb/datalink/availability")
function datalink:availability() {
    <availability>TBD - copy tap's one</availability>
};
