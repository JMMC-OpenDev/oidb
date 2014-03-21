xquery version "3.0";

(:~
 : Return an XML file for loading files in OIFitsExplorer as a collection.
 :)

declare namespace oixp="http://www.jmmc.fr/oiexplorer-data-collection/0.1";

declare option exist:serialize "method=xml";

import module namespace query="http://apps.jmmc.fr/exist/apps/oidb/query" at "query.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

let $response :=
    <oixp:oiDataCollection> 
        {
            try {
                (: build the query from the request query string :)
                let $query := query:build-query()
                (: run the ADQL SELECT :)
                let $data := tap:execute($query, true())

                (: FIXME may or may not have an access_url column :)
                (: FIXME may or may already not have a DISTINCT :)
                (: FIXME may or may be public/available :)
                for $url in distinct-values($data//td[@colname='access_url' and starts-with(., 'http')])
                return <file><file> { $url } </file></file>
            } catch * {
                comment { "Error: " || $err:description }
            }
        }
    </oixp:oiDataCollection>
    
return $response
