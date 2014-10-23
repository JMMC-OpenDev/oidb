xquery version "3.0";

module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";
import module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers" at "templates-helpers.xql";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";
import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth";
import module namespace jmmc-eso="http://exist.jmmc.fr/jmmc-resources/eso";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";
(: Store main metadata to present in the search result table, granule summary, etc... :)
declare variable $app:main-metadata := ( 'target_name', 'access_url', 't_min', 'instrument_name', 'em_min', 'em_max', 'nb_channels', 'datapi' );

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
    let $columns := $model('columns')
    let $colnames := for $column in $columns return map:get($column, 'name')
    return
        app:td-cells($row, $colnames)
};

declare function app:td-cells($row as node(), $columns as xs:string*)
{
        (: output cells in the same order as headers :)
        for $col in $columns
        let $cell := $row/td[@colname=$col]
        return <td> {
            switch ($cell/@colname)
                case "access_url"
                    return
                        let $access-url := data($cell)
                        let $id := $row/td[@colname='id']
                        let $data-rights := $row/td[@colname='data_rights']
                        let $obs-release-date := $row/td[@colname='obs_release_date']
                        return if($data-rights and $obs-release-date) then
                            app:format-access-url($id, $access-url, $data-rights, $obs-release-date, $row/td[@colname='obs_creator_name'])
                        else
                            $access-url
                case "obs_collection"
                    return
                        let $obs-collection := data($cell)
                        return if ($obs-collection) then
                            app:format-collection-url($obs-collection)
                        else
                            ''
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
                    return if($cell = "" or data($cell) = -1) then '-' else data($cell)
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
declare %private function app:format-access-url($id as xs:string, $url as xs:string, $data_rights as xs:string, $release_date as xs:string, $creator_name as xs:string?) {
    let $public := app:public-status($data_rights, $release_date)
    return 
        element {"a"} {
        attribute { "href" } { "get-data.html?id="||$id (: $url :) }, 
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
 : Format a cell for the obs_collection column.
 : 
 : It builds an anchor element redirecting to the collection page.
 : 
 : @param $id the ID of the collection
 : @return an <a> element
 :)
declare %private function app:format-collection-url($id as xs:string) {
    let $collection := collection("/db/apps/oidb-data/collections")/collection[@id eq $id]/name/text()
    return element { "a" } {
        attribute { "href" } { "collection.html?id=" || encode-for-uri($id) },
        if ($collection) then $collection else $id
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
    <span title="{$mjd}">{substring(string(jmmc-dateutil:MJDtoISO8601($mjd)),0,20)}</span>
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


declare variable $app:collections-query := adql:build-query(( 'col=obs_collection', 'distinct' ));

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
function app:collections-options($node as node(), $model as map(*)) as map(*) {
    let $data := tap:execute($app:collections-query, false())
    let $ids := $data//*:TD/text()
    let $collections := collection("/db/apps/oidb-data/collections")/collection
    return map {
        'collections' := map:new(
            for $id in $ids
            let $name := $collections[@id=$id]/name/text()
            return map:entry($id, $name)
        )
    }
};

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
    let $data := tap:execute($app:instruments-query, false())
    let $instruments := distinct-values(
        for $instrument-name in $data//*:TD/text()
        return tokenize($instrument-name, '[^A-Za-z0-9]')[1])

    return map:new(map:entry('instruments', $instruments))
};


declare variable $app:facilities-query := adql:build-query(( 'col=facility_name', 'distinct' ));

(:~
 : Build a list of facility names and put it in the model for templating.
 : 
 : It creates a 'facilities' entry in the model for the children of the node.
 : 
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with facilities list
 :)
declare
    %templates:wrap
function app:facilities($node as node(), $model as map(*)) as map(*) {
    let $data := tap:execute($app:facilities-query, false())
    let $facilities := distinct-values($data//*:TD/text())
    return map:new(map:entry('facilities', $facilities))
};

declare variable $app:data-pis-query := adql:build-query(( 'col=datapi', 'distinct' ));

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
    let $data := tap:execute($app:data-pis-query, false())
    let $datapis := $data//*:TD/text()
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
        let $column-names := if($all) then
                $data//th/@name/string()
            else
                ( 'target_name', 'access_url', 't_min', 'instrument_name', 'em_min', 'em_max', 'nb_channels', 'datapi' )
    
        let $stats   := app:data-stats($params)
    
        (: select columns, keep order :)
        let $columns :=
            for $name in $column-names
            let $th := $data//th[@name=$name]
            return map {
                'name'    := $name,
                'ucd'     := $th/a/text(),
                'ucd-url' := data($th/a/@href)
            }

        (: limit rows to page - skip row of headers :)
        let $rows    := subsequence($data//tr[position()!=1], 1 + ($page - 1) * $perpage, $perpage)
    
        (: the query shown to the user :)
        let $query := adql:build-query($params)

        return map {
            'query' :=      $query,
            'query-edit' := 'query.html?query=' || encode-for-uri($query),
            'columns' :=    $columns,
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
        (: target=[!][~]<data> :)
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
        (: collection=[!][~]<data> :)
        map {
            'collection'  := substring-after(request:get-parameter('collection', ''), '~')
        },
        (: datapi=[!][~]<data> :)
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
            "observationdate=" || $start || '..' || $end
        else
            (),
        (: conesearch filter :)
        let $position := request:get-parameter('cs_position', '')
        return if($position != '') then
            "conesearch=" || string-join((
                $position,
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
            case "target_name" return "target=" ||     "~" || $value
            case "instrument"  return "instrument="        || $value
            case "band"        return "wavelengthband="    || string-join(for $v in $value return $v, ',')
            case "collection"  return "collection=" || "~" || $value
            case "datapi"      return "datapi=" ||     "~" || $value
            case "reduction"   return if (empty(( 0, 1, 2, 3 )[not(string(.)=$value)])) then 
                    (: default is all calibration level :)
                    ()
                else
                    "caliblevel=" || string-join(for $v in $value return $v, ',')
            case "available"    return if ($value = ( 'yes', 'no' )) then "public=" || $value else ()
            case "sortby"
                return concat("order=",
                    if(request:get-parameter('descending', ())) then '' else '^', $value
                )

            case "perpage"     return "perpage=" || $value

            default            return ()
    )
};

(:~
 : Display all columns from the selected row.
 : 
 : A query with the identifier for the row is passed to the TAP service and the
 : returned VOTable is formatted as an HTML table.
 : TODO refactor using templating
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
    let $nb-granules := count($data//tr[td])

    return if ($nb-granules=0) then
        <div data-template="templates:if-parameter-unset" data-template-param="id">
            <div class="alert alert-warning fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <strong>No granule found with id={$id}</strong>
            </div>
        </div>
        else
            ( 
        <h1> Granule {$data//td[@colname='id']/text()}</h1>
        (: app:show-granule-summary($node,  map {'granule' := app:granules($query) }, "granule")
        ,:)
        ,app:show-granule-summary($node,  map {'granule' := $data }, "granule")
        ,
        <h2> <i class="glyphicon glyphicon-align-justify"/> Table of metadata for granule {$data//td[@colname='id']/text()}</h2>
        ,
        <table class="table table-striped table-bordered table-hover">
        <!-- <caption> Details for { $id } </caption> -->
        {
            for $th at $i in $data//th[@name!='id']
            let $td := $data//td[position()=index-of($data//th, $th)]
            return <tr> <th> { $th/node() } </th> {
                if ($td[@colname='access_url']) then 
                    <td> <a href="{ $td/text() }"> { tokenize($td/text(), "/")[last()] }</a></td>
                else if ($td[@colname='obs_collection' and starts-with($td/text(), 'J/')]) then
                    <td> <a href="{ app:vizcat-url($td/text()) }">{ $td/text() }</a></td>
                else if ($td[@colname='bib_reference']/node()) then
                    <td> <a href="{ app:adsbib-url($td) }">{ $td/text() }</a></td>
                else if ($td[@colname='keywords']/node()) then  	 	 
                    <td>  	 	 
                        <link rel="stylesheet" type="text/css" href="resources/css/bootstrap-tagsinput.css"/>  	 	 
                        <div class="bootstrap-tagsinput"> {  	 	 
                            let $keywords := tokenize($td/text(), ";")  	 	 
                            for $kw in $keywords  	 	 
                            return <span class="tag label label-info">{ $kw }</span>  	 	 
                        } </div>  	 	 
                    </td>
                else
                    <td> { $td/text() } </td>
            } </tr>
        }
    </table>)
};

(:~
 : Display the summary information for a given granule.
 : 
 : TODO finish implementation using templating (see show())
 :      and implement logic to retrieve some external link from the fields of a given granule
 :      VLTI should not be hardcoded here!!
 : 
 : @param $node
 : @param $model
 : @return a <table> filled with data from the raw row
 :)
declare function app:show-granule-summary($node as node(), $model as map(*), $key as xs:string)
{
    let $granule := map:get($model, $key) 
    let $obs_id := string($granule//td[@colname='obs_id'])    
    let $facility-name := string($granule//td[@colname='facility_name'])
 
   let $sec1 := <div class="col-md-5" id="summary">
        <h2><i class="glyphicon glyphicon-zoom-in"/> Summary</h2>
        <table class="table table-striped table-bordered table-hover">
        {
            let $row := $granule//tr[td]
            let $tds := app:td-cells($row, $app:main-metadata)
            for $td at $pos in $tds
                let $m := $app:main-metadata[$pos]
                return <tr><th>{$m}</th>{$td}</tr>
        }
    </table>
    </div>
    (: :)
    let $sec2 := if($facility-name="VLTI" and $obs_id!='') then 
        let $url := $jmmc-eso:eos-url||"?progid="||encode-for-uri($obs_id)
        return <div class="col-md-5 col-md-offset-2" id="external_resources">
            <h2><i class="glyphicon glyphicon-new-window"/> External resources</h2>
        <table class="table table-striped table-bordered table-hover">
            <tr>
                <th>
                    <a href="{$url}">Jump to ESO archive for progid <em>{$obs_id}</em></a>
                </th>
                    
            </tr>
        </table>
        </div>
        else ()
    return  <div class="row">{$sec1,$sec2}</div>
};

(:~
 : Provide information to retrieve original data.
 : It returns a 303 return code if an url associated to the granule id is found else an error message is thrown.
 : A log is also store for statistic purpose.
 : a flash is thrown if url is missing
 : 
 : @param $node  the current node
 : @param $model the current model
 : @param $id    the granule id (caller template show not call this function if id is missing)
 : @return a new model with comments for the granule
 :)
declare function app:get-data($node as node(), $model as map(*), $id as xs:integer) as map(*) {
    let $query := "SELECT access_url FROM " || $config:sql-table || " AS t WHERE t.id='" || $id || "'"
    (: send query by TAP :)
    let $data := tap:execute($query, false())
    let $data-url := $data//*:TD/text()
    
    let $activate-303 := if ($data-url) then
        (response:set-header("Location", $data-url),
        response:set-status-code(303))
        else ()
        
    let $do-log := log:get-data( $id, $data-url ) 
    

    return  map { 'data-url' := if($data-url) then $data-url else (),
                      'flash'    := if($data-url) then () else "can't find associated data, please check your granule id (given is '" || $id || "')" }
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
    let $data := tap:execute($app:latest-query, false())

    let $fields := data($data//votable:FIELD/@ID)
    let $name-pos := index-of($fields, 'target_name')
    let $url-pos  := index-of($fields, 'access_url')

    return <ul> {
        for $row in $data/*:TR
        return <li>
            <span> { $row/*:TD[position()=$name-pos]/text() } </span> - 
            <span> { $row/*:TD[position()=$url-pos]/text() } </span>
        </li>
    } </ul>
};

(:~
 : Create model with general informations for homepage templating.
 : 
 : @param $node
 : @param $model
 : @return a new model with counts for homepage
 :)
declare
    %templates:wrap
function app:homepage-header($node as node(), $model as map(*)) as map(*) {
    (: count rows and extract result from VOTable :)
    let $count := function($q) { tap:execute('SELECT COUNT(*) FROM (' || adql:build-query($q) || ') AS e', false())//*:TD/text() }
    return map {
        'n_facilities'  := $count(( 'distinct', 'col=facility_name' )),
        'n_instruments' := $count(( 'distinct', 'col=instrument_name' )),
        'n_data_pis'    := $count(( 'distinct', 'col=obs_creator_name' )),
        'n_collections' := $count(( 'distinct', 'col=obs_collection' )),
        'n_oifits'      := $count(( 'distinct', 'col=access_url' )) - 1,
        'n_granules'    := $count(( 'caliblevel=1,2,3' )),
        'n_obs_logs'    := $count(( 'caliblevel=0' ))
    }
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

(:~
 : Replace node with documentation extracted from TWiki.
 : 
 : @param $node the placeholder for documentation
 : @param $model
 : @return a document fragment with documentation
 :)
declare function app:doc($node as node(), $model as map(*)) {
    doc($config:data-root || "/" || $config:maindoc-filename)
};

(:~
 : Test if a collection is from a VizieR astronomical catalog.
 : 
 : @param $c a <collection> element
 : @return true if the collection is from a VizieR catalog
 :)
declare %private function app:vizier-collection($c as element(collection)) as xs:boolean {
    starts-with(data($c/source), 'http://cdsarc.u-strasbg.fr/viz-bin/Cat')
};

(:~
 : Add collections to the model.
 : 
 : It separates collections based on their origin (at the moment, from VizieR
 : astronomical catalog or user-defined).
 : 
 : templates may call one of them using following snippet :
 : <div data-template="helpers:render" data-template-partial="_collection-short.html" data-template-key="other-collections" data-template-as="collection"/>
 : 
 : @param $node
 : @param $model
 : @return a new submodel with collections
 :)
declare function app:collections($node as node(), $model as map(*)) as map(*) {
    let $collections :=
        for $collection in collection("/db/apps/oidb-data/collections")/collection
        (: open up collection and add link to full description page :)
        return <collection> {
            $collection/@*,
            $collection/node(),
            <url>{ 'collection.html?id=' || encode-for-uri($collection/@id) }</url>
        } </collection>
    let $vizier-collections := $collections[app:vizier-collection(.)]
    return map {
        'vizier-collections' := $vizier-collections,
        'other-collections'  := $collections[not(.=$vizier-collections)]
    }
};

(:~
 : Put collection details into model for templating.
 : 
 : It takes the collection ID from a 'id' HTTP parameter in the request.
 : 
 : @param $node
 : @param $model the current model
 : @return a submodel with collection description
 :)
declare function app:collection($node as node(), $model as map(*)) as map(*) {
    let $id := request:get-parameter('id', '')
    let $collection := collection("/db/apps/oidb-data/collections")/collection[@id eq $id]
    return map { 'collection' := $collection }
};

(:~
 : Count the number of OIFITS files and granules matching a given query.
 : 
 : @param $query the ADQL query
 : @return a map with counts of OIFITS and granules
 :)
declare %private function app:stats($query as item()*) as map(*) {
    let $count := function($q) { number(tap:execute('SELECT COUNT(*) FROM (' || adql:build-query(( $q, $query )) || ') AS e', false())//*:TD) }

    return map {
        'n_oifits'   := $count(( 'distinct', 'col=access_url' )),
        'n_granules' := $count(())
    }
};

(:~
 : Add collection stats to the model for templating.
 : 
 : @param $node
 : @param $model the current model
 : @param $key the entry name in model with collection id
 : @return a submodel with stats of the requested collection
 :)
declare function app:collection-stats($node as node(), $model as map(*), $key as xs:string) as map(*) {
    let $id := helpers:get($model, $key)
    return app:stats(( 'collection=' || $id ))
};

(:~
 : Convert a row of a granule from a VOTable to XML granule.
 : 
 : @param $fields the VOTable column names
 : @param $row    the VOTable row
 : @return a XML granule
 :)
declare %private function app:votable-row-to-granule($fields as xs:string*, $row as element(votable:TR)) as element(granule){
    <granule> {
        (: turn each cell into child element whose name is the respective column name :)
        for $td at $i in $row/votable:TD
        return element { $fields[$i] } { $td/text() }
    } </granule>
};

(:~
 : Return for templating the granules matching a query grouped by source.
 : 
 : @param $query the description of the ADQL query
 : @return a sequence of granule grouped by source
 :)
declare %private function app:granules($query as item()*) as node()* {
    (: search for granules matching query :)
    let $votable := tap:execute(adql:build-query($query), false())

    (: select VOTable rows for page :)
    let $rows :=
        let $page  := number(substring-after($query[starts-with(., 'page=')], '='))
        return subsequence($votable//votable:TR,
            if (string($page) = 'NaN') then
                1
            else
                let $perpage := number($query[starts-with(., 'perpage=')])
                let $perpage := if (string($perpage) = 'NaN') then 25 else $perpage
                return 1 + ($page - 1) * $perpage)

    (: transform the VOTable :)
    let $fields := data($votable//votable:FIELD/@ID)
    let $url-pos := index-of($fields, 'access_url')
    return
        (: group by source file (access_url) :)
        for $url in distinct-values($rows/votable:TD[position()=$url-pos])
        return <file> {
            <url>{ $url }</url>,
            for $tr in $rows
            where $tr/votable:TD[position()=$url-pos]/text() = $url
            return app:votable-row-to-granule($fields, $tr)
        } </file>
};

(:~
 : Put collection granules into model from templating.
 : 
 : It takes the collection ID from a 'id' HTTP parameter in the request.
 : 
 : It ultimately adds a 'granules' entry to the model containing a sequence of
 : the collection granules grouped by source file.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @param $id    the collection identifier
 : @param $page  offset into query result (page * perpage)
 : @param $perpage number of results per page
 : @return a submodel with granules data and pagination info
 :)
declare
    %templates:default("page", 1)
    %templates:default("perpage", 25)
function app:collection-granules($node as node(), $model as map(*), $id as xs:string, $page as xs:integer, $perpage as xs:integer) as map(*) {
    let $query := ( 'collection=' || $id, 'order=^access_url' )
    let $stats := app:stats($query)

    return map {
        'granules' := app:granules(( $query, 'page=' || $page, 'perpage=' || $perpage )),
        'pagination' := map { 'page' := $page, 'npages' := ceiling($stats('n_granules') div $perpage) }
    }
};

(:~
 : Iterate over granules from a model entry and repeatedly process nested contents.
 : 
 : @note
 : This function differs from helpers:each() in that it adds a 'data-id'
 : attribute to each node.
 : 
 : @param $node  the template node to repeat
 : @param $model the current model
 : @param $from  the key in model for entry with granules to iterate over
 : @param $to    the name of the new entry in each iteration
 : @return a sequence of nodes, one for each granule
 :)
declare function app:each-granule($node as node(), $model as map(*), $from as xs:string, $to as xs:string) as node()* {
    for $granule in helpers:get($model, $from)
    return
        element { node-name($node) } {
            $node/@*,
            (: here is the magic: attach id to element for later scripting :)
            attribute { 'data-id' } { helpers:get($granule, 'id') },
            templates:process($node/node(), map:new(($model, map:entry($to, $granule))))
        }
};

(:~
 : Add the user information (name, email, affiliation) to the model for templating.
 : 
 : @param $node  the current node
 : @param $modem the current model
 : @param $key   the key to the entry in model with user id
 : @return a new model with user information
 :)
declare function app:user-info($node as node(), $model as map(*), $key as xs:string) as map(*) {
    let $user := helpers:get($model, $key)
    return map { 'user' := jmmc-auth:get-info($user) }
};

(:~
 : Truncate a text string from the model to a given length.
 : TODO: move to templates-helpers
 : 
 : @param $node the placeholder for the ellipsized text
 : @param $model
 : @param $key the key to lookup in the model for source text
 : @param $length the maximum size of text returned
 : @return a ellipsized text if too long
 :)
declare 
    %templates:default("length", "300")
function app:ellipsize($node as node(), $model as map(*), $key as xs:string, $length as xs:integer) as xs:string? {
    let $text := helpers:get($model, $key)
    return if (string-length($text) > $length) then
        substring($text, 1, $length) || '…'
    else
        $text
};

(:~
 : wrap jmmc-auth function for templating.
 : 
 : @param $node the placeholder for the email
 : @param $model
 : @param $key the key to lookup in the model for email text
 : @return the obfuscated email
 :)
declare function app:get-obfuscated-email($node as node(), $model as map(*), $key as xs:string) as xs:string? {
    jmmc-auth:get-obfuscated-email ( helpers:get($model, $key) )
};

(:~
 : Build a link to sort the results on the given column.
 : 
 : It picks the name of the column from the model and analyzes the current
 : query string to create a 'href' attribute on the current node to start a
 : new query with sorting on the current column or inverting the sorting
 : if the results have already been sorted by the column).
 : 
 : It template-processes the children of the node.
 : 
 : @param $node  the parent for the href attribute to change sorting
 : @param $model the current model
 : @return the templatized node.
 :)
declare function app:column-sort($node as node(), $model as map(*)) as node() {
    let $column := helpers:get($model, 'column')
    let $column-name := $column('name')

    let $query := adql:split-query-string()
    (: search for on existing ordering in the query :)
    let $order := substring-after($query[starts-with(., 'order=')][1], '=')
    let $asc := starts-with($order[1], '^')
    let $sort-key := substring($order[1], if ($asc) then 2 else 1)
    let $same-key := ($sort-key = $column-name)

    let $ordering :=
        if ($same-key) then
            (: invert ordering :)
            if ($asc) then '' else '^'
        else
            (: default to ascending :)
            '^'

    (: the new split query with ordering change :)
    let $new-query := ( adql:clear-order(adql:clear-pagination($query)), 'order=' || $ordering || $column-name )

    return element { node-name($node) } {
        $node/@* except ( $node/@href, $node/@class ),
        attribute { 'href'  }  { '?' || adql:to-query-string($new-query) },
        attribute { 'class' } { concat(data($node/@class), if ($asc) then ' dropup' else '') },
        templates:process($node/node(), $model),
        if ($same-key) then <span class="caret"/> else ()
    }
};
