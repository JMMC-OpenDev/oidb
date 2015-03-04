xquery version "3.0";

(:~
 : Return an XML file for loading files in OIFitsExplorer as a collection.
 :)

declare namespace oixp="http://www.jmmc.fr/oiexplorer-data-collection/0.1";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "xml";
declare option output:media-type "application/x-oifits-explorer+xml";

import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";
import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

let $response :=
    <oixp:oiDataCollection> 
        {
            try {
                (: tweak the query string to build a custom ADQL query :)
                let $query := adql:build-query(
                    (
                        (: remove pagination, order and set of columns :)
                        adql:clear-order(
                        adql:clear-pagination(
                            adql:clear-select-list(
                                    adql:split-query-string()))),
                        'distinct',
                        (: select single column with file URL :)
                        'col=access_url'
                    )
                )
                (: run the ADQL SELECT :)
                let $data := tap:execute($query)
                (: FIXME url for search on Web portal :)
                let $url := substring-before(request:get-url(), '/modules/oiexplorer.xql') || '/search.html?' || request:get-query-string()

                return (
                    '&#xa;    ', (: poor attempt at prettyprinting the comment :)
                    comment { ' ' || $url || ' ' },
                    '&#xa;    ',
                    comment { ' ' || $query || ' ' },
                    (: FIXME may or may be public/available :)
                    for $row in $data//*:TR
                    let $url := app:fix-relative-url($row/*:TD[position()=index-of(data($data//*:TABLE/*:FIELD/@name), 'access_url')]/text()) 
                    where starts-with($url, 'http')
                    return <file><file> { $url } </file></file>
                )
            } catch * {
                comment { "Error: " || $err:description }
            }
        }
    </oixp:oiDataCollection>
    
return (
    response:set-header('Content-Disposition', 'attachment; filename="' || 'collection.oixp' || '"'),
    $response
)
