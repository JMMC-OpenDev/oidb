xquery version "3.0";

(:~
 : Return the VOTable for the serialized query.
 : 
 : If the query can not be built or executed, it instead returns an <error> 
 : element with error text.
 :)

declare option exist:serialize "method=xml";

import module namespace query="http://apps.jmmc.fr/exist/apps/oidb/query" at "query.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

let $response :=
    try {
        (: build the query from the request query string :)
        let $query := query:build-query()
        (: run the ADQL SELECT :)
        let $data := tap:execute($query, false())
        return $data
    } catch * {
        response:set-status-code(400),
        <error> Error: { $err:code } - { $err:description } </error>
    }
    
return $response
