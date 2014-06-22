xquery version "3.0";

(:~
 : Save metadata from OIFits files whose URL have been passed as parameter.
 :
 : Each file is processed by OIFitsViewer to extract metadata.
 : 
 : It returns a <response> fragment with the status of the operation for each
 : URL (<success> or <error>).
 :)

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace upload="http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";

(:~
 : Test the existence of a bibcode.
 : 
 : It sends the bibcode to the ADS service and check the status returned to
 : see if it knows if the code is attached to a paper.
 : 
 : @param $bibcode Bibcode to test
 : @return true if the bibcode is valid
 : @error Failure to check validity of the bibcode
 :  :)
declare
    %private
function local:valid-bibcode($bibcode as xs:string) as xs:boolean {
    let $server := 'adsabs.harvard.edu'
    let $url := concat('http://', $server, '/cgi-bin/nph-bib_query?', encode-for-uri($bibcode))
    return try {
            (: too bad, does not work with HEAD :)
            let $resp := httpclient:get($url, false(), <headers/>)
            return (number($resp/@statusCode) lt 400)
        } catch * {
            error(xs:QName('error'), 'Failed to check validity of ' || $bibcode, $err:description)
        }
};

(: Split parameter into individual URLs :)
let $urls := tokenize(request:get-parameter("urls", ""), "\s")
(:  other parameters, turned into additional metadata :)
let $more-columns := ("obs_collection", "calib_level", "bib_reference", "obs_creator_name")
let $more := <more>
        {
            for $p in request:get-parameter-names()[.=$more-columns]
            return element { $p } { request:get-parameter($p, '') }
        }
        <keywords> {
            (: trim to 6 keywords max :)
            let $keywords := subsequence(request:get-parameter('keywords', ''), 1, 6)
            return string-join($keywords, ';')
        } </keywords>
    </more>
let $db_handle := config:get-db-connection()

let $response :=
    <response> {
        (: form validation :)
        if ($more/calib_level = '') then
            <error> Calibration level field is mandatory </error>
        (: test for bibcode with calibration level :)
        else if ($more/calib_level != '3' and $more/bib_reference != '') then
            <error> Only L3 data should have a bibliographic code </error>
        else if ($more/calib_level = '3' and ($more/bib_reference = '' or not(local:valid-bibcode($more/bib_reference)))) then
            <error> Invalid bibcode { $more/bib_reference } </error>
        else
            for $url in $urls
            where $url
            return (
                try {
                    <success url="{$url}"> {
                        let $report := upload:upload-uri($db_handle, xs:anyURI($url), $more/*)
                        return ( 'Successfully uploaded file', <report>{ $report }</report> )
                    }</success>
                } catch * {
                    <error url="{$url}"> { $err:description } </error>
                })
    } </response>

return (log:submit($response), $response)
