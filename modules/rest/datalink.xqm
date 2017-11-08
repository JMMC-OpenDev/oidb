xquery version "3.1";
(:~
 : This module provides a REST API for oidb-datalink and utility functions.
 :)
module namespace datalink="http://apps.jmmc.fr/exist/apps/oidb/restxq/datalink";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "../tap.xqm";


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
 : 
 : 
 : @return 
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
 : Return datalink capabilities
 : 
 : @return 
 :)
declare
    %rest:GET
    %rest:path("/oidb/datalink/capabilities")
function datalink:datalink() {
    <capabilities>TBD - copy tap's one</capabilities>
};

(:~
 : Return datalink availability
 : 
 : @return 
 :)
declare
    %rest:GET
    %rest:path("/oidb/datalink/availability")
function datalink:datalink() {
    <availability>TBD - copy tap's one</availability>
};
