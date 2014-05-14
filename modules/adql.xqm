xquery version "3.0";

(:~
 : This module translates an HTTP query string into an ADQL query.
 : 
 : It splits the query string into filters written as conditions and combine
 : them with boolean operations (AND and OR).
 : 
 : The filters are defined in the 'filters.xqm' module.
 :)
module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace filters="http://apps.jmmc.fr/exist/apps/oidb/filters" at "filters.xqm";

(:~
 : Parameter starting with these names are criteria for the select list
 : of the query.
 :)
declare variable $adql:filters := 
    for $f in util:list-functions('http://apps.jmmc.fr/exist/apps/oidb/filters')
    return local-name-from-QName(function-name($f)) || '=';

(:~
 : The name to associate with the table within the query.
 :)
declare variable $adql:correlation-name := 't';


(:~
 : Format a set quantifier fragment for an ADQL query.
 : 
 : It returns a distinct quantifier if there is a 'distinct' parameter.
 : 
 : @param $params a sequence of parameters
 : @return a set quantifier
 :)
declare %private function adql:set_quantifier($params as item()*) as xs:string {
    if (exists(adql:get-parameter($params, 'distinct', ()))) then
        "DISTINCT"
    else
        "ALL"
};

(:~
 : Format a limit fragment for an ADQL query.
 : 
 : It makes use of the 'page' and 'perpage' parameters to select items
 : from pages up to and including 'page'.
 : 
 : @note ADQL does not define a way to skip the items before selected rows
 : (OFFSET in SQL).
 : 
 : @param $params a sequence of parameters
 : @return a TOP fragment or an empty string
 :)
declare %private function adql:set_limit($params as xs:string*) as xs:string {
    let $limit-page :=
        let $page    := number(adql:get-parameter($params, 'page', ()))
        let $perpage := number(adql:get-parameter($params, 'perpage', 25))
        return if (string($page) != 'NaN' and string($perpage) != 'NaN') then
            $page * $perpage
        else
            ()
    let $limit-limit :=
        let $limit := number(adql:get-parameter($params, 'limit', ()))
        return if (string($limit) != 'NaN') then $limit else ()
    let $limit := max(( $limit-page, $limit-limit ))
    return if (exists($limit)) then
        "TOP " || $limit
    else
        ""
};

(:~
 : List of parameter keys for ADQL set functions
 :)
declare variable $adql:set_functions := ( 'avg', 'max', 'min', 'sum', 'count' );

(:~
 : Transform a parameter into a proper select sublist ADQL element.
 : 
 : @param $param a key-value string
 : @return a subselect clause
 :)
declare %private function adql:select_sublist($param as xs:string) as xs:string {
    let $column   := substring-after($param, '=')
    let $function := substring-before($param, '=')
    return if ($function != 'col') then
        upper-case($function) || '(' || $column || ')'
    else
        $adql:correlation-name || '.' || $column
};

(:~
 : Format a select list of columns for an ADQL query.
 : 
 : The column names are taken from the parameters named 'col'. If there
 : is no explicit column requested, it returns all columns (*) of the table.
 : 
 : Alternatively the select list can contains calls to set functions on
 : columns.
 : 
 : @param $params a sequence of parameters
 : @return a select list of columns
 :)
declare %private function adql:select_list($params as xs:string*) as xs:string? {
    let $selects := $params[starts-with(., for $f in ( $adql:set_functions, 'col' ) return $f || '=')]
    return if(empty($selects)) then
        '*'
    else
        string-join(
            for $s in $selects
            return adql:select_sublist($s), ', ')
};

(:~
 : Format an ORDER BY clause for an ADQL query.
 : 
 : The sorting keys are taken from the parameters named 'order'.
 : The results are sorted in ascending order if the value of the 'order'
 : parameter starts with '^'.
 : 
 : @param $params a sequence of parameters
 : @return an ORDER BY clause or empty string
 :)
declare %private function adql:order_by_clause($params as xs:string*) as xs:string {
    let $sort-keys := adql:get-parameter($params, 'order', ())
    return if(exists($sort-keys)) then
        'ORDER BY ' ||
            string-join(
                for $key in $sort-keys
                let $sort-key := if(starts-with($key, '^')) then substring($key, 2) else $key
                let $ordering-specification := if(substring-before($key, $sort-key) = '^') then 'ASC' else 'DESC'
                return $sort-key || ' ' || $ordering-specification
                , ', ')
    else
        (: no order specified :)
        ''
};

(:~
 : Format a from clause for an ADQL query.
 : 
 : @return a from clause on the application DB table
 :)
declare %private function adql:from_clause() as xs:string {
    'FROM ' || $config:sql-table || ' AS ' || $adql:correlation-name
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
declare %private function adql:predicate($param as xs:string) as xs:string? {
    let $name  := substring-before($param, '=')
    let $value := substring-after($param, '=')
    let $f := function-lookup(xs:QName('filters:' || $name), 1)
    return if (exists($f)) then 
        $f(util:unescape-uri($value, 'UTF8'))
    else
        error(xs:QName('adql:error'), "Unknown filter " || $name)
};

(:~
 : Format a WHERE clause from the parameters of the request.
 : 
 : It takes filter definitions from the sequence of parameters and returns a
 : clause with conditions combined by AND operations.
 : 
 : @param $params a sequence of parameters
 : @return an ADQL where clause with condition from the parameters or '' if no
 : filter
 : @todo redo the OR combination of filters
 :)
declare %private function adql:where_clause($params as xs:string*) as xs:string {
    let $search-condition := string-join(
        for $p in $params[starts-with(., $adql:filters)]
        return adql:predicate($p),
        ' AND ')
    return if($search-condition != '') then
        'WHERE ' || $search-condition
    else
        ''
};

(:~
 : Return a set of clauses for the table expression of the query.
 : 
 : @param $params a sequence of parameters
 : @return a sequence of clauses as strings
 :)
declare %private function adql:table_expression($params as xs:string*) as item()* {
    (
        adql:from_clause(),
        adql:where_clause($params),
        (: group_by :)
        (: having_clause :)
        adql:order_by_clause($params)
    )    
};

(:~
 : Return the parameter identified by name.
 : 
 : It searches in the parameter list for any parameter starting with the given
 : name and returns their values as a sequence.
 : 
 : If no parameter matches that name, the default value is returned instead.
 : 
 : @param $all-params a sequence of parameters
 : @param $name the name of the parameters to find
 : @param $default-value returned if parameter not found
 : @return a sequence of parameter values
 :)
declare %private function adql:get-parameter($all-params as xs:string*, $name as xs:string, $default-value as item()*) as item()* {
    let $params := $all-params[starts-with(., $name)]
    return if (exists($params)) then
        for $p in $params
        (: value from text after the '=', '' if no value :)
        return substring-after($p, "=")
    else
        $default-value
};

(:~
 : Turn the current HTTP query string into a sequence of parameters for
 : building and ADQL query.
 : 
 : @return a sequence of query parameters
 :)
declare function adql:split-query-string() as item()* {
    tokenize(request:get-query-string(), '&amp;')
};

(:~
 : Helper function to filter out specified parameters.
 : 
 : @param $params a sequence of parameters
 : @return a new sequence without the matching parameters
 :)
declare %private function adql:clear($params as xs:string*, $keys as xs:string*) as xs:string* {
    $params[not(starts-with(., for $k in $keys return $k || '='))]
};

(:~
 : Remove any parameter relative to data selection from a list of parameters.
 : 
 : @param $params a sequence of parameters
 : @return a new sequence without selection parameters
 :)
declare function adql:clear-select-list($params as xs:string*) as xs:string* {
    adql:clear($params, 'col')
};

(:~
 : Remove any parameter relative to pagination from a list of parameters.
 : 
 : @param $params a sequence of parameters
 : @return a new sequence without pagination parameters
 :)
declare function adql:clear-pagination($params as xs:string*) as xs:string* {
    adql:clear($params, ( 'page', 'perpage' ))
};

(:~
 : Remove any filter from a list of parameters.
 : 
 : @param $params a sequence of parameters
 : @param $filter a filter name
 : @return a new sequence without the filter
 :)
declare function adql:clear-filter($params as xs:string*, $filter as xs:string) {
    adql:clear($params, $filter)
};

(:~
 : Remove any order parameter from a list of parameters.
 : 
 : @param $params a sequence of parameters
 : @return an new sequence without order parameters
 :)
declare function adql:clear-order($params as xs:string*) {
    adql:clear($params, 'order')
};

(:~
 : Transform parameters into an ADQL query.
 : 
 : The parameters are key-value pairs separated by '=' like regular HTTP query
 : parameters.
 : 
 : @param $params a sequence of parameters
 : @return an ADQL SELECT statement
 :)
declare function adql:build-query($params as item()*) as xs:string {
    let $query := adql:get-parameter($params, 'query', ())
    return if ($query) then
        $query
    else 
        string-join(( 
            'SELECT',
            adql:set_quantifier($params),
(:            adql:set_limit($params),:)
            adql:select_list($params),
            adql:table_expression($params)
            ), ' ')
};

(:~
 : Transform the HTTP parameters of the request into an ADQL query.
 : 
 : @return an ADQL SELECT statement
 :)
declare function adql:build-query() as xs:string {
    adql:build-query(adql:split-query-string())
};

(:~
 : Escape a string for ADQL query.
 : 
 : @param $str the string to escape
 : @return the escaped string
 :)
declare function adql:escape($str as xs:string) as xs:string {
    (: FIXME more escapes? :)
    replace($str, "'", "''")
};
