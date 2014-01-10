xquery version "3.0";

(:~
 : Save one or more metadata chunk from an output of OIFitsViewer run on 
 : one or more OIFits files.
 :
 : It also look for elements specifying:
 :  * contact information (<contact>),
 :  * dataset identification (<dataset>),
 :  * base URL where the source files are stored (<baseurl>)
 : 
 : <root>
 :   <contact>Bob &lt;bob@example.com&gt;</contact>
 :   <dataset>MyData</dataset>
 :   <baseurl>http://example.com/files/</baseurl>
 :   <oifits>
 :     <metadata>
 :       <target>...<target>
 :       ...
 :     </metadata>
 :     ...
 :   </oifits>
 :   <oifits>
 :     ...
 :   </oifits>
 :   ...
 : </root>
 : 
 : It returns a <response> fragment with the status of the operation for each
 : target (<success> or <error>).
 :)

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace util = "http://exist-db.org/xquery/util";

import module namespace upload = "http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";

(: Retrieve file from multi-part request :)
let $uploaded-file := request:get-uploaded-file-data('file')
let $data := util:parse(util:base64-decode(xs:string($uploaded-file)))
let $db_handle := upload:getDbHandle()
return
    <response> {
        try {
            (: optional elements :)
            let $obs_collection := $data//obs_collection
            let $obs_creator_name := $data//obs_creator_name
            
            for $file in $data//oifits
                let $filename := $file/filename/text()
                (: where to download the original file 
                   TODO replace by a proxy/redirect script that could then log requests even on remote sites
                :)
                let $url      := resolve-uri($filename, $data//baseurl||"/")
            
                for $target in $file/metadata/target
                   return upload:upload(
                        $db_handle, 
                        ($target/*, <access_url> { $url } </access_url>, $obs_collection, $obs_creator_name)
                        )
        } catch * {
            <error> { $err:description } </error>
        }
    } </response>
