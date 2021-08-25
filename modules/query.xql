xquery version "3.0";

module namespace query="http://apps.jmmc.fr/exist/apps/oidb/query";

import module namespace templates="http://exist-db.org/xquery/templates";

import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

(:~
 : Count the number of results found for a given query.
 : 
 : @param $query an ADQL query
 : @return the number of results
 :)
declare function query:count($query as xs:string) as xs:integer {
    let $query := 'SELECT COUNT(*) FROM ( ' || $query || ' ) AS r'
    return tap:execute($query)//*:TD/text()
};

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
        let $offset  := max( ( (($page - 1) * $perpage ), xs:double(0)))
        (: FIXME SELECT TOP 10 * FROM ... does not respond properly :)
(:        let $subquery := 'SELECT TOP '|| $perpage ||' OFFSET ' || ($perpage * $page) || ' * ' || ' ' ||' FROM (' || $query || ') AS e':)
        let $subquery := 'SELECT TOP '|| $perpage || ' * ' || ' ' ||' FROM (' || $query || ') AS e ' ||' OFFSET ' || ($offset) 
        let $votable := if ($query) then tap:execute($subquery) else ()
        let $data := if ($votable) then app:transform-votable($votable) else ()
        let $overflow := if ($votable and (count($data/tr) - 1) < $perpage) then tap:overflowed($votable) else false()

        let $columns :=
            for $th in $data//th
            return map { (: TODO merge with app.xql common code :)
                'name'    : data($th/@name),
		'label'   : switch ($th/@name)
                    case "em_min" return "wlen_min"
                    case "em_max" return "wlen_max"
                    default return $th/@name,
                'ucd'     : $th/a/text(),
                'ucd-url' : data($th/a/@href)
            }
        (: limit rows to page - skip row of headers :)
        let $rows := $data//tr[position()!=1]
        let $nrows  := if ($query) then query:count($query) else 0

        return
            map {
                'stats' : <stats> { attribute { "info" } { $nrows } } </stats>,
                'columns' :    $columns,
                'rows' :       $rows,
                'overflow' :   if ($overflow) then true() else (),
                'pagination' : map { 'page' : $page, 'npages' : ceiling($nrows div $perpage) }
            }
    } catch tap:error {
        let $message := if ($err:value) then ' (' || $err:value || ')' else ''
        return map {
            'flash' : $err:description || $message
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
    text { normalize-space(request:get-parameter('query', '')) }
};
