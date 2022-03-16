xquery version "3.0";

module namespace catalogs="http://apps.jmmc.fr/exist/apps/oidb/catalogs";

import module namespace templates="http://exist-db.org/xquery/html-templating";
import module namespace lib="http://exist-db.org/xquery/html-templating/lib";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";
import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";
import module namespace filters="http://apps.jmmc.fr/exist/apps/oidb/filters" at "filters.xqm";

import module namespace query="http://apps.jmmc.fr/exist/apps/oidb/query" at "query.xql";


import module namespace jmmc-simbad="http://exist.jmmc.fr/jmmc-resources/simbad";
(: 
import module namespace comments="http://apps.jmmc.fr/exist/apps/oidb/comments" at "comments.xql";


import module namespace math="http://www.w3.org/2005/xpath-functions/math";
import module namespace facilities="http://apps.jmmc.fr/exist/apps/oidb/facilities" at "facilities.xqm";
import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";

import module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers" at "templates-helpers.xql";
import module namespace user="http://apps.jmmc.fr/exist/apps/oidb/restxq/user" at "rest/user.xqm";
import module namespace datalink="http://apps.jmmc.fr/exist/apps/oidb/restxq/datalink" at "rest/datalink.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";

import module namespace jmmc-vizier="http://exist.jmmc.fr/jmmc-resources/vizier";

import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth";
import module namespace jmmc-eso="http://exist.jmmc.fr/jmmc-resources/eso";
import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs";
import module namespace jmmc-xml="http://exist.jmmc.fr/jmmc-resources/xml";
 :)

(: This module has been set up to eplore capabilities to query for other catalogs than oidb
 : This is quite a copy of search/query that could be all 3 be merged  ?
 : It should be a good point to have some part in $config:data-root some list of catalogs and their associated preferences
 :)

(:~
 : Display the result of the query in a paginated table.
 :
 : The query is passed to a TAP service and the returned VOTable
 : content is put in the model for further template processing.
 :
 : @param $node
 : @param $model
 : @param $page    offset into query result (page * perpage)
 : @param $perpage number of results displayed per page
 : @param $all     display all columns or only a subset
 : @return a new model with search results for presentation
 :)
declare
    %templates:default("page", 1)
    %templates:default("perpage", 25)
function catalogs:search($node as node(), $model as map(*),
                    $page as xs:integer, $perpage as xs:integer, $all as xs:string?) as map(*) {
    try {
        (: Search database, use request parameters :)
        (: clean up pagination stuff, recovered later from function parameters :)
        let $params := adql:clear-pagination(adql:split-query-string())
                let $log := util:log("info", "params: " ||string-join($params, ", "))

        return if (empty($params)) then map {'empty-search':'-'}
        else
        
        let $log := util:log("info", "params: " ||string-join($params, ", "))
        
        let $paginated-query := adql:build-query((
                $params,
                (: force query pagination to limit number of rows returned :)
                'page=' || $page, 'perpage=' || $perpage))
        
        let $log := util:log("info", "query: " || $paginated-query )
        
        let $votable := tap:execute( $paginated-query )
        
        let $overflow := tap:overflowed($votable)
        let $data := app:transform-votable($votable)

        (: default columns to display :)
        let $column-names := if(exists($all) or true()) then
                $data//th/@name/string()
            else 
                ($app:main-metadata)

        (: select columns, keep order :)
        let $columns :=
            for $name in $column-names
            let $th := $data//th[@name=$name]
            let $unit := if($th/@unit) then " [" || $th/@unit || "]" else ()
            return map {
                'name'    : $name,
(:                'ucd'     : $th/a/text(),:)
(:                'ucd-url' : data($th/a/@href),:)
                'description' : $name || " : "|| data($th/@description) || $unit,
                'label'   : switch ($name)
                    case "em_min" return "wlen_min"
                    case "em_max" return "wlen_max"
                    case "calib_level" return "L"
                    default return $name
            }

        (: pick rows from transformed votable - skip row of headers :)
        let $rows    := $data//tr[position()!=1]
        
        (: the query shown to the user :)
        let $query := adql:build-query($params)
        
        let $nrows  := if ($query) then query:count($query) else 0
        
        (:        let $stats   := app:data-stats($params):)
        (: was not generic :)
        let $stats := <stats> {
            attribute { "info" } { $nrows }
        } </stats>


        (: add log request :)
        let $log := log:search(<success/>)
        return map {
            'query' :      $query,
            'query-edit' : 'query.html?query=' || encode-for-uri($query),
            'columns' :    $columns,
            'rows' :       $rows,
            'overflow' :   if ($overflow) then true() else (),
            'stats' :      $stats,
            'pagination' : map { 'page' : $page, 'npages' : ceiling($nrows div $perpage) }
        }
    } catch filters:error {
        (: add log request with error :)
        let $log := log:search(<error code="{$err:code}">{$err:description}</error>)

        (: try to provide suggestion if search by name fails :)
        let $cs-tokens := tokenize(request:get-parameter('conesearch', ''), ',')
        let $cs-position := if (count($cs-tokens) = 4) then $cs-tokens[1] else ()
        let $suggestion := if ($cs-position) then let $uri := request:get-query-string() return <span><br/>You may try <ul class="list-inline">{ for $li in jmmc-simbad:search-names($cs-position, ()) let $href:= replace($uri, "conesearch="||$cs-position, "conesearch="||$li) return <li><a href="?{$href}">{$li}</a></li>} </ul></span> else ()

        return map {
(:            'flash' : 'Unable to build a query from search form data: ' || $err:description:)
              'flash' : <span>Unable to build a query from search form data : <b><em>{$err:description}</em></b>{$suggestion}</span>
        }
    } catch tap:error {
        let $message := if ($err:value) then ' (' || $err:value || ')' else ''
        return map {
            'flash' : $err:description || $message
        }
    } catch * {
        (: add log request with error :)
        let $log := log:search(<error code="{$err:code}">{$err:description}</error>)
        return
        map {
            'flash' : 'fatal error: (' || $err:code || ')' || $err:description
        }
    }
};