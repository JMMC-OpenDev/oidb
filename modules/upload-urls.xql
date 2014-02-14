xquery version "3.0";

(:~
 : Save metadata from OIFits files whose URL have been passed as parameter.
 :
 : Each file is processed by OIFitsViewer to extract metadata.
 : 
 : It returns a <response> fragment with the status of the operation for each
 : URL (<success> or <error>).
 :)

import module namespace upload="http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";

(: Split parameter into individual URLs :)
let $urls := tokenize(request:get-parameter("urls", ""), "\s")
let $db_handle := upload:getDbHandle()

let $response :=
    <response> {
        for $url in $urls
        where $url
        return ( 
            try {
                upload:upload-uri($db_handle, xs:anyURI($url), ())
            } catch * {
                <error url="{$url}"> { $err:description } </error>
            })
    } </response>

return (log:submit($response), $response)
