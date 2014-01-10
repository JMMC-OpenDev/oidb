xquery version "3.0";

(:~
 : Save metadata from OIFits files whose URL have been passed as parameter.
 :
 : Each file is processed by OIFitsViewer to extract metadata.
 : 
 : It returns a <response> fragment with the status of the operation for each
 : URL (<success> or <error>).
 :)

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";

(: TODO: compute distinct access_url from adql ? :)
declare variable $query := "SELECT t.access_url, t.data_rights, t.obs_release_date FROM " || $config:sql-table || " AS t";

declare option exist:serialize "method=text media-type=text/plain omit-xml-declaration=yes";

let $collection := request:get-parameter("obs_collection", "", true())
let $rows := tap:execute(concat($query," WHERE t.obs_collection='", $collection, "'"), true())
let $access_urls := distinct-values($rows//td[@colname="access_url"]/text())

for $u at $pos in $access_urls
let $row := $rows//tr[td[@colname="access_url"]=$u][1]
let $access_url := $row/td[@colname="access_url"]/text()
let $obs_release_date := $row/td[@colname="obs_release_date"]/text()
let $data_rights := $row/td[@colname="data_rights"]/text()
let $public := app:public-status($data_rights, $obs_release_date)
where $public
order by $pos
return
    <p>
# {$pos} obs_release_date:{ $obs_release_date } data_right:= { $data_rights }
&lt;Files "{ tokenize($access_url, "/")[last()] }"&gt;
    { 
        if ($public) then "Allow from all&#10;    Satisfy any" else ()
    }
&lt;/Files&gt;

    </p>
