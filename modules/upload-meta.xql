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

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace upload = "http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";

(: Retrieve file from multi-part request :)
let $uploaded-file := request:get-uploaded-file-data('file')
let $data := util:parse(util:base64-decode(xs:string($uploaded-file)))
let $db_handle := config:get-db-connection()
let $response :=
    <response> {
        try {
            (: optional elements :)
            let $obs_collection := $data//obs_collection
            let $obs_creator_name := $data//obs_creator_name

            return (
                for $file in $data//oifits
                let $filename := $file/filename/text()
                let $filesize := $file/size/text() idiv 1000 (: in kbytes :)
                (: where to download the original file :)
                let $url      := resolve-uri($filename, $data//baseurl||"/")
                let $more := (
                    (: access information of source file :)
                    <access_url>{ $url }</access_url>,
                    <access_format>application/fits</access_format>,
                    <access_estsize>{ $filesize }</access_estsize>,
                    (: dataset description :)
                    $obs_collection,
                    $obs_creator_name
                )
            
                let $ids :=
                    for $target in $file/metadata/target
                    return upload:upload($db_handle, ( $target/*, $more ))
                return <success>Successfully uploaded metadata file</success>
            )
        } catch * {
            <error> { $err:description } </error>
        }
    } </response>

return ( log:submit($response), $response )
