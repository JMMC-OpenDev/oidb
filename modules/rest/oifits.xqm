xquery version "3.0";

(:~
 : This module provides a REST API to upload OIFITS to a staging area.
 :)
module namespace oifits="http://apps.jmmc.fr/exist/apps/oidb/restxq/oifits";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";

import module namespace jmmc-oiexplorer="http://exist.jmmc.fr/jmmc-resources/oiexplorer";

import module namespace compression="http://exist-db.org/xquery/compression";


declare namespace rest="http://exquery.org/ns/restxq";

(: staging area where to put every upload collections :)
declare variable $oifits:base-staging := $config:data-root || '/oifits/staging/';

(: the MIME type for OIFits data :)
declare variable $oifits:mime-type := 'application/oifits';

(: Replace xmldb:encode to replace the minimal subset that keep valid resource name :)
declare %private function oifits:normalise-resource-path($path as xs:string) as xs:string
{
    (: <space> " # % : < > ? [ \ ] ^ ` { | }:) 
	(: take care of the first % replacement that MUST occur at the begining of replace sequence :)
    $path ! replace(.,"%","%25") ! replace(.,' ',"%20")! replace(.,'"',"%22") ! replace(.,"#","%23")  ! replace(.,":","%3A")  ! replace(.,"<","%3C")  ! replace(.,">","%3E")  ! replace(.,"\?","%3F")  ! replace(.,"\[","%5B")  ! replace(.,"\\","%5C")  ! replace(.,"\]","%5D")  ! replace(.,"\^","%5E")  ! replace(.,"`","%60")  ! replace(.,"\{","%7B")  ! replace(.,"\|","%7C")  ! replace(.,"\}","%7D")
};
(:~
 : Strip last component from filename
 : 
 : @param $name the filename
 : @return the filename with the text following the last '/' (included) removed
 :)
declare %private function oifits:dirname($name as xs:string) as xs:string {
    string-join(tokenize($name, '/')[position()!=last()], '/')
};

(:~
 : Strip directory and suffix from filename
 : 
 : @param $name the filename
 : @param $suffix the trailing suffix to remove
 : @return the filename with no directory and no suffix
 :)
declare %private function oifits:basename($name as xs:string, $suffix as xs:string?) as xs:string {
    let $name := tokenize($name, '/')[last()]
    return
        if ($suffix and substring($name, string-length($name) - string-length($suffix) + 1) = $suffix) then
            substring($name, 1, string-length($name) - string-length($suffix))
        else
            $name
};

(:~
 : Strip directory from filename
 : @param $name the filename
 : @return the filename with no directory
 :)
declare %private function oifits:basename($name as xs:string) as xs:string {
    oifits:basename($name, ())
};

(:~
 : Save a OIFits file as a resource in the given collection.
 : 
 : The content of the given file is checked with OIExplorer. If it is valid 
 : and new, the file is saved as a binary document with the appropriate MIME 
 : type.
 : 
 : @param $path the path relative to collection
 : @param $data the content of the file as binary data
 : @param $collection the destination collection for the file
 : @return en element with status for the operation
 :)
declare %private function oifits:save($path as xs:string, $data as xs:base64Binary, $collection as xs:string) as node() {
    let $new-collection := string-join(tokenize($path, '/')[position()!=last()] ! xmldb:encode(.), '/')
    (:    let $resource := xmldb:encode(oifits:basename($path)):)
    let $resource := oifits:normalise-resource-path(oifits:basename($path))
    
    let $collection := xmldb:create-collection($collection, $new-collection)

    (: TODO better test? compare checksums? search scope: staging or all? :)
    return if (not(util:binary-doc-available(resolve-uri($new-collection || '/' || $resource, $collection || '/')))) then
        (:
            FIXME at the moment it seems it is not possible to reuse binary data
            So it saves everything in DB and then check the document.
            If the document is invalid, it is then deleted.
        :)
        let $doc := xmldb:store($collection, $resource, $data, $oifits:mime-type)
        let $doc-name := oifits:basename($doc)

        return if ($doc) then
            try {
                jmmc-oiexplorer:check(util:binary-doc($doc)),
                <file name="{ $doc-name }" original-path="{$path}"/>
            } catch * {
                (: not an OIFits :)
                xmldb:remove($collection, oifits:basename($path)),
                <warning name="{ $path }">{ $err:description }</warning>
            }
        else
            <error name="{ $path }">Failed to store file</error>
    else
        (: file already uploaded, continue :)
        <warning name="{ $path }">File already exists</warning>
};

(:~
 : Save all OIFits files from a ZIP archive in a given collection.
 : 
 : The tree structure from the ZIP archive is preserved. Each path is prefixed
 : with the name of the ZIP file.
 : 
 : The returned element contains the status of save for each file of the
 : archive as children elements.
 : 
 : @param $name the name of the ZIP archive
 : @param $data the contents of the ZIP archive
 : @param $base the path to the collection where to save the files
 : @return a <zip> element
 :)
declare %private function oifits:unzip($name as xs:string, $data as xs:base64Binary, $base as xs:string) as node() {
    let $collection := xmldb:create-collection($base, $name)

    let $entry-filter := function($path as xs:string, $data-type as xs:string, $param as item()*) as xs:boolean {
        (: only interested in files :)
        $data-type = 'resource'
    }
    let $entry-data := function($path as xs:string, $data-type as xs:string, $data as item()?, $param as item()*) {
        (: process only binary files, others can not be OIFits :)
        if ($data instance of xs:base64Binary) then
            oifits:save($path, $data, $collection)
        else
            ()
    }
    return <zip name="{ $name }"> {
        (: unzip archive :)
        compression:unzip($data, $entry-filter, (), $entry-data, ()) 
    } </zip>
};

(:~
 : Save an individual OIFits file or the files from a zip archive in a given collection.
 : 
 : @param $name the name of the file
 : @param $data the contents of the file as binary data
 : @param $collection the path to the staging area
 : @return an element with the status of the operation
 :)
declare %private function oifits:upload($name as xs:string, $data as xs:base64Binary, $collection as xs:string) as node() {
    (: FIXME rough detection of zip archive :)
    if (ends-with($name, '.zip')) then
        (: open new collection :)
        oifits:unzip($name, $data, $collection)
    else
        oifits:save($name, $data, $collection)
};

(:~
 : Create a new collection in a staging area and save the attached file.
 : 
 : Each file is checked with OIExplorer so that only OIFits files are saved to 
 : the collection. If the file is a ZIP archive, its content is extracted and 
 : the OIFits files are saved.
 : 
 : It returns a response element with the status of any file submitted by the 
 : user. If it failed, it reports the problem through the HTTP status code of
 : the response.

 : @param $staging  the id of the staging area where to put the file
 : @param $filename the name of the uploaded file
 : @return a <response/> document with status for uploaded file.
 : @error see HTTP status code
 : 
 : @note Because of eXist-db (2.2) bug dealing with binary data, using
 : annotation for the content of the request is not possible. Rely on
 : request:get-data() within the resource function instead.
 :)
declare
(:    %rest:POST("{$data}"):)
    %rest:POST
    %rest:path("/oidb/oifits")
    %rest:query-param("staging",  "{$staging}")
    %rest:query-param("filename", "{$filename}")
    %rest:consumes("application/octet-stream", "application/oifits", "application/zip")
(:function oifits:stage-oifits($data as xs:base64Binary, $staging as xs:string, $filename as xs:string) {:)
function oifits:stage-oifits($staging as xs:string, $filename as xs:string) {
    try {
        <response> {
            let $data := request:get-data()
            let $collection := xmldb:create-collection($oifits:base-staging, $staging)
            (: put files in staging area :)
            return oifits:upload($filename, $data, $collection)
        } </response>
    } catch java:org.xmldb.api.base.XMLDBException {
        (: failed to save to staging :)
        <rest:response>
            <http:response status="401"/> <!-- Unauthorized -->
        </rest:response>
    } catch * {
        <rest:response>
            <http:response status="500"/> <!-- Internal Server Error -->
        </rest:response>
    }
};
