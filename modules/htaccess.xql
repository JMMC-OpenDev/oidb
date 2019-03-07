xquery version "3.0";

(:~
 : Create an hypertext access file for a specified collection.
 : 
 : It outputs a .htaccess file that would allow access to public files of the
 : collection when this file is saved to the directory of the machine serving
 : the files.
 : It opens released oifits and associated 
 :)

import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "text/plain";
declare option output:omit-xml-declaration "yes";

let $collection := request:get-parameter("obs_collection", "", true())
let $query := adql:build-query((
    'distinct', 'col=access_url', 'col=data_rights', 'col=obs_release_date',
    'collection=' || $collection,
    'public=yes' ))

let $rows := tap:execute($query, -1) 

let $datalink-query := 'SELECT distinct(d.access_url) FROM oidb_datalink as d, ' || substring-after($query, "FROM ") || ' AND d.id=t.id' 
let $datalink-rows := tap:execute($datalink-query, -1) 

return (
<p># request performed on {current-dateTime()} for collection={$collection}&#10;</p>,
<p># {count($datalink-rows//*:TR)} url need to be released for public datalinks&#10;&#10;</p>,
<p># {$datalink-query}&#10;&#10;</p>,
<p># {count($rows//*:TR)} url need to be released for public granules&#10;&#10;</p>,
<p># {$query}&#10;&#10;</p>,
for $row at $pos in $datalink-rows//*:TR
    let $data := $row/*:TD
    let $access_url := $data[1]
(:    let $data_rights := $data[2]:)
(:    let $obs_release_date := $data[3]:)
(:    let $datapi := $data[4]:)
    return
    <p>
# {$pos} datalink
&lt;Files "{ tokenize($access_url, "/")[last()] }"&gt;
    Allow from all
    Satisfy any
&lt;/Files&gt;
    </p>,
for $row at $pos in $rows//*:TR
    let $data := $row/*:TD
    let $access_url := $data[1]
    let $data_rights := $data[2]
    let $obs_release_date := $data[3]
    let $datapi := $data[4]
    return
    <p>
# {$pos} obs_release_date:{ $obs_release_date } data_right:{ $data_rights } datapi:{$datapi}
&lt;Files "{ tokenize($access_url, "/")[last()] }"&gt;
    Allow from all
    Satisfy any
&lt;/Files&gt;
    </p>
)
