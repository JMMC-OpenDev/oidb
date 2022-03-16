xquery version "3.1";

(:~
 : Create an hypertext access file for a specified collection.
 :  This seems to be unused but more elaborated since it uses maps instead of copy of xml... please check that...
 : 
 : It outputs a .htaccess file that would allow access to public files of the
 : collection when this file is saved to the directory of the machine serving
 : the files.
 : It opens released oifits and associated datalinks. Public datalink have a post filter so we do not publish these which also are associated to a private oifits ( PIONIER's pdf e.g. ).
 : 
 : Another approach could be to add release_date to datalinks so we can generate the list much faster.
 :)

import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";


declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "text/plain";
declare option output:omit-xml-declaration "yes";

let $collection := request:get-parameter("obs_collection", "", true())

let $all := map:merge(
    for $public in (true(), false())
    return
        let $yesno := if ($public) then "yes" else "no"
        let $query :=
            adql:build-query(('distinct', 'col=access_url', 'col=obs_release_date', 'col=datapi', 'col=obs_creator_name',
                             'collection=' || $collection, 'caliblevel=1,2,3', 'public=' || $yesno, 'order=^obs_release_date'))
        (: FIXME distinct is not perfect enough, we should ask for DISTINCT on (access_url) .... order by access_url, obs_release_date DESC ; :)
        (: as supported by postgres so we take for a file with multiple granules the latest release date :)
        (: do that in buld-query engine ? distinct=access_url with order=obs_release_date)
        :)
        let $rows := tap:execute($query, -1)
        (: use JOIN to get shared info for associated datalinks :) 
        let $datalink-query := replace($query, "FROM oidb AS t WHERE",
                    ", oidb_datalink.access_url FROM oidb AS t JOIN oidb_datalink on t.id = oidb_datalink.id AND")
        let $datalink-rows := tap:execute($datalink-query, -1)
        let $header :=
            (<p></p>,<p># request performed on { current-dateTime() } for collection={ $collection } and public={ $yesno
                }&#10;</p>,
                        <p># Normal query : { $query }&#10;&#10;</p>,
                                                                   <p># Join query : { $datalink-query }&#10;&#10;</p>)
        let $log := util:log("info", "return "||count($rows//*:TR))
        return map { $public : 
                        map{ "header" : $header,
                        "rows": $rows//*:TR,
                        "datalink-rows": $datalink-rows//*:TR
                        }
                }
        )

let $ok := $all(true())("datalink-rows")/*/*:TD[5]
let $bad := $all(false())("datalink-rows")/*/*:TD[5]
let $common := $bad[. = $ok]
let $log := util:log("info", "common : "||count($common))

for $public in (true(), false())
return
    let $yesno := if ($public) then "yes" else "no"
    let $log  := util:log("info", "do " || $yesno) 
    let $rows := $all($public)("rows")
    let $datalink-rows := $all($public)("datalink-rows")
    let $log := util:log("info", "before filtering:" || count($datalink-rows))
    let $datalink-access_urls := $datalink-rows/*:TD[5]
    
    (: Fix shared permissions:
       a datalink may be linked to two oifits . avoid giving access if still under embargo by another one but leave access with auth :) 
    let $datalink-rows :=
        if ($public) then
            $datalink-rows[not(./*:TD[5] = $all(not($public))("datalink-rows")/*/datalink-rows/*/*:TD[5])]
        else
            $datalink-rows | $all(not($public))("datalink-rows")[./*:TD[5] = $datalink-rows/*/*:TD[5]]
            
(:    let $new-datalink-access_urls := $datalink-rows/*:TD[5]:)
 let $log  := util:log("info", "after filtering:" || count($datalink-rows)) 
(: let $log  := util:log("info", "common:" || count($common)) :)
(: let $log  := util:log("info", count($datalink-access_urls)||" non filtered (" ||count(distinct-values($datalink-access_urls))||" distinct)") :)
(: let $log  := util:log("info", count($new-datalink-access_urls)||" filtered (" ||count(distinct-values($new-datalink-access_urls))||" distinct)") :)
    
(: Prepare oifits access list :)
    let $oifits-lines := for $group-row at $pos in $rows  group  by $access_url := tokenize($group-row/*:TD[1] , "/")[last()]
        let $row := $group-row[1]
(:  avoid group by if 'distinct on' (see before) is set up :)
(:    let $row-lines := for $row at $pos in $rows :)
        let $data := $row/*:TD
        let $access_url := $data[1]
        let $obs_release_date := $data[2]
        let $datapi := $data[3]
        let $obs_creator-name := $data[4]
        
        let $email := if ($public) then ()  else data(doc($config:data-root||"/people/people.xml")//alias[.=$datapi]/@email)
        let $obs_creator-email := if($public) then () else data(doc($config:data-root||"/people/people.xml")//alias[.=$obs_creator-name]/@email)
        
        return
            (
                <p>&#10;# {$pos} obs_release_date:{ $obs_release_date } datapi:{$datapi}&#10;&lt;Files "{ tokenize($access_url, "/")[last()] }"&gt;&#10;</p>,
                if($public) then 
                    <p>    Allow from all&#10;    Satisfy any</p>
                else 
                    <p>    Require user {string-join( ($obs_creator-email, $datapi, $email), " ")}</p>,
                <p>&#10;&lt;/Files&gt;&#10;</p>
            )
            
(: Prepare datalink access list :)
    let $datalink-lines := for $row at $pos in $datalink-rows 
        let $data := $row/*:TD
        let $access_url := $data[1]
        let $obs_release_date := $data[2]
        let $datapi := $data[3]
        let $obs_creator-name := $data[4]
        let $datalink_access_url := $data[5]   
        
        let $email := if ($public) then ()  else data(doc($config:data-root||"/people/people.xml")//alias[.=$datapi]/@email)
        let $obs_creator-email := if($public) then () else data(doc($config:data-root||"/people/people.xml")//alias[.=$obs_creator-name]/@email)
        
        return
            (
                <p>&#10;# {$pos} datalink&#10;</p>,
                <p>&lt;Files "{ tokenize($datalink_access_url, "/")[last()] }"&gt;&#10;</p>,
                if($public) then 
                    <p>    Allow from all&#10;    Satisfy any</p>
                else 
                    <p>    Require user {string-join( ($obs_creator-email, $datapi, $email), " ")}</p>,
                <p>&#10;&lt;/Files&gt;&#10;</p>
            )
    return
        ($all($public)("header"), $oifits-lines, $datalink-lines)
