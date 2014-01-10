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
let $file := request:get-uploaded-file-data('file')
let $data := util:parse(util:base64-decode(xs:string($file)))
return
    <response> {
        try {
            (: optional elements :)
            let $contact := $data//contact/text()
            let $dataset := $data//dataset/text()
            
            for $file in $data//oifits
                let $filename := $file/filename/text()
                (: where to download the original file :)
                let $url      := resolve-uri($filename, $data//baseurl/text())
            
                for $target in $file/metadata/target
                   return upload:upload-file($target, $url, $dataset, $contact)
        } catch * {
            <error> { $err:description } </error>
        }
    } </response>
