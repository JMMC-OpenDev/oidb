xquery version "3.0";

module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";
import module namespace cs="http://apps.jmmc.fr/exist/apps/oidb/conesearch" at "conesearch.xqm";

import module namespace vega="http://apps.jmmc.fr/exist/apps/oidb/vega" at "vega.xqm";

import module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame" at "sesame.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";

(:~
 : Add pagination elements to the page.
 : 
 : @param $page the current page number
 : @param $npages the total number to pages returned for the request
 : @return an XHTML fragment with pagination elements
 :)
declare %private function app:pagination($page as xs:integer, $npages as xs:integer) as node() {
    (: rebuild a string with all parameters but 'page' :)
    let $parameters := string-join(
        for $n in request:get-parameter-names() 
        where $n != 'page' 
        return for $p in request:get-parameter($n, "")
            return string-join(($n, encode-for-uri($p)), "="), "&amp;")
    
    return
    <ul class="pager">
        {
            if ($page > 1) then 
                <li><a href="{ concat("?", string-join(( $parameters, "page=" || $page - 1 ), "&amp;")) }">Previous</a></li>
            else 
                () 
        }
        <li>Page { $page } / { $npages }</li>,
        { 
            if ($page < $npages) then 
                <li><a href="{ concat("?", string-join(( $parameters, "page=" || $page + 1 ), "&amp;")) }">Next</a></li>
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
 : Helper to build an URL for a given target on SIMBAD.
 : 
 : @param $name
 : @return an URL to SIMBAD for the specified target as string
 :)
declare %private function app:simbad-url($name as xs:string) as xs:string {
    concat("http://simbad.u-strasbg.fr/simbad/sim-id?NbIdent=1&amp;submit=submit+id&amp;Ident=NAME%20", encode-for-uri($name))
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

(:~
 : Transform a VOTable TableData rows into HTML
 : 
 : @param $rows a sequence of votable:TR to render
 : @return an HTML <tr>
 :)
declare %private function app:transform-table($rows as node()*, $columns as xs:string*) as item()* {
    for $row in $rows
    return <tr> 
        <td>
            <div class="dropdown">
                <a class="dropdown-toggle" data-toggle="dropdown" href="#"><span class="glyphicon glyphicon-cog"/>&#160;<b class="caret"/></a>
                <ul class="dropdown-menu" role="menu">
                    <li role="presentation"><a href="show.html?id={$row/td[@colname='id']}"><i class="glyphicon glyphicon-zoom-in"/> Details</a></li>
                    <li role="presentation"><a href="{ app:simbad-url($row/td[@colname='target_name']) }"><i class="glyphicon glyphicon-globe"/> View in SIMBAD</a></li>
                    {
                        let $bibref := $row/td[@colname='bib_reference']
                        return if ($bibref/node()) then
                            <li role="presentation"><a href="{ app:adsbib-url($bibref) }"><i class="glyphicon glyphicon-book"/> Paper at ADS</a></li>
                        else
                            ()
                    }
                    <li class="divider" role="presentation"></li>
                </ul>
            </div>
        </td>
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
        }
    </tr>
};


declare variable $app:collections-query := "SELECT DISTINCT t.obs_collection, t.obs_creator_name FROM " || $config:sql-table || " AS t";

declare %private function app:collections() {
    let $data := tap:execute($app:collections-query, true())
    for $tr in $data//tr
    return element { "collection" } {
        attribute { "name"} { $tr/td[@colname='obs_collection']/text() },
        $tr/td[@colname='obs_creator_name']/text() }
};

declare function app:select-collection($node as node(), $model as map(*), $obs_collection as xs:string?) {
    <select name="obs_collection">
        <option disabled="disabled" selected="selected">All collections</option>
        {
            for $col in app:collections()
            return <option value="{ $col/@name }">
                { if ($obs_collection = $col/@name) then attribute { "selected"} { "selected" } else () }
                { if ($col/text()) then
                    $col/@name || " - " || $col/text()
                else
                    data($col/@name)
                }
            </option>
        }         
    </select>
};

declare variable $app:instruments-query := "SELECT DISTINCT t.instrument_name FROM " || $config:sql-table || " AS t";

declare %private function app:instruments() {
    let $data := tap:execute($app:instruments-query, true())
    return distinct-values(
        for $i in $data//td[@colname='instrument_name']/text()
        (: separate instrument name from mode, FIXME :)
        return tokenize($i, '[^A-Za-z0-9]')[1])
};

declare function app:select-instrument($node as node(), $model as map(*), $instrument_name as xs:string?) {
    <select name="instrument_name">
        <option disabled="disabled" selected="selected">All instruments</option>
        {
            for $ins in app:instruments()
            return <option value="{ $ins }">
                { if ($instrument_name = $ins) then attribute { "selected"} { "selected" } else () }
                { $ins }
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
 : Resolve target from name and return its coordinates.
 : 
 : It is using the database first and if not found, try with the Sesame name
 : resolver.
 : 
 : @param $name the name of the target
 : @return an empty sequence if unknown target or sequence with sra and sdec
 :)
declare %private function app:target-coords($target as xs:string) {
    if ($target != '') then
        (: first try resolution on database :)
        let $query := "SELECT TOP 1 t.s_ra, t.s_dec FROM " || $config:sql-table || " AS t WHERE t.target_name='" || $target || "'"
        let $result := tap:execute($query, false())//*:TD/text()
        return if (empty($result)) then
            (: no result in database, resolve name with Sesame :)
            try { sesame:resolve($target)//target/(@s_ra, @s_dec) } catch * { () }
        else
            (: target found in database :)
            $result
    else
        (: incorrect target name :)
        ()
};

(:~
 : Default ADQL request for the search page: display everything
 :)
declare variable $app:default-search-query := "SELECT * FROM " || $config:sql-table;

(:~
 : Perform one of the predefined request based on request parameters.
 : 
 : @return a <votable>, possibly empty if no results
 :)
declare %private function app:pre-defined-search() as node() {
    let $search := request:get-parameter("search", "")
    return if ($search = 'conesearch') then
        (: Cone Search search :)
        let $sra     := number(request:get-parameter("s_ra", 0))
        let $sdec    := number(request:get-parameter("s_dec", 0))
        let $sradius := number(request:get-parameter("s_radius", 0))
        return cs:execute($sra, $sdec, $sradius, true())
    else if ($search ='conesearch2') then
        let $name    := request:get-parameter("target_name", "")
        let $sradius := number(request:get-parameter("s_radius", 1))
        let $sra-sdec := app:target-coords($name)
        return if (empty($sra-sdec)) then
            (: no coordinates found for given name :)
            (: TODO: print message :)
            let $msg := util:log('info', "Target '" || $name || "' not found")
            return <x/>
        else
            cs:execute($sra-sdec[1], $sra-sdec[2], $sradius, true())
    else if ($search = 'level') then
        let $levels := request:get-parameter('l', ())
        let $query := string-join((
            $app:default-search-query || " AS t ",
            string-join(for $level in $levels return "t.calib_level=" || $level, " OR ")),
            " WHERE ")
        return tap:execute($query || " ORDER BY t.subdate DESC", true())
    else if ($search = 'misc') then
        let $type  := request:get-parameter("type", "")
        let $query := if ($type = "monochromatic") then
                $app:default-search-query || " AS t WHERE t.nb_channels=1"
            else if ($type = "polychromatic") then
                $app:default-search-query || " AS t WHERE t.nb_channels>1"
            else if ($type = "kbandonly") then
                $app:default-search-query || " AS t WHERE t.em_min>1.925E-6 AND t.em_max<2.825E-6"
            else if ($type = "hband") then
                $app:default-search-query || " AS t WHERE t.em_max>1.925E-6 AND t.em_min<2.825E-6"
            else
                $app:default-search-query
        return tap:execute($query || " ORDER BY t.subdate DESC", true())
    else if ($search = 'nmeasurements') then
        (: Search for minimal number of measurements :)
        let $nvis  := number(request:get-parameter("nvis", 0))
        let $nvis2 := number(request:get-parameter("nvis2", 0))
        let $nt3   := number(request:get-parameter("nt3", 0))
        let $query := concat($app:default-search-query, " AS t WHERE t.nb_vis>=", $nvis, " AND t.nb_vis2>=", $nvis2, " AND t.nb_t3>=", $nt3)
        return tap:execute($query || " ORDER BY t.subdate DESC", true())
    else if ($search = 'collection') then 
        (: Search for collection by name :)
        let $collection := request:get-parameter("obs_collection", "")
        let $author     := request:get-parameter("obs_creator_name", "")
        let $query      := if ($collection != '') then
                concat($app:default-search-query, " AS t WHERE t.obs_collection='", $collection, "'")
            else
                concat($app:default-search-query, " AS t WHERE t.t.obs_creator_name LIKE '%", $author,"%'")
        return tap:execute($query || " ORDER BY t.subdate DESC", true())
    else if ($search = 'instrument') then
        (: Search for observations with the specified instrument :)
        let $instrument := request:get-parameter("instrument_name", "")
        let $query      := concat($app:default-search-query, " AS t WHERE t.instrument_name LIKE '", $instrument, "%'")
        return tap:execute($query || " ORDER BY t.subdate DESC", true())
    else
        (: default or custom ADQL query :)
        let $query := request:get-parameter("query", $app:default-search-query || " AS t ORDER BY t.subdate DESC")
        return tap:execute($query, true())
};

(:~
 : Display the result of the query in a paginated table.
 : 
 : The query is passed to Astrogrid DSA and the returned VOTable is formatted
 : as an HTML table.
 : 
 : @param $node
 : @param $model
 : @param $page offset into query result (page * perpage)
 : @param $perpage number of results displayed per page
 : @param $all display all columns or only a subset
 :)
declare
    %templates:default("page", 1)
    %templates:default("perpage", 25)
function app:search($node as node(), $model as map(*),
                    $page as xs:integer, $perpage as xs:integer,$all as xs:string?) {
    (: Search database, use request parameters :)
    let $data := app:pre-defined-search()

    (: default columns to display :)
    let $columns := if($all) then $data//th/@name/string() else ( 'target_name', 's_ra', 's_dec', 'access_url', 'instrument_name', 'em_min', 'em_max', 'nb_channels', 'nb_vis', 'nb_vis2', 'nb_t3' )
    

    let $headers := ( <th/>, $data//th[@name=$columns] )
    (: limit rows to page - skip row of headers :)
    let $rows    := subsequence($data//tr[position()!=1], 1 + ($page - 1) * $perpage, $perpage)
    (: number of rows for pagination :)
    let $nrows   := count($data//tr)

    let $stats := app:data-stats($data)
    let $npages := ceiling($nrows div $perpage)
    return <div>
        <div> 
            { string($stats/@nobservations) } observations from
            { string($stats/@noifitsfiles) } oifits files
            { if ($stats[@nprivatefiles='0']) then () else "(" || string($stats/@nprivatefiles) || " private)" }
        </div>
        <div>{ app:pagination($page, $npages) }</div>      
        <div><table class="table table-striped table-bordered table-hover">
            <!-- <caption> Results for <code> { $query } </code> </caption> -->
            <thead>
                { $headers }
            </thead>
            <tbody>
                { app:transform-table($rows, $columns) }
            </tbody>
        </table></div>
        <div>{ app:pagination($page, $npages) }</div>      
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

(: Hard coded request to get the 3 last entries :)
declare variable $app:latest-query := "SELECT DISTINCT TOP 3 t.target_name, t.access_url, t.subdate FROM " || $config:sql-table || " AS t ORDER BY t.subdate DESC";

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
        <td> { 'VEGA' } <br/> { vega:instrument-mode($row) } </td>,
        <td> { number($row/td[@colname='Lambda']) div 1000 } </td>, (: wavelength range, FIXME :)
        $row/td[@colname='ProgNumber'], (: Run/Program ID :)
        <td> { vega:number-of-telescopes($row) } </td>,
        <td> { vega:telescopes-configuration($row) } </td>,
        <td> { $row/td[@colname='CommentaireFileObs'][text()!='NULL']/text() } </td>, (: Special remarks, FIXME :)
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
        <td> { 'VEGA' } <br/> { vega:instrument-mode($row) } </td>,
        <td> { number($row/td[@colname='Lambda']) div 1000 } </td>, (: wavelength range, FIXME :)
        <td> { vega:number-of-telescopes($row) } </td>,
        <td> { vega:telescopes-configuration($row) } </td>,
        <td> { $row/td[@colname='CommentaireFileObs'][text()!='NULL']/text() } </td>, (: observation notes, FIXME :)
        <td> {
            vega:get-user-name($row/td[@colname='DataPI']/text())
        } </td> (: PI contact details :)
    } </tr>
};

declare %private function app:vega-all-row($row as node()) as node() {
    <tr> {
        $row/td[@colname='StarHD'], (: Object Name/Identifier :)
        <td> { $row/td[@colname='NightDir']/text() } <br/> { $row/td[@colname='JulianDay']/text() } </td>, (: Observation Date / MJD :)
        <td> { 'VEGA' } <br/> { vega:instrument-mode($row) } </td>,
        <td> { number($row/td[@colname='Lambda']) div 1000 } </td>, (: wavelength range, FIXME :)
        $row/td[@colname='ProgNumber'], (: Run/Program ID :)
        <td> { vega:number-of-telescopes($row) } </td>,
        <td> { vega:telescopes-configuration($row) } </td>,
        <td> { $row/td[@colname='CommentaireFileObs'][text()!='NULL']/text() } </td>, (: Notes, FIXME :)
        <td>
            {
                if ($row/td[@colname='DataStatus'][text()='Published']) then <i class="icon-check"/> else ()
            }
        </td>, (: Published :)
        <td> {
            vega:get-user-name($row/td[@colname='DataPI']/text())
        } </td> (: PI contact details :)
    } </tr>
};

declare function app:vega-select-star-hd($node as node(), $model as map(*), $starHD as xs:string?) {
    <select name="starHD">
        <option value="">Search by star</option>
        {
            for $hd in vega:get-star-hds(('Published', 'WaitProcessing'))
            order by $hd
            return <option value="{ $hd }">
                { if ($starHD = $hd) then attribute { "selected"} { "selected" } else () }
                { $hd }
            </option>
        }         
    </select>
};

declare function app:vega-select-all-star-hd($node as node(), $model as map(*), $starHD as xs:string?) {
    <select name="starHD">
        <option value="">Search by star</option>
        {
            for $hd in vega:get-all-star-hds()
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
        for $row in doc($vega:data-root || '/published.xml')//votable/tr[./td[@colname='StarHD' and ./text()=$starHD]]
        return app:vega-L3-row($row)
    } </tbody>
};

declare
    %templates:default("starHD", "HD213306")
function app:vega-L0($node as node(), $model as map(*), $starHD as xs:string) {
    <tbody> {
        for $row in doc($vega:data-root || '/wait-processing.xml')//votable/tr[./td[@colname='StarHD' and ./text()=$starHD]]
        return app:vega-L0-row($row)
    } </tbody>
};

declare function app:vega-all($node as node(), $model as map(*), $starHD as xs:string?) {
    <tbody> {
        let $rows := collection($vega:data-root)//votable/tr
        let $rows := if ($starHD) then $rows[./td[@colname='StarHD' and ./text()=$starHD]] else $rows
        for $row in $rows
        order by $row/td[@colname='StarHD']/text()
        return app:vega-all-row($row)
    } </tbody>
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
