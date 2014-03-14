xquery version "3.0";

(:~
 : This module translates an HTTP query string into an ADQL query.
 : 
 : It splits the query string into filters written as conditions and combine
 : them with boolean operations (AND and OR).
 : 
 : The filters are defined in the 'filters.xqm' module.
 :)
module namespace query="http://apps.jmmc.fr/exist/apps/oidb/query";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace filters="http://apps.jmmc.fr/exist/apps/oidb/filters" at "filters.xqm";

(:~
 : Parameters starting with these names that are not criteria for the select
 : list of the query.
 :)
declare variable $query:special-parameters := ( 'col=', 'order=', 'orderdesc', 'distinct', 'page=', 'perpage=' );

(:~
 : The name to associate with the table within the query.
 :)
declare variable $query:correlation-name := 't';


(:~
 : Return the requested column names.
 : 
 : Columns names are extracted from the request parameters named 'col'.
 : 
 : @return the list of requested column names
 :)
declare function query:columns() as item()* {
    request:get-parameter('col', ())
};

(:~
 : Format a set quantifier fragment for an ADQL query.
 : 
 : It returns a distinct quantifier if the request has 'distinct' parameter.
 : 
 : @return a set quantifier
 :)
declare %private function query:set_quantifier() as xs:string {
    if (exists(request:get-parameter('distinct', ()))) then
        "DISTINCT"
    else
        "ALL"
};

(:~
 : Format a select list of columns for an ADQL query.
 : 
 : The column names are taken from the request parameters named 'col'. If there
 : is no explicit column requested, it return any column of the table.
 : 
 : @return a select list of columns
 :)
declare %private function query:select_list() as xs:string? {
    let $columns := query:columns()
    return if(empty($columns)) then
        '*'
    else
        string-join(
            for $c in $columns
            return $query:correlation-name || '.' || $c,
            ', ')
};

(:~
 : Format an order by clause for an ADQL query.
 : 
 : The sorting key is taken from the request parameter named 'order'.
 : The results are sorted in descending order if the 'orderdesc' request
 : parameter is set.
 : 
 : @return an order by clause or empty string
 :)
declare %private function query:order_by_clause() as xs:string {
    let $sort-key := request:get-parameter('order', ())
    return if (exists($sort-key)) then
        let $ordering-specification := 
            if (exists(request:get-parameter('orderdesc', ()))) then 'DESC' else 'ASC'
        return 
            'ORDER BY ' || $query:correlation-name || "." || $sort-key || ' ' || $ordering-specification
    else
        (: no order specified :)
        ''
};

(:~
 : Format a from clause for an ADQL query.
 : 
 : @return a from clause on the application DB table
 :)
declare %private function query:from_clause() as xs:string {
    'FROM ' || $config:sql-table || ' AS ' || $query:correlation-name
};

(:~
 : Split a query string into subsequence separated by 'or' parameters.
 : 
 : Parameters within the subsequence are combined with AND, the subsequences
 : combined with OR.
 : 
 : @param $x request query string
 : @return a sequence of substrings of the query string
 :)
declare %private function query:split-query-string($x as xs:string?) as item()* {
    (
        let $before := substring-before($x, '&amp;or&amp;')
        return if (string-length($before) = 0) then $x else $before
        ,
        let $after := substring-after($x, '&amp;or&amp;')
        return if (string-length($after) = 0) then () else query:split-query-string($after)
    )
};

(:~
 : Turns a request parameter into an ADQL condition using
 : predefined filters.
 : 
 : It is using the name of the parameter to lookup a filter function.
 : That function is given the value and is expected to return an ADQL condition
 : for this value.
 : 
 : The filter is searched in the 'filters' namespace (filters.xqm module).
 : The format of the parameter depends on the filter.
 : 
 : @param $param the name=value
 : @return an ADQL select condition or () if the filter is not found or the
 : parameter is invalid
 : @error if unknown filter or failed to serialize filter
 :)
declare %private function query:predicate($param as xs:string) as xs:string? {
    let $name  := substring-before($param, '=')
    let $value := substring-after($param, '=')
    let $f := function-lookup(xs:QName('filters:' || $name), 1)
    return if (exists($f)) then 
        try {
            $f(util:unescape-uri($value, 'UTF8'))
        } catch * {
            error(xs:QName('query:error'), "Failed to transform filter " || $param|| " into ADQL condition: "  || $err:description)
        }
    else
        error(xs:QName('query:error'), "Unknown filter " || $name)
};

(:~
 : Format a WHERE clause from the parameters of the request.
 : 
 : The request is split in filters that are translated into condition
 : expressions then combined with OR and AND as they appear in the query string.
 : 
 : @return an ADQL where clause with condition from the request or '' if no
 : filter
 :)
declare %private function query:where_clause() as xs:string {
    let $search-condition := 
        string-join(
            for $x in query:split-query-string(request:get-query-string())
                let $predicates :=
                    (: filter out special and empty parameters :)
                    for $p in tokenize($x, '&amp;')[not(starts-with(., $query:special-parameters) or .='')]
                    return query:predicate($p)
                return string-join($predicates, ' AND '),
            ' OR ')
    return if ($search-condition) then
        'WHERE ' || $search-condition
    else
        ''
};

(:~
 : Return a set of clauses for the table expression of the query.
 : 
 : @return a sequence of clauses as strings
 :)
declare %private function query:table_expression() as item()* {
    (
        query:from_clause(),
        query:where_clause(),
        (: group_by :)
        (: having_clause :)
        query:order_by_clause()
    )    
};

(:~
 : Transform the HTTP parameters of the request into an ADQL query.
 : 
 : @return an ADQL SELECT statement
 :)
declare function query:build-query() as xs:string {
    string-join((
        'SELECT',
        query:set_quantifier(),
        (: set_limit, TOP xx :)
        query:select_list(),
        query:table_expression()
        ), ' ')
};

(:~
 : Escape a string for ADQL query.
 : 
 : @param $str the string to escape
 : @return the escaped string
 :)
declare function query:escape($str as xs:string) as xs:string {
    (: FIXME more escapes? :)
    replace($str, "'", "''")
};
