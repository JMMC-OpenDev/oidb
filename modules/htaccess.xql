xquery version "3.0";

(:~
 : Create an hypertext access file for a specified collection.
 : 
 : It outputs a .htaccess file that would allow access to public files of the
 : collection when this file is saved to the directory of the machine serving
 : the files.
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
    'collection=~' || $collection,
    'public=yes' ))
    
let $rows := tap:execute($query, true())
let $access_urls := distinct-values($rows//td[@colname="access_url"]/text())

return (
<p># request performed on {current-dateTime()} for collection={$collection}&#10;</p>,
<p># {count($access_urls)} url need to be released to public&#10;&#10;</p>,
for $u at $pos in $access_urls
let $row := $rows//tr[td[@colname="access_url"]=$u][1]
let $access_url := $row/td[@colname="access_url"]/text()
let $obs_release_date := $row/td[@colname="obs_release_date"]/text()
let $data_rights := $row/td[@colname="data_rights"]/text()
order by $pos
return
    <p>
# {$pos} obs_release_date:{ $obs_release_date } data_right:= { $data_rights }
&lt;Files "{ tokenize($access_url, "/")[last()] }"&gt;
    Allow from all&#10;
    Satisfy any
&lt;/Files&gt;

    </p>
)
