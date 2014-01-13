xquery version "3.0";

module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

import module namespace vega="http://apps.jmmc.fr/exist/apps/oidb/vega" at "vega.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";

(:~
 : Add pagination elements to the page.
 : 
 : @param $query the ADQL query
 : @param $page the current page number
 : @param $npages the total number to pages returned for the request
 : @return an XHTML fragment with pagination elements
 :)
declare %private function app:pagination($query as xs:string, $page as xs:integer, $npages as xs:integer) {
    <ul class="pager">
        {
            if ($page > 1) then 
                <li><a href="{ concat("?query=", encode-for-uri($query), "&amp;page=", $page - 1) }">Previous</a></li>
            else 
                () 
        }
        <li>Page { $page } / { $npages }</li>,
        { 
            if ($page < $npages) then 
                <li><a href="{ concat("?query=", encode-for-uri($query), "&amp;page=", $page + 1) }">Next</a></li>
            else 
                ()
        }
    </ul>
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
         if ($public) then () else <i class="icon-lock"/> 
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
 : Transform a VOTable TableData rows into HTML
 : 
 : @param $rows a sequence of votable:TR to render
 : @return an HTML <tr>
 :)
declare %private function app:transform-table($rows as node()*, $columns as xs:string*) as item()* {
    for $row in $rows
    return <tr> 
        <td> {
            element {"a"} {
            attribute { "href" } { "show.html?id=" || $row/td[@colname='id'] },
            <i class="icon-zoom-in"/>
            }
        } </td>
        {
        for $cell in $row/td[@colname=$columns]
        return <td> {
            switch ($cell/@colname)
                case "access_url"
                    return app:format-access-url(
                        data($cell),
                        data($row/td[@colname='data_rights']),
                        data($row/td[@colname='obs_release_date']),
                        data($row/td[@colname='obs_creator_name']))
                case "em_min"
                case "em_max"
                    return app:format-wavelengths(number(data($cell)))
                case "t_min"
                case "t_max"
                    return app:format-mjd($cell)
                default
                    return translate(data($cell)," ","&#160;")
        } </td>
    } </tr>
};


declare variable $app:collections-query := "SELECT DISTINCT t.obs_collection FROM " || $config:sql-table || " AS t";

declare %private function app:collections() {
    let $data := tap:execute($app:collections-query, true())
    return $data//td/text()
};

declare function app:select-collection($node as node(), $model as map(*), $obs_collection as xs:string?) {
    <select name="obs_collection">
        <option value="">Select a collection</option>
        {
            for $col in app:collections()
            return <option value="{ $col }">
                { if ($obs_collection = $col) then attribute { "selected"} { "selected" } else () }
                { $col }
            </option>
        }         
    </select>
};

declare function app:input-all($node as node(), $model as map(*), $all as xs:string?) {
<label class="checkbox inline">            
    <input class="templates:form-control" type="checkbox" name="all" value="all">
        {if ($all) then attribute {"checked"} {""} else ()}
    </input>
    display all columns
</label>
};

(:~
 : Return an element with counts of the number of observations, all OIFits 
 : files and private OIFits files in the database.
 : 
 : @param $data a element with rows from a <votable>
 : @return a <stats> element with attributes for counts.
 :)
declare %private function app:data-stats($data as node()) as node() {
    <stats> {
        attribute { "nobservations" } { count($data//tr[td]) },
        attribute { "nprivatefiles" } { count(distinct-values($data//tr[not(app:public-status(td[@colname="data_rights"], td[@colname="obs_release_date"]))]/td[@colname="access_url"])) },
        attribute { "noifitsfiles" }  { count(distinct-values($data//td[@colname="access_url"])) }
    } </stats>
};

(:~
 : Default ADQL request for the search page: display everything
 :)
declare variable $app:default-search-query := "SELECT * FROM " || $config:sql-table;

(:~
 : Display the result of the query in a paginated table.
 : 
 : The query is passed to Astrogrid DSA and the returned VOTable is formatted
 : as an HTML table.
 : 
 : @param query ADQL query for Astrogrid DSA
 : @param page offset into query result (page * perpage)
 : @param perpage number of results displayed per page
 :)
declare
    %templates:default("page", 1)
    %templates:default("perpage", 25)
function app:search($node as node(), $model as map(*), $query as xs:string?, 
                    $page as xs:integer, $perpage as xs:integer,$all as xs:string?) {
    let $query := if($query) then $query else $app:default-search-query
                   
    let $obs_collection := request:get-parameter("obs_collection", "")
    let $query := if ($obs_collection = '') then $query else concat($query, " AS t  WHERE t.obs_collection='", $obs_collection, "'")
                      
    (: make request to DSA for query :)
    let $data := tap:execute($query, true())

    (: default columns to display :)
    let $columns := if($all) then $data//th/@name/string() else ( 'target_name', 's_ra', 's_dec', 'access_url', 'instrument_name', 'em_min', 'em_max', 'nb_channels', 'nb_vis', 'nb_vis2', 'nb_t3' )
    

    let $headers := ( <th/>, $data//th[@name=$columns] )
    (: limit rows to page - skip row of headers :)
    let $rows    := subsequence($data//tr[position()!=1], 1 + ($page - 1) * $perpage, $perpage)
    (: number of rows for pagination :)
    let $nrows   := count($data//tr)

    let $stats := app:data-stats($data)
    return <div>
        <div> 
            { string($stats/@nobservations) } observations from
            { string($stats/@noifitsfiles) } oifits files
            { if ($stats[@nprivatefiles='0']) then () else "(" || string($stats/@nprivatefiles) || " private)" }
        </div>
        <div>{ app:pagination($query, $page, ceiling($nrows div $perpage)) }</div>      
        <div><table class="table table-striped table-bordered table-hover">
            <caption> Results for <code> { $query } </code> </caption>
            <thead>
                { $headers }
            </thead>
            <tbody>
                { app:transform-table($rows, $columns) }
            </tbody>
        </table></div>
    </div>
};

(:~
 : Display all columns from the selected row.
 : 
 : A query with the identifier for the row is passed to Astrogrid DSA and the
 : returned VOTable is formatted as an HTML table.
 : 
 : @param $node
 : @param $model
 : @param $id the row identifier
 : @return a <table> filled with data from the raw row
 :)
declare function app:show($node as node(), $model as map(*), $id as xs:integer) {
    let $query := "SELECT * FROM " || $config:sql-table || " AS t WHERE t.id='" || $id || "'"
    (: make request to DSA for query :)
    let $data := tap:execute($query, true())

    return <table class="table table-striped table-bordered table-hover">
        <!-- <caption> Details for { $id } </caption> -->
        {
            for $th at $i in $data//th[@name!='id']
            let $td := $data//td[position()=$i]
            return <tr> { ( $th, $td ) } </tr>
        }
    </table>
};

(: Hard coded request to get the 3 last entries :)
declare variable $app:latest-query := "SELECT DISTINCT TOP 3 t.target_name, t.access_url, t.subdate FROM " || $config:sql-table || " AS t ORDER BY t.subdate";

(:~
 : Create a list of the three latest files uploaded.
 : 
 : @param query ADQL query for Astrogrid DSA
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
 : Test for VEGA data integration
 :)

declare %private function app:vega-L3-row($row as node()) as node() {
    <tr> {
        $row/td[@colname='StarHD'], (: Object Name/Identifier :)
        <td> { $row/td[@colname='NightDir']/text() } <br/> { $row/td[@colname='JulianDay']/text() } </td>, (: Observation Date / MJD :)
        <td> { 'VEGA' } { ' TBD' } </td>,
        <td> { number($row/td[@colname='Lambda']) div 1000 } </td>, (: wavelength range, FIXME :)
        $row/td[@colname='ProgNumber'], (: Run/Program ID :)
        <td> { vega:number-of-telescopes($row) } </td>,
        <td> { vega:telescopes-configuration($row) } </td>,
        $row/td[@colname='CommentaireFileObs'], (: Special remarks, FIXME :)
        <td> TBD </td>, (: DOI :)
        <td> {
            vega:get-user-name($row/td[@colname='DataPI']/text())
        } </td> (: PI contact details :)
    } </tr>
};

declare %private function app:vega-L0-row($row as node()) as node() {
    <tr> {
        $row/td[@colname='StarHD'], (: Object Name/Identifier :)
        <td> { $row/td[@colname='NightDir']/text() } <br/> { $row/td[@colname='JulianDay']/text() } </td>, (: Observation Date / MJD :)
        <td> { 'VEGA' } { ' TBD' } </td>,
        <td> { number($row/td[@colname='Lambda']) div 1000 } </td>, (: wavelength range, FIXME :)
        <td> { vega:number-of-telescopes($row) } </td>,
        <td> { vega:telescopes-configuration($row) } </td>,
        $row/td[@colname='CommentaireFileObs'], (: observation notes, FIXME :)
        <td> {
            vega:get-user-name($row/td[@colname='DataPI']/text())
        } </td> (: PI contact details :)
    } </tr>
};

declare %private function app:vega-all-row($row as node()) as node() {
    <tr> {
        $row/td[@colname='StarHD'], (: Object Name/Identifier :)
        <td> { $row/td[@colname='NightDir']/text() } <br/> { $row/td[@colname='JulianDay']/text() } </td>, (: Observation Date / MJD :)
        <td> { 'VEGA' } { ' TBD' } </td>,
        <td> { number($row/td[@colname='Lambda']) div 1000 } </td>, (: wavelength range, FIXME :)
        $row/td[@colname='ProgNumber'], (: Run/Program ID :)
        <td> { vega:number-of-telescopes($row) } </td>,
        <td> { vega:telescopes-configuration($row) } </td>,
        <td> { $row/td[@colname='CommentaireFileObs']/text() } <br/> Status: { $row/td[@colname='DataStatus']/text() } </td>, (: Notes, FIXME :)
        <td> {
            vega:get-user-name($row/td[@colname='DataPI']/text())
        } </td> (: PI contact details :)
    } </tr>
};

declare function app:vega-select-star-hd($node as node(), $model as map(*), $starHD as xs:string?) {
    <select name="starHD">
        <option value="">Search by star</option>
        {
            for $hd in vega:get-star-hds()
            order by $hd
            return <option value="{ $hd }">
                { if ($starHD = $hd) then attribute { "selected"} { "selected" } else () }
                { $hd }
            </option>
        }         
    </select>
};

declare
    %templates:default("starHD", "HD213306")
function app:vega-L3($node as node(), $model as map(*), $starHD as xs:string) {
    <tbody> {
        for $row in doc('/db/apps/oidb/data/vega/published.xml')//votable/tr[./td[@colname='StarHD' and ./text()=$starHD]]
        return app:vega-L3-row($row)
    } </tbody>
};

declare
    %templates:default("starHD", "HD213306")
function app:vega-L0($node as node(), $model as map(*), $starHD as xs:string) {
    <tbody> {
        for $row in doc('/db/apps/oidb/data/vega/wait-processing.xml')//votable/tr[./td[@colname='StarHD' and ./text()=$starHD]]
        return app:vega-L0-row($row)
    } </tbody>
};

declare function app:vega-all($node as node(), $model as map(*), $starHD as xs:string?) {
    <tbody> {
        let $rows := collection('/db/apps/oidb/data/vega')//votable/tr
        let $rows := if ($starHD) then $rows[./td[@colname='StarHD' and ./text()=$starHD]] else $rows
        for $row in $rows
        return app:vega-all-row($row)
    } </tbody>
};
