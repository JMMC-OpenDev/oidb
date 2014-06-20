xquery version "3.0";

module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";

(:~
 : Create a model for the context of the node with statistics on results.
 : 
 : @param $node  the node starting the context
 : @param $model the current model
 : @return a new model with statistics
 :)
declare
    %templates:wrap
function app:stats($node as node(), $model as map(*)) as map(*) {
    map:new(for $x in $model('stats')/@* return map:entry(name($x), string($x)))    
};

(:~
 : Replace a node with the column description from a VOTable header.
 : 
 : @param $node  the node to replace with header data
 : @param $model the current model
 :)
declare function app:column-header($node as node(), $model as map(*)) {
    let $header := $model('header')
    return $header/child::node()
};

(:~
 : Return a selection of items from the data row as HTML5 data attributes.
 : 
 : If an expected column is found in the row, it creates a 'data-' prefixed
 : attribute to associate with the HTML row.
 : 
 : @param $row VOTable data row
 : @return a sequence of 'data-' attributes
 :)
declare %private function app:row-data($row as node()) {
    let $data := ( 'id', 'target_name', 'bib_reference', 'access_url' )
    for $x in $row/td[@colname=$data]
    (: no data- attribute if cell is empty :)
    where $x/text()
    return attribute { 'data-' || $x/@colname } { $x/text() }
};

(:~
 : Iterate over each data row, updating the model for subsequent templating.
 : 
 : It creates a new node for each row and template processes
 : each extending the model with the row data and urls.
 : 
 : @note
 : This function differs from templates:each in that it adds row-specific data
 : to the node as HTML5 'data-' attributes.
 : 
 : @param $node  the node to use as pattern for each rows
 : @param $model the current model
 : @return a sequence of nodes, one for each row
 :  :)
declare function app:each-row($node as node(), $model as map(*)) as node()* {
    for $row in $model('rows')
    return
        element { node-name($node) } {
            $node/@*,
            app:row-data($row),
            templates:process($node/node(), map:new(($model, map:entry('row', $row))))
        }
};

(:~
 : Create and format cells for a given row of data.
 : 
 : Data formatting depends on the column type.
 : 
 : @param $node  a placeholder
 : @param $model the current model with row data
 : @return a sequence of <td/> elements for the current row
 :)
declare function app:row-cells($node as node(), $model as map(*)) {
    let $row     := $model('row')
    let $columns := $model('headers')/text()
    return
        for $cell in $row/td[@colname=$columns]
        return <td> {
            switch ($cell/@colname)
                case "access_url"
                    return
                        let $access-url := data($cell)
                        let $data-rights := $row/td[@colname='data_rights']
                        let $obs-release-date := $row/td[@colname='obs_release_date']
                        return if($data-rights and $obs-release-date) then
                            app:format-access-url($access-url, $data-rights, $obs-release-date, $row/td[@colname='obs_creator_name'])
                        else
                            $access-url
                case "s_ra"
                    return jmmc-astro:to-hms($cell)
                case "s_dec"
                    return jmmc-astro:to-dms($cell)
                case "em_min"
                case "em_max"
                    return app:format-wavelengths(number(data($cell)))
                case "t_min"
                case "t_max"
                    return app:format-mjd($cell)
                case "nb_channels"
                case "nb_vis"
                case "nb_vis2"
                case "nb_t3"
                    return if(data($cell) = -1) then '-' else data($cell)
                default
                    return translate(data($cell)," ","&#160;")
            } </td>
};

(:~
 : Given curation data, check if data is public or not.
 : 
 : @param $data_rights availability of the dataset (public/secure/proprietaty)
 : @param $release_date date of public_release
 : @return a boolean, public or not
 :)
declare function app:public-status($data_rights as xs:string?, $obs_release_date as xs:string?) as xs:boolean {
    switch ($data_rights)
        case "public"
            (: data is explicitly public :)
            return true()
        (: TODO: difference between secure and proprietary? :)
        case "secure"
        case "proprietary"
            (: or wait until release_date :)
            return if ($obs_release_date != '') then
                (: build a datetime from a SQL timestamp :)
                let $obs_release_date := dateTime(
                    xs:date(substring-before($obs_release_date, " ")),
                    xs:time(substring-after($obs_release_date, " ")))
                (: compare release date to current time :)
                return if (current-dateTime() gt $obs_release_date) then true() else false()
            else 
                (: never gonna be public :)
                false()
        default
            (: never gonna be public :)
            return false()
            
};

(:~
 : Format a cell for the access_url column.
 : 
 : It contains the link to the file and an eventual status icon for private 
 : data.
 : 
 : @param $url the URL to the OIFits file
 : @param $data_rights availability of the dataset
 : @param $release_date the date at which data become public 
 : @param $creator_name owner of the data
 : @return an <a> element
 :)
declare %private function app:format-access-url($url as xs:string, $data_rights as xs:string, $release_date as xs:string, $creator_name as xs:string?) {
    let $public := app:public-status($data_rights, $release_date)
    return 
        element {"a"} {
        attribute { "href" } { $url }, 
        if ($public or $creator_name = '') then
            ()
          else 
            (
                attribute { "rel" }                 { "tooltip" },
                attribute { "data-original-title" } { concat("Contact ", $creator_name, " for availability") }
            ),
         tokenize($url, "/")[last()] ,
         if ($public) then () else <i class="glyphicon glyphicon-lock"/> 
        }
};

(:~
 : Format a cell for a wavelength value.
 : 
 : @param $wl the wavelength in meters
 : @return the same wavelength in micrometers
 :)
declare %private function app:format-wavelengths($wl as xs:double) {
    format-number($wl * 1e6, ".00000000")
};

(:~
 : Format a cell for a mjd value.
 : 
 : @param $mjd the date in mjd
 : @return the date in a datetime format
 :)
declare %private function app:format-mjd($mjd as xs:double) {
    <a href="#" title="{$mjd}">{substring(string(jmmc-dateutil:MJDtoISO8601($mjd)),0,20)}</a>
};

(:~
 : Helper to build an URL for a given target on SIMBAD.
 : 
 : @param $name
 : @return an URL to SIMBAD for the specified target as string
 :)
declare %private function app:simbad-url($name as xs:string) as xs:string {
    concat('http://simbad.u-strasbg.fr/simbad/sim-id?Ident=', encode-for-uri($name))
};

(:~
 : Helper to build an URL for the page at the ADS abstract service for
 : the given bibliographic reference.
 : 
 : @param $bibref 
 : @return an URL to CDS's ADS as string
 :)
declare %private function app:adsbib-url($bibref as xs:string) as xs:string {
    concat("http://cdsads.u-strasbg.fr/cgi-bin/nph-bib_query?", encode-for-uri($bibref))
};

(:~
 : Helper to build an URL to a given catalogue on VizieR.
 : 
 : @param $catalogue catalogue name
 : @return an URL to the VizieR astronomical catalogue as string
 :)
declare %private function app:vizcat-url($catalogue as xs:string) as xs:string {
    concat("http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat=", encode-for-uri($catalogue))
};


declare variable $app:collections-query := adql:build-query(( 'col=obs_collection', 'col=obs_creator_name', 'collection=!~VegaObs Import' ));

(:~
 : Build a map for collections and put it in the model for templating.
 : 
 : It creates a 'collections' entry in the model for the children of the nodes.
 : 
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with collections details
 :)
declare
    %templates:wrap
function app:collections($node as node(), $model as map(*)) as map(*) {
    let $data := tap:execute($app:collections-query, true())

    return map:new(
        map:entry('collections',
            map:new(
                for $tr in $data//tr
                let $name    := $tr/td[@colname='obs_collection']/text()
                let $creator := $tr/td[@colname='obs_creator_name']/text()
                where $name != ''
                return map:entry($name, if($creator != '') then $name || " - " || $creator else $name))))
};

declare variable $app:facilities-query := adql:build-query(( 'col=facility_name', 'distinct' ));
declare variable $app:oifits-query := adql:build-query(( 'col=access_url', 'distinct' ));
(: TODO copy/update app:instruments for facilities + TBD oifits files , granules :)

declare variable $app:instruments-query := adql:build-query(( 'col=instrument_name', 'distinct' ));

(:~
 : Build a list of instrument names and put it in the model for templating.
 : 
 : It creates a 'instruments' entry in the model for the children of the node.
 : 
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with instruments list
 :)
declare
    %templates:wrap
function app:instruments($node as node(), $model as map(*)) as map(*) {
    let $data := tap:execute($app:instruments-query, true())
    let $instruments := distinct-values(
        for $tr in $data//tr
        return tokenize($tr//td[@colname='instrument_name']/text(), '[^A-Za-z0-9]')[1])

    return map:new(map:entry('instruments', $instruments))
};

declare variable $app:data-pis-query := adql:build-query(( 'col=obs_creator_name', 'distinct' ));

(:~
 : Build a list of dataPIs and put it in the model for templating.
 : 
 : It creates a 'datapis' entry in the model for the children of the node.
 : 
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with dataPI names
 :)
declare
    %templates:wrap
function app:data-pis($node as node(), $model as map(*)) as map(*) {
    let $data := tap:execute($app:data-pis-query, true())
    let $datapis := $data//td[@colname='obs_creator_name']/text()
    return map:new(($model, map:entry('datapis', $datapis)))
};

declare
    %templates:wrap
function app:sort-by($node as node(), $model as map(*)) as map(*) {
    map:new(
        map:entry('sortbys',
            map {
                (: column name       displayed text :)
                'target_name'     := "Target name",
                't_min'           := "Date",
                'instrument_name' := "Instrument"
            }))
};

(:~
 : Return of HTML input elements for each of the wavelength bands.
 : 
 : @param $node  the node to use as pattern for each rows
 : @param $model the current model
 : @return a sequence of nodes, one for each band
 :)
declare function app:input-each-band($node as node(), $model as map(*)) as node()* {
    for $n in jmmc-astro:band-names()
    (: one element for each band, process templates inside the node :)
    return element { node-name($node) } {
            $node/@*,
            attribute { 'value' } { $n },
            if ($n = $model('band')) then attribute { 'checked'} { 'checked' } else (),
            templates:process($node/node(), map:new(($model, map:entry('band', $n))))
        }
};

(:~
 : Return an element with counts of the number of observations, all OIFits 
 : files and private OIFits files in the database.
 : 
 : @param $params a sequence of parameters
 : @return a <stats> element with attributes for counts.
 :)
declare %private function app:data-stats($params as xs:string*) as node() {
    let $base-query := 
        adql:clear-pagination(
            adql:clear-select-list(
                adql:clear-order(
                    adql:clear-filter($params, 'public'))))
    let $count := function($q) { tap:execute($q, false())//*:TD/text() }
    (: FIXME 3 requests... nasty, nasty :)
    return <stats> {
        attribute { "nobservations" } { $count(adql:build-query(( $base-query, 'count=*' ))) },
        attribute { "nprivatefiles" } { $count(adql:build-query(( $base-query, 'count=*', 'public=no' ))) },
        (: FIXME even worse... can you believe it? :)
        attribute { "noifitsfiles" }  { $count('SELECT COUNT(*) FROM (' || adql:build-query(( $base-query, 'distinct', 'col=access_url')) || ') AS urls') }
    } </stats>
};

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
function app:search($node as node(), $model as map(*),
                    $page as xs:integer, $perpage as xs:integer, $all as xs:string?) as map(*) {
    try {
        (: Search database, use request parameters :)
        (: clean up pagination stuff, recovered later from function parameters :)
        let $params := adql:clear-pagination(adql:split-query-string())

        let $data := tap:execute(
            adql:build-query((
                $params,
                (: force query pagination to limit number of rows returned :)
                'page=' || $page, 'perpage=' || $perpage)),
            true())

        (: default columns to display :)
        let $columns := if($all) then
                $data//th/@name/string()
            else
                ( 'target_name', 's_ra', 's_dec', 'access_url', 'instrument_name', 'em_min', 'em_max', 'nb_channels' )
    
        let $stats   := app:data-stats($params)
    
        let $headers := $data//th[@name=$columns]
        (: limit rows to page - skip row of headers :)
        let $rows    := subsequence($data//tr[position()!=1], 1 + ($page - 1) * $perpage, $perpage)
    
        (: the query shown to the user :)
        let $query := adql:build-query($params)

        return map {
            'query' :=      $query,
            'query-edit' := 'query.html?query=' || encode-for-uri($query),
            'headers' :=    $headers,
            'rows' :=       $rows,
            'stats' :=      $stats,
            'pagination' := map { 'page' := $page, 'npages' := ceiling(number($stats/@nobservations) div $perpage) }
        }
    } catch filters:error {
        map {
            'flash' := 'Unable to build a query from search form data: ' || $err:description
        }
    }
};

(:~
 : Turn a query string into a model with values for search form elements.
 :
 : It analyzes the search filters from the request and convert them into values
 : for search form elements.
 :
 : @param $node
 : @param $model
 : @return a new model with values of the search
 :)
declare
    %templates:wrap
function app:deserialize-query-string($node as node(), $model as map(*)) as map(*) {
    map:new((
        (: --- FILTERS --- :)
        (: target=[!]~<data> :)
        map {
            'target_name' := substring-after(request:get-parameter('target', ''), '~')
        },
        (: conesearch=<position>,<equinox>,<radius>,<unit> :)
        let $tokens := tokenize(request:get-parameter('conesearch', ''), ',')
        return if(count($tokens) = 4) then
            map {
                'cs_position'    := $tokens[1],
                'cs_equinox'     := $tokens[2],
                'cs_radius'      := $tokens[3],
                'cs_radius_unit' := $tokens[4]
            }
        else
            map:new(),
        (: observationdate=[<start>]..[<end>] :)
        map {
            'date_start'  := substring-before(request:get-parameter('observationdate', ''), '..'),
            'date_end'    := substring-after(request:get-parameter('observationdate', ''), '..')
        },
        (: instrument=[!]<data> :)
        map {
            'instrument'  := request:get-parameter('instrument', '')
        },
        (: wavelengthband=<band>[,<band>]* :)
        map {
            'band'        := tokenize(request:get-parameter('wavelengthband', ''), ',')
        },
        (: collection=[!]~<data> :)
        map {
            'collection'  := substring-after(request:get-parameter('collection', ''), '~')
        },
        (: datapi=[!]~<data> :)
        map {
            'datapi'      := substring-after(request:get-parameter('datapi', ''), '~')
        },
        (: caliblevel=<level>[,<level>]* :)
        map {
            'reduction'   := tokenize(request:get-parameter('caliblevel', ''), ',')
        },
        (: public=yes|no|all :)
        map {
            'available'   := request:get-parameter('public', 'all')
        },
        (: --- ORDERING --- :)
        let $order := request:get-parameter('order', '')[1]
        let $desc := starts-with($order, '^')
        return map {
            'sortby'     := if($desc) then substring($order, 2) else $order,
            'descending' := if($desc) then () else 'yes'
        },
        (: --- PAGINATION --- :)
        map {
            'perpage'    := request:get-parameter('perpage', '25')
        }
    ))
};

(:~
 : Return components of a query string for building an ADQL select.
 : 
 : It translates the parameters from the request into filter strings suitable
 : to build an ADQL query.
 : 
 : @return a sequence of filter strings
 :)
declare function app:serialize-query-string() as xs:string* {
    (
        (: date filter: combine two parameters into one :)
        let $start := request:get-parameter('date_start', '')
        let $end   := request:get-parameter('date_end', '')
        return if($start != '' or $end != '') then
            "observationdate=" || encode-for-uri($start) || '..' || encode-for-uri($end)
        else
            (),
        (: conesearch filter :)
        let $position := request:get-parameter('cs_position', '')
        return if($position != '') then
            "conesearch=" || string-join((
                encode-for-uri($position),
                request:get-parameter('cs_equinox',     'J2000'),
                request:get-parameter('cs_radius',      '2'),
                request:get-parameter('cs_radius_unit', 'deg')), ',')
        else
            (),
        (: any other filter :)
        for $n in request:get-parameter-names()
        let $value := request:get-parameter($n, "")
        where exists($value) and $value != ''
        return switch($n)
            (: parameter name         filter with argument :)
            case "target_name" return "target=" ||     "~" || encode-for-uri($value)
            case "instrument"  return "instrument="        || encode-for-uri($value)
            case "band"        return "wavelengthband="    || string-join(for $v in $value return encode-for-uri($v), ',')
            case "collection"  return "collection=" || "~" || encode-for-uri($value)
            case "datapi"      return "datapi=" ||     "~" || encode-for-uri($value)
            case "reduction"   return "caliblevel="        || string-join(for $v in $value return encode-for-uri($v), ',')
            case "available"    return if ($value = ( 'yes', 'no' )) then "public=" || $value else ()
            case "sortby"
                return concat("order=",
                    if(request:get-parameter('descending', ())) then '' else '^',
                    encode-for-uri($value))

            case "perpage"     return "perpage=" || encode-for-uri($value)

            default            return ()
    )
};

(:~
 : Display all columns from the selected row.
 : 
 : A query with the identifier for the row is passed to the TAP service and the
 : returned VOTable is formatted as an HTML table.
 : 
 : @param $node
 : @param $model
 : @param $id the row identifier
 : @return a <table> filled with data from the raw row
 :)
declare function app:show($node as node(), $model as map(*), $id as xs:integer) {
    let $query := "SELECT * FROM " || $config:sql-table || " AS t WHERE t.id='" || $id || "'"
    (: send query by TAP :)
    let $data := tap:execute($query, true())

    return <table class="table table-striped table-bordered table-hover">
        <!-- <caption> Details for { $id } </caption> -->
        {
            for $th at $i in $data//th[@name!='id']
            let $td := $data//td[position()=index-of($data//th, $th)]
            return <tr> { $th } {
                if ($td[@colname='access_url']) then 
                    <td> <a href="{ $td/text() }"> { tokenize($td/text(), "/")[last()] }</a></td>
                else if ($td[@colname='obs_collection' and starts-with($td/text(), 'J/')]) then
                    <td> <a href="{ app:vizcat-url($td/text()) }">{ $td/text() }</a></td>
                else if ($td[@colname='bib_reference']/node()) then
                    <td> <a href="{ app:adsbib-url($td) }">{ $td/text() }</a></td>
                else
                    $td
            } </tr>
        }
    </table>
};

(: Query to get the 3 last entries :)
declare variable $app:latest-query := adql:build-query(( 'col=target_name', 'col=access_url', 'col=subdate', 'order=subdate', 'limit=3' ));

(:~
 : Create a list of the three latest files uploaded.
  :
 : @param query ADQL query for TAP service
 : @param page offset into query result (page * perpage)
 : @return an HTML list
 :)
declare function app:latest($node as node(), $model as map(*)) {
    let $data := tap:execute($app:latest-query, true())

    return <ul> {
        for $row in $data/tr[position() > 1]
        return <li>
            <span> { data($row/td[@colname='target_name']) } </span> - 
            <span> { data($row/td[@colname='subdate']) } </span>
        </li>
    } </ul>
};

(:~
 : Create a list of general informations to provide on the first homepage.
 : @param query ADQL query for TAP service
 : @param page offset into query result (page * perpage)
 : @return an HTML list
 :)
declare function app:homepage-header($node as node(), $model as map(*)) {
    let $count := function($q) { tap:execute($q, false())//*:TD/text() }
    let $base-query := ""
    
    (: TODO resynchronize code with app:data-stats :)
    let $occurences := <occurences>                
                
                
                <e><title>FACILITIES</title><c>{$count('SELECT COUNT(*) FROM (' || adql:build-query(( $base-query, 'distinct', 'col=facility_name')) || ') AS e')}</c></e>
                <e><title>INSTRUMENTS</title><c>{$count('SELECT COUNT(*) FROM (' || adql:build-query(( $base-query, 'distinct', 'col=instrument_name')) || ') AS e')}</c></e>
                <e><title>DATA-PIS</title><c>{$count('SELECT COUNT(*) FROM (' || adql:build-query(( $base-query, 'distinct', 'col=obs_creator_name')) || ') AS e')}</c></e>
                <e><title>COLLECTIONS</title><c>{$count('SELECT COUNT(*) FROM (' || adql:build-query(( $base-query, 'distinct', 'col=obs_collection')) || ') AS e')}</c></e>
                <e><title>OIFITS FILES</title><c>{$count('SELECT COUNT(*) FROM (' || adql:build-query(( $base-query, 'distinct', 'col=access_url')) || ') AS e')}</c><link>search.html</link></e>
                <e><title>GRANULES</title><c>{ $count(adql:build-query(( $base-query, 'count=*' ))) }</c><link>search.html</link></e>
                
            </occurences>
    return  <div class="text-center">
            <ul class="list-inline">
            { for $e at $pos in $occurences/e 
                let $count := if(exists($e/c/text())) then $e/c/text() else if (exists($e/q/text())) then count( tap:execute($e/q, true())//tr ) else "..."
                let $title := data($e/title)
                let $link := if(exists($e/link)) then data($e/link) else "#"
                let $style := if ($title="FACILITIES") then 'background-image: url("random-icon.xql?'||$pos||'"); margin:0;' else ()
                return 
                    <li>
                        <div class="well" style='{$style}'>
                        <a href="{$link}" style="color: #000000;"><div class="well-sm transparent" style="margin:0;">
                            <h2>{$count}</h2><b>{$title}</b></div>
                            </a>
                        </div>
                    </li>
            }</ul></div>
};

(:~
 : Add a new attribute of given name and value to the node.
 : 
 : @param $elt the element
 : @param the name of the attribute
 : @param the value of the attribute
 : @return a copy of the passed element with the new attribute
 :)
declare %private function app:add-attribute($elt as element(), $name as xs:string, $value as xs:string?) as element() {
    element { node-name($elt) } { $elt/@*, attribute { $name } { $value }, $elt/node() }
};

import module namespace login="http://apps.jmmc.fr/exist/apps/oidb/login" at "login.xqm";

(:~
 : Set the value of the passed input element to the email of the current user.
 : 
 : @param $elt
 : @param $model
 : @return a copy of the element with email as default value
 :)
declare function app:input-user-email($elt as element(), $model as map(*)) {
    app:add-attribute($elt, 'value', login:user-email())
};

(:~
 : Set the value of the passed input element to the name of the current user.
 : 
 : @param $elt
 : @param $model
 : @return a copy of the element with name as default value
 :)
declare function app:input-user-name($elt as element(), $model as map(*)) {
    app:add-attribute($elt, 'value', login:user-name())
};
