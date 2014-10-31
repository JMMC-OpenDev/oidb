xquery version "3.0";

(:~
 : Create a new collection in a staging area and save the files attached to the
 : current request.
 : 
 : Each file is checked with OIExplorer so that only OIFits files are saved to
 : the collection.
 : 
 : The script returns a response element with the status of any file submitted
 : by the user.
 :)

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace jmmc-oiexplorer="http://exist.jmmc.fr/jmmc-resources/oiexplorer";

import module namespace compression="http://exist-db.org/xquery/compression";

(: staging area where to put every upload collections :)
declare variable $base-staging := $config:data-root || '/oifits/staging/';

(: the MIME type for OIFits data :)
declare variable $mime-type := 'application/oifits';

(:~
 : Strip last component from filename
 : 
 : @param $name the filename
 : @return the filename with the text following the last '/' (included) removed
 :)
declare function local:dirname($name as xs:string) as xs:string {
    string-join(tokenize($name, '/')[position()!=last()], '/')
};

(:~
 : Strip directory and suffix from filename
 : 
 : @param $name the filename
 : @param $suffix the trailing suffix to remove
 : @return the filename with no directory and no suffix
 :)
declare function local:basename($name as xs:string, $suffix as xs:string?) as xs:string {
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
declare function local:basename($name as xs:string) as xs:string {
    local:basename($name, ())
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
declare function local:save($path as xs:string, $data as xs:base64Binary, $collection as xs:string) as node() {
    let $collection := xmldb:create-collection($collection, local:dirname($path))
    
    (: TODO better test? compare checksums? search scope: staging or all? :)
    return if (not(util:binary-doc-available(resolve-uri($path, $collection || '/')))) then
        (:
            FIXME at the moment it seems it is not possible to reuse binary data
            So it saves everything in DB and then check the document.
            If the document is invalid, it is then deleted.
        :)
        let $doc := xmldb:store($collection, local:basename($path), $data, $mime-type) 

        return if ($doc) then
            try {
                jmmc-oiexplorer:check(util:binary-doc($doc)),
                <file name="{ $path }"/>
            } catch * {
                (: not an OIFits :)
                xmldb:remove($collection, local:basename($path)),
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
declare function local:unzip($name as xs:string, $data as xs:base64Binary, $base as xs:string) as node() {
    let $collection := xmldb:create-collection($base, $name)

    let $entry-filter := function($path as xs:string, $data-type as xs:string, $param as item()*) as xs:boolean {
        (: only interested in files :)
        $data-type = 'resource'
    }
    let $entry-data := function($path as xs:string, $data-type as xs:string, $data as item()?, $param as item()*) {
        (: process only binary files, others can not be OIFits :)
        if ($data instance of xs:base64Binary) then
            local:save($path, $data, $collection)
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
declare function local:upload($name as xs:string, $data as xs:base64Binary, $collection as xs:string) as node() {
    (: FIXME rough detection of zip archive :)
    if (ends-with($name, '.zip')) then
        (: open new collection :)
        local:unzip($name, $data, $collection)
    else
        local:save($name, $data, $collection)
};

(: TODO check all params :)

(: an identifier for a repository in the database :)
let $staging := request:get-parameter('staging', '')
let $collection := xmldb:create-collection($base-staging, $staging)

let $filename := request:get-parameter('filename', '')

(: TODO check size of file, add size limit :)
let $data := request:get-data()

(: put files in staging area :)
return <response>{ local:upload($filename, $data, $collection) }</response>
