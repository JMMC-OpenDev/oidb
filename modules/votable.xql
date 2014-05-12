xquery version "3.0";

(:~
 : Return the VOTable for the serialized query.
 : 
 : If the query can not be built or executed, it instead returns an <error> 
 : element with error text.
 :)

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "xml";
declare option output:media-type "application/x-votable+xml";

import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

let $response :=
    try {
        (: build the query from the request query string :)
        let $query := adql:build-query(
            (: remove pagination and column set :)
            adql:split-query-string()[not(starts-with(., ('page', 'perpage', 'col=')))]
        )
        (: run the ADQL SELECT :)
        let $data := tap:execute($query, false())
        return $data
    } catch * {
        response:set-status-code(400),
        <error> Error: { $err:code } - { $err:description } </error>
    }
    
return (
    response:set-header('Content-Disposition', 'attachment; filename="' || 'oidb-votable.xml' || '"'),
    $response
)
