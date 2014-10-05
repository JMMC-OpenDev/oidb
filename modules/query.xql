xquery version "3.0";

module namespace query="http://apps.jmmc.fr/exist/apps/oidb/query";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates";

import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

(:~
 : Display the results of the query in a paginated table.
 : 
 : @param $node
 : @param $model
 : @param $page    offset into query result (page * perpage)
 : @param $perpage number of rows to display per page
 : @return a new model with result for presentation
 :)
declare
    %templates:default("page", 1)
    %templates:default("perpage", 25)
function query:run($node as node(), $model as map(*),
                   $page as xs:integer, $perpage as xs:integer) as map(*) {
    try {
        (: Search database, use request parameter :)
        let $query := request:get-parameter('query', false())
        let $data := if ($query) then tap:execute($query, true()) else ()

        let $columns :=
            for $th in $data//th
            return map {
                'name'    := data($th/@name),
                'ucd'     := $th/a/text(),
                'ucd-url' := data($th/a/@href)
            }
        (: limit rows to page - skip row of headers 
        TODO move subsequence into tap:execute to avoid output-size-limit error with huge number of records :)
        let $rows    := subsequence($data//tr[position()!=1], 1 + ($page - 1) * $perpage, $perpage)

        return if ($rows) then
            map {
                'columns' :=    $columns,
                'rows' :=       $rows,
                'pagination' := map { 'page' := $page, 'npages' := ceiling(count($data//tr) div $perpage) }
            }
        else
            map {}
    } catch filters:error {
        map {
            'flash' := 'Failed to execute query: ' || $err:description
        }
    }
};

(:~
 : Return the current query as a text element.
 : 
 : @param $node
 : @param $model
 : @return a text node with the current query
 :)
declare function query:query($node as node(), $model as map(*)) as node() {
    text { request:get-parameter('query', '') }
};
