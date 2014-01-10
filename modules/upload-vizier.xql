xquery version "3.0";

(:~
 : Analyze and save the OIFits files from a VizieR catalog at a specified URL.
 : 
 : Using the root URL of the catalog, it derives the path to the OIFits 
 : listing and process each of these files.
 : 
 : It returns a <response> fragment with the status of the operation for each
 : file in the catalog (<success> or <error>).
 :)

import module namespace httpclient="http://exist-db.org/xquery/httpclient";

import module namespace upload = "http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";

(:~
 : Return a list of URLs to OIFits files from a VizieR catalog.
 : 
 : @param $url the root URL of the catalog (for example http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat=J%2FA%2BA%2F558%2FA149)
 : @return a sequence of URLs
 : @error Failed to retrieve the list of files at URL
 :)
declare %private function local:extract-files($url as xs:anyURI) {
    (: url to the Browse tab for fits files :)
    let $url := concat($url, "%2Ffits", "&amp;target=http")
    (: retrieve the file listing, convert to XML (tidy) :)
    let $doc := httpclient:get($url, false(), <headers/>)
    return
        if (number($doc/@statusCode) != 200) then
            fn:error(xs:QName('httperror'),
                concat("Failed to retrieve list of files at ", $url))
        else
            $doc/httpclient:body/html//td/a/@href[ends-with(., '.oifits') or ends-with(., '.fits') ]
};

(:~
 : Extract bibcode and catalog reference from the summary page.
 : 
 : @param $url the root URL of the catalog (for example http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat=J%2FA%2BA%2F558%2FA149)
 : @return a sequence of nodes with data
 : @error Failed to retrieve summary data at URL
 :)
declare %private function local:summary-data($url as xs:anyURI) {
    let $url := concat($url, "&amp;target=brief")
    let $doc := httpclient:get($url, false(), <headers/>)
    return if (number($doc/@statusCode) != 200) then
            fn:error(xs:QName('httperror'),
                concat("Failed to retrieve summary data at ", $url))
        else
            let $data := $doc//div[@id='brief']
            let $collection := data($data//tr[position() = 1]/td[position() = 1])
            (: FIXME: page structure, element name :)
            let $bibref := data($data//A[starts-with(@HREF, "http://cdsbib.u-strasbg.fr/cgi-bin/cdsbib")])
            return (
                <bib_reference> { $bibref } </bib_reference>,
                <obs_collection> { $collection } </obs_collection> )
};

let $cat := request:get-parameter("cat", "")
let $url := concat("http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat=",encode-for-uri($cat))
let $db_handle := upload:getDbHandle()

return
    <response> 
        { comment {"vizier url: "||$url}}
        {
        let $urls := local:extract-files(xs:anyURI($url))
        return
            ( comment {"oifits urls: "||string-join($urls," ")},        
            try {
            for $file in $urls
                return upload:upload-uri(
                    $db_handle,
                    resolve-uri(data($file), $url),
                    (
                        (: published files -> L3 :) 
                        <calib_level> 3 </calib_level>, 
                        local:summary-data($url)))
            } catch * {
            <error url="{$url}"> { $err:description } </error>
            })
        }
    </response>
