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
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";


declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "text/plain";
declare option output:omit-xml-declaration "yes";

let $collection := request:get-parameter("obs_collection", "", true())
let $admin-login := "pionier"
let $query := adql:build-query((
    'distinct', 'col=access_url', 'col=data_rights', 'col=obs_release_date', 'col=datapi',
    'collection=' || $collection,
    'public=no' ))
    
(: hard code indexes to improve efficiency :)
let $rows := tap:execute($query, -1) (: -1 avoids limit so we do loose and block records that should be made public :)

return (
<p># request performed on {current-dateTime()} for collection={$collection}&#10;</p>,
<p># {count($rows//*:TR)} url need to be released to public&#10;&#10;</p>,
for $row at $pos in $rows//*:TR
    let $data := $row/*:TD
    let $access_url := $data[1]
    let $data_rights := $data[2]
    let $obs_release_date := $data[3]
    let $datapi := $data[4]
    let $email := data(doc($config:data-root||"/people/people.xml")//alias[.=$datapi]/@email)
    where exists($email)
    return
    <p>
# {$pos} obs_release_date:{ $obs_release_date } data_right:{ $data_rights }  datapi:{$datapi}
&lt;Files "{ tokenize($access_url, "/")[last()] }"&gt;
    Require user {string-join( ($admin-login, $datapi, $email), " ")}
&lt;/Files&gt;

    </p>
)
