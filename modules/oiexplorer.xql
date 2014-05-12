xquery version "3.0";

(:~
 : Return an XML file for loading files in OIFitsExplorer as a collection.
 :)

declare namespace oixp="http://www.jmmc.fr/oiexplorer-data-collection/0.1";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "xml";
declare option output:media-type "application/x-oifits-explorer+xml";

import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

let $response :=
    <oixp:oiDataCollection> 
        {
            try {
                (: tweak the query string to build a custom ADQL query :)
                let $query := adql:build-query(
                    (
                        (: remove pagination and set of columns :)
                        adql:split-query-string()[not(starts-with(., ('page', 'perpage', 'col=')))],
                        (: select single column with file URL :)
                        'col=access_url'
                    )
                )
                (: run the ADQL SELECT :)
                let $data := tap:execute($query, true())
                (: FIXME url for search on Web portal :)
                let $url := substring-before(request:get-url(), '/modules/oiexplorer.xql') || '/search.html?' || request:get-query-string()

                return (
                    '&#xa;    ', (: poor attempt at prettyprinting the comment :)
                    comment { ' ' || $url || ' ' },
                    '&#xa;    ',
                    comment { ' ' || $query || ' ' },
                    (: FIXME may or may already not have a DISTINCT :)
                    (: FIXME may or may be public/available :)
                    for $url in distinct-values($data//td[@colname='access_url' and starts-with(., 'http')])
                    return <file><file> { $url } </file></file>
                )
            } catch * {
                comment { "Error: " || $err:description }
            }
        }
    </oixp:oiDataCollection>
    
return (
    response:set-header('Content-Disposition', 'attachment; filename="' || 'collection.xml' || '"'),
    $response
)
