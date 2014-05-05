xquery version "3.0";

(:~
 : Analyze and save the OIFits files from a VizieR catalog at a specified URL.
 : 
 : Using the root URL of the catalog, it derives the path to the OIFits 
 : listing and process each of these files. It also get additional data from
 : the Astronomy Abstract Service.
 : 
 : It returns a <response> fragment with the status of the operation for each
 : file in the catalog (<success> or <error>).
 :)

import module namespace httpclient="http://exist-db.org/xquery/httpclient";

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace upload = "http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";

import module namespace jmmc-ads="http://exist.jmmc.fr/jmmc-resources/ads";

(: Base url for astronomical catalogues at CDS :)
declare variable $local:VIZIER_URL := "http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat="; 

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
 : Retrieve the bibcode associated with a catalog.
 : 
 : The bibcode is taken from the summary page of the specified catalog.
 : 
 : @param $url an url to the VizieR catalog page
 : @return the bibcode or an empty string if not found
 : @error failed to download catalog summary
 :)
declare %private function local:catalog-bibcode($url as xs:string) as xs:string? {
    let $url := concat($url, "&amp;target=brief")
    let $doc := httpclient:get($url, false(), <headers/>)
    return if (number($doc/@statusCode) != 200) then
            fn:error(xs:QName('httperror'),
                concat("Failed to retrieve catalog summary at ", $url))
        else
            $doc//A[starts-with(@HREF, "http://cdsbib.u-strasbg.fr/cgi-bin/cdsbib")]/text()
};

(:~
 : Extract metadata from the abstract description at ADS.
 : 
 : @param $bibcode the paper bibcode
 : @return a sequence of metadata extracted from the abstract
 :)
declare %private function local:abstract-data($bibcode as xs:string) as node()* {
    let $record := jmmc-ads:get-record($bibcode)
    return (
        <bib_reference>{ $bibcode }</bib_reference>,
        (: publication date for release date of files :)
        <obs_release_date>{ jmmc-ads:get-pub-date($record) }</obs_release_date>,
        (: use first author as collection creator :)
        <obs_creator_name>{ jmmc-ads:get-first-author($record) }</obs_creator_name>,
        (: list of keywords, comma-separated :)
        (: TODO escape commas in keywords? :)
        <keywords>{ string-join(jmmc-ads:get-keywords($record), ',') }</keywords>
    )
};

let $cat := request:get-parameter("cat", "")
let $url := concat("http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat=", encode-for-uri($cat))
let $db_handle := config:get-db-connection()

let $response :=
    <response> 
        { comment {"vizier url: "||$url}}
        {
        let $urls := local:extract-files(xs:anyURI($url))
        let $additional-data := (
            (: published files -> L3 :) 
            <calib_level>3</calib_level>,
            (: collection identifier :)
            <obs_collection>{ $cat }</obs_collection>,
            (: data from abstract: author, publication date, keywords... :)
            local:abstract-data(local:catalog-bibcode($url)) 
        )
        return ( 
            for $file in $urls
            return (
                comment {"oifits urls: " || string-join($urls," ")},
                try {
                    let $report := upload:upload-uri(
                        $db_handle,
                        resolve-uri(data($file), $url),
                        $additional-data
                    )
                    return <success url="{$file}">Successfully uploaded file <report>{ $report }</report></success>
                } catch * {
                    <error url="{$url}"> { $err:description } </error>
                } )
        ) }
    </response>

return ( log:submit($response), $response )
