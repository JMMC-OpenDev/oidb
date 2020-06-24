xquery version "3.0";

module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace math="http://www.w3.org/2005/xpath-functions/math";
import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace comments="http://apps.jmmc.fr/exist/apps/oidb/comments" at "comments.xql";
import module namespace filters="http://apps.jmmc.fr/exist/apps/oidb/filters" at "filters.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";
import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";

import module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers" at "templates-helpers.xql";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";
import module namespace user="http://apps.jmmc.fr/exist/apps/oidb/restxq/user" at "rest/user.xqm";
import module namespace datalink="http://apps.jmmc.fr/exist/apps/oidb/restxq/datalink" at "rest/datalink.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";
import module namespace jmmc-simbad="http://exist.jmmc.fr/jmmc-resources/simbad";

import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth" at "/db/apps/jmmc-resources/content/jmmc-auth.xql";
import module namespace jmmc-eso="http://exist.jmmc.fr/jmmc-resources/eso";
import module namespace jmmc-ads="http://exist.jmmc.fr/jmmc-resources/ads";
import module namespace jmmc-xml="http://exist.jmmc.fr/jmmc-resources/xml";

declare namespace sm="http://exist-db.org/xquery/securitymanager";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";
(: Store main metadata to present in the search result table, granule summary, etc... :)
declare variable $app:main-metadata := ( 'target_name', 'access_url', 't_min', 'instrument_name', 'em_min', 'em_max', 'nb_channels', 'datapi' );

(: UCD (Unified Content Descriptor) description service :)
declare variable $app:UCD_URL := "http://cdsws.u-strasbg.fr/axis/services/UCD?method=explain&amp;ucd=";


declare variable $app:domain := "fr.jmmc.oidb.login";

declare function app:user-allowed() as xs:boolean {
    let $user := request:get-attribute($app:domain || '.user')
    return $user and $user != "guest"
};

(:~
 : Return the admin state (from central JMMC user account system or local existdb admin).
 : @return true() if the user is superuser else false()
 :)
declare function app:user-admin() as xs:boolean {
    try{
        sm:id()//sm:group[.='oidb']
        or
        request:get-attribute($app:domain || '.superuser')
        or
        (: allow offline developpement :)
        exists ( ("guillaume.mella@","admin")[matches( request:get-attribute($app:domain || '.user') , .)] )
    }catch *{
        false()
    }
};

(:~
 : Return the login name.
 : @return the user-name (login) if any
 :)
declare function app:user-name() as xs:string {
    let $user := request:get-attribute($app:domain || '.user')
    return $user
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
            templates:process($node/node(), map:merge(($model, map:entry('row', $row))))
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
        app:td-cells($row, $colnames)//td (: ignore tr parent of tds :)
};

declare function app:tr-cells($rows as node()*, $columns as xs:string*)
{
    let $trs := app:td-cells($rows, $columns )
    for $tr at $pos in $trs
        let $m := $columns[$pos]
        return <tr><th>{$m}</th>{$tr//td}</tr>
};

(:~
 : Output a tr fragment per given column picking data from given rows.
 :
 : @param $rows the rows to search data into
 : @param $columns the list of column name to output
 : @return a sequence of <tr/> elements for the each columns with one td per row
 :)
declare function app:td-cells($rows as node()*, $columns as xs:string*)
{
        (: output cells in the same order as headers :)
        for $col in $columns
        return <tr>
        {
            for $row in $rows
            let $cell := $row/td[@colname=$col]
                return
                    if($cell) then app:td-cell($cell, $row) else <td class="missing-column-{$col}"/>
        }
        </tr>
};

(:~
 : Output a td fragment per given column picking data from given row.
 :
 : @param $cell the cell element to convert if appropriate
 : @param $columns the list of column name to output
 : @param $row the row to search complimentary data into
 : @return a <td/> element for the given cell
 :)
declare function app:td-cell($cell as node(), $row as node()*) as element()
{
    <td> {
                switch ($cell/@colname)
                    case "access_url"
                        return
                            let $access-url := data($cell)
                            let $id := $row/td[@colname='id']
                            let $data-rights := $row/td[@colname='data_rights']
                            let $obs-release-date := $row/td[@colname='obs_release_date']
                            return app:format-access-url($id, $access-url, $data-rights, $obs-release-date, $row/td[@colname='obs_creator_name'], $row/td[@colname='datapi'], $row/td[@colname='calib_level'])
                    case "datapi"
                        return
                            let $id := $row/td[@colname='id']
                            return <span>{data($cell)}<a href="show.html?id={$id}#contact">&#160;<i class="glyphicon glyphicon-envelope"/> </a></span>
                    case "bib_reference"
                        return <a href="{ app:adsbib-url($cell) }">{ data($cell) }</a>
                    case "em_min"
                    case "em_max"
                        return app:format-wavelengths(data($cell))
                    case "obs_collection"
                        return
                            let $obs-collection := data($cell)
                            return if ($obs-collection) then
                                app:format-collection-url($obs-collection)
                            else
                                ''
                    case "id"
                        return <a href="show.html?id={$cell}">{data($cell)}</a>
                    case "keywords"
                        return if(exists(data($cell)) and data($cell)!="") then
                            <div class="bootstrap-tagsinput"> {
                                let $keywords := tokenize($cell, ";")
                                for $kw in $keywords
                                    return <span class="tag label label-info">{ $kw }</span>
                            }</div>
                            else ''
                    case "s_ra"
                        return jmmc-astro:to-hms($cell)
                    case "s_dec"
                        return jmmc-astro:to-dms($cell)
                    case "t_min"
                    case "t_max"
                        return app:format-mjd($cell)
                    case "nb_channels"
                    case "nb_vis"
                    case "nb_vis2"
                    case "nb_t3"
                        return if($cell = "" or data($cell) = -1) then '-' else data($cell)
                    case "quality_level"
                        return if($cell = "") then "Unknown" else map:get($app:data-quality-levels, data($cell))
                    default
                        return translate(data($cell)," ","&#160;")
                } </td>
};

(:~
 : Given curation data, check if data is public or not.
 : # TODO check that secure and () return false
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
                let $obs_release_date := try {
                        xs:dateTime($obs_release_date)
                    }catch *{
                        (: this case occured when RDBMS dates were retrieve as strings :)
                        dateTime(
                            xs:date(substring-before($obs_release_date, " ")),
                            xs:time(substring-after($obs_release_date, " ")))
                    }
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
 : data. The url is replace by get-data.html?id=$id if id parameter is provided else the original url is used.
 :
 : @param $id optional granule id
 : @param $url the URL to the OIFits file to hide behind get-data.html if an associated id is given
 : @param $data_rights availability of the dataset
 : @param $release_date the date at which data become public
 : @param $creator_name owner of the data
 : @return an <a> element
 :)
declare %private function app:format-access-url($id as xs:string?, $url as xs:string, $data_rights as xs:string?, $release_date as xs:string?, $creator_name as xs:string?, $datapi as xs:string?, $calib_level as xs:integer ?) {
    let $public := if ($data_rights and $release_date) then app:public-status($data_rights, $release_date) else true()
    let $c := if($creator_name) then <li>{$creator_name||" (data creator)"}</li> else ()
    let $d := if($datapi) then <li>{$datapi||" (data PI)"}</li> else ()
    let $contact := <span><b>Contact:</b><ul>{$c, $d}</ul></span>
    let $contact := serialize($contact)
    return
        element {"a"} {
        attribute { "href" } { if(exists($id)) then "get-data.html?id="||$id else $url },
        if ( not ( $calib_level < 1 ) and string-length($url)>3 and ( $public or $creator_name = '' )) then
            
            let $dfpu := datalink:datalink-first-png-url($id)
            let $img     := if(exists($dfpu)) then serialize(<img src="{$dfpu}" width="400%"/>) else ()
            return
            (
                attribute { "rel" }                 { "tooltip" },
(:                attribute { "data-placement"}       { "right" },:)
                attribute { "data-original-title" } { "&lt;div&gt;"||$contact||$img||"&lt;/div&gt;" },
                attribute { "data-html" } { "true" }
            )
          else
            (
                attribute { "rel" }                 { "tooltip" },
                attribute { "data-original-title" } { $contact },
                attribute { "data-html" } { "true" }
            ),
         tokenize($url, "/")[last()] ! xmldb:decode(.) ,
         if ($public) then () else <i class="glyphicon glyphicon-lock"/>
        }
};

(:~
 : Append scheme://host:port if given input starts with /, else return the same input.
 :
 : @param $url the input URL to prefix with actual server if
 : @return a full qualified url.
 :)
declare function app:fix-relative-url($url as xs:string) as xs:string {
    if(starts-with($url, "/"))
    then
        request:get-scheme()||"://"||request:get-server-name()||":"||request:get-server-port()||$url
    else
        $url
};

(:~
 : Format a cell for the obs_collection column.
 :
 : It builds an anchor element redirecting to the collection page. VizieR link is appent if relevant.
 :
 : @param $id the ID of the collection
 : @return an <a> element
 :)
declare function app:format-collection-url($id as xs:string) {
    let $collection := collection("/db/apps/oidb-data/collections")/collection[@id eq $id]/name/text()
    return (
        element { "a" } {
        attribute { "href" } { "collection.html?id=" || encode-for-uri($id) },
        if ($collection) then $collection else $id
            },
        if (starts-with($id, 'J/')) then
            (",&#160;",<a href="{ app:vizcat-url($id) }">VizieR&#160;<span class="glyphicon glyphicon-new-window"></span></a>)
        else ()
    )
};

(:~
 : Format a cell for the obs_collection column.
 :
 : It builds an anchor element redirecting to the collection page. VizieR link is appent if relevant.
 :
 : @param $node
 : @param $model the current model
 : @param $key the entry name in model with collection id
 : @return an <a> element
 :)
declare function app:format-collection-url($node as node(), $model as map(*), $key as xs:string) {
    let $id := helpers:get($model, $key)
    return app:format-collection-url($id)
};

(:~
 : Format a link to search data of given collection id.
 :
 : It builds an anchor element redirecting to the search page. VizieR link is appent if relevant.
 :
 : @param $node
 : @param $model the current model
 : @param $key the entry name in model with collection id
 : @return an <a> element
 :)
declare function app:format-search-collection-url($node as node(), $model as map(*), $key as xs:string) {
    let $id := helpers:get($model, $key)
    return app:format-search-collection-url($id)
};

(:~
 : Format a link to search data of given collection id.
 :
 : It builds an anchor element redirecting to the search page. VizieR link is appent if relevant.
 :
 : @param $id the ID of the collection
 : @return an <a> element
 :)
declare function app:format-search-collection-url($id as xs:string) {
    let $collection := collection("/db/apps/oidb-data/collections")/collection[@id eq $id]/name/text()
    return (
        element { "a" } {
        attribute { "href" } { "search.html?collection=~" || encode-for-uri($id) },
        if ($collection) then $collection else $id
            },
        if (starts-with($id, 'J/')) then
            (",&#160;",<a href="{ app:vizcat-url($id) }">VizieR&#160;<span class="glyphicon glyphicon-new-window"></span></a>)
        else ()
    )
};

(:~
 : Format a cell for a wavelength value.
 :
 : @param $wl the wavelength in meters
 : @return the same wavelength in micrometers
 :)
declare %private function app:format-wavelengths($wl) {
    <span title="{$wl} m">{ format-number(xs:double($wl) * 1e6, ".00000000")}</span>
};

(:~
 : Format a cell for a mjd value.
 :
 : @param $mjd the date in mjd
 : @return the date in a datetime format
 :)
declare %private function app:format-mjd($mjd as xs:double) {
    <span title="{$mjd} mjd">{substring(string(jmmc-dateutil:MJDtoISO8601($mjd)),0,20)}</span>
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
    let $data := tap:retrieve-or-execute($app:collections-query)
    let $ids := $data//*:TD/text()
    let $collections := collection("/db/apps/oidb-data/collections")/collection
    return map {
        'collections' : map:merge(
            for $id in $ids
            let $name := $collections[@id=$id]/name/text()
            return map:entry($id, $name)
        )
    }
};

(:~
 : Build a map of user writable collections and put it in the model for templating.
 :
 : It creates a 'user-collections' entry in the model for the children of the nodes.
 :
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with collections details
 :)
declare
    %templates:wrap
function app:user-collections-options($node as node(), $model as map(*), $calib_level as xs:integer?) as map(*) {
    let $data := tap:retrieve-or-execute($app:collections-query)
    let $ids := data($data//*:TD)
    let $collections := collection("/db/apps/oidb-data/collections")/collection
    return map {
        'user-collections' : map:merge(
            for $id in $ids[.=$collections/@id]
            return
                let $col := $collections[@id=$id]
                let $valid-level := if(exists($calib_level)) then if($calib_level>2) then exists($col//bibcode/text()) else empty($col//bibcode/text()) else true()
                let $name := $col/name/text() || " - " || $col/datapi/text()
                return if( $valid-level and collection:has-access($col, "w")  ) then map:entry($id, $name) else () (: TODO improve calib_level filtering :)
        )
    }
};

(:~
 : Build a map with data associated to the given collections .
 :
 : It creates a 'user-collections' entry in the model for the children of the nodes.
 :
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with collections details
 :)
declare
    %templates:wrap
function app:collection-form($node as node(), $model as map(*), $id as xs:string?, $calib_level as xs:integer?) as map(*) {
    let $map1 :=
    if(empty($id)) then $model else
        let $collection := collection($config:data-root)//collection[@id=$id]
        return if(empty($collection)) then $model else
        map {
        'id' : $id
        ,'ask_coltype' : $calib_level!=3
        , 'coltype'    : $collection/coltype/text()
        ,'name'        : $collection/name/text()
        ,'title'       : $collection/title/text()
        ,'description' : $collection/description/text()
        ,'keywords'    : ($collection//keyword/text())
        ,'bibcodes'    : ($collection//bibcode/text())
         }

    return map:merge(($map1, if($calib_level != 3) then map {'ask_coltype' : "yes" } else () ))
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
    let $data := tap:retrieve-or-execute($app:instruments-query)
    let $instruments := distinct-values(
        for $instrument-name in $data//*:TD/text()
        return tokenize($instrument-name, '[^A-Za-z0-9]')[1])
    let $instruments := for $e in $instruments order by $e return $e

    return map:merge(map:entry('instruments', $instruments))
};

(:~
 : Put instrument details into model for templating.
 :
 : It takes the instrument name from the model using given key or from a 'name' HTTP parameter in the request.
 :
 : @param $node
 : @param $model the current model
 : @return a submodel with instrument description
 :)
declare function app:instrument($node as node(), $model as map(*), $key as xs:string?) as map(*) {
    let $id := if($key) then map:get($model,$key) else request:get-parameter('name', '')

    let $focal-instrument := collection('/db/apps/oidb-data/instruments')//focalInstrument[starts-with(./*:name,$id)]
    let $facility := <facility>{string-join(($focal-instrument/ancestor::*:interferometerSetting/*:description/*:name), " / ")}</facility>
    let $url := <url>{ 'search.html?instrument=' || encode-for-uri($id) }</url>

    let $anchor := <anchor>#{$id}</anchor>

    let $instrument := <instrument>
        {if(count($focal-instrument)=1)
            then jmmc-xml:strip-ns($focal-instrument/*)
            else <name>{$id}</name>
        }
        {$facility, $url, $anchor}
        </instrument>
    return map { 'instrument' : $instrument, 'html-desc' : () (: TODO :) }
};


(:~
 : Add instrument stats to the model for templating.
 :
 : @param $node
 : @param $model the current model
 : @param $key the entry name in model with instrument id
 : @return a submodel with stats of the requested instrument
 :)
declare function app:instrument-stats($node as node(), $model as map(*), $key as xs:string) as map(*) {
    let $id := helpers:get($model, $key)
    return app:stats(( 'instrument=' || $id ))
};

(:~
 : Add general statistics to the model .
 :
 : @param $node
 : @param $model the current model
 : @return a submodel with stats
 :)
declare function app:statistics($node as node(), $model as map(*)) as map(*) {
    let $key:="granules-stats"
    let $cached := $tap:cache-get($key)

    let $ret :=
        if(exists($cached)) then
            $cached
        else
            let $vot       := tap:retrieve-or-execute(adql:build-query( 'caliblevel=1,2,3' ))
            let $granules := app:votable-rows-to-granules(data($vot//votable:FIELD/@name), $vot//votable:TABLEDATA/votable:TR)
            let $rows := $granules//granule
            let $statistics:=
            <dev>nb_granules for calib_level >=1 :{count($rows)}<br/>
            <table class="table table-striped table-bordered table-hover">
            <tr><th>nb</th><th>instrument_name</th><th>nb_vis(mean)</th><th>nb_vis2(mean)</th><th>nb_t3(mean)</th><th>min(em_res_power)</th><th>max(em_res_power)</th><th>res threshold</th><th>LR</th><th>MR/HR</th></tr>
            {
                for $granule in $rows group by $instrument_name := data($granule/instrument_name)
                let $nb := count($granule)
                let $nb_vis := sum($granule//nb_vis) div $nb
                let $nb_vis2 := sum($granule//nb_vis2) div $nb
                let $nb_t3 := sum($granule//nb_t3) div $nb
                let $em_res_power_min := min($granule//em_res_power)
                let $em_res_power_max := max($granule//em_res_power)
                return <tr><td>{$nb}</td><td>{$instrument_name}</td><td>{$nb_vis}</td><td>{$nb_vis2}</td><td>{$nb_t3}</td><td>{$em_res_power_min}</td><td>{$em_res_power_max}</td><td>TBD</td><td>#?</td><td>#?</td></tr>
            }
            </table>
            </dev>
                return $tap:cache-insert($key, $statistics)

    return map {  'statistics' : $ret }
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
    let $data := tap:retrieve-or-execute($app:facilities-query)
    let $tap-facilities := distinct-values($data//*:TD/text())

    let $aspro-table := <table class="table table-striped table-bordered table-hover">
    <tr><th>Name</th><th>Description</th><th>X,Y,Z coordinates</th><th>Lat,Lon approximation </th><th>records in the database</th></tr>
        {
            for $facility in collection($config:aspro-conf-root)/*:interferometerSetting
                let $name := data($facility/*:description/*:name)
                let $desc := data($facility/*:description/*:description)
                (: http://stackoverflow.com/questions/1185408/converting-from-longitude-latitude-to-cartesian-coordinates :)
                let $coords := data($facility/*:description/*:position/*)
                let $x := xs:double($coords[1])
                let $y := xs:double($coords[2])
                let $z := xs:double($coords[3])
                let $r := xs:double(6371000)
                let $lat := math:asin( $z div $r ) * 180 div math:pi()
                let $lon := math:atan2($y, $x) * 180 div math:pi()

                let $has-records := for $f in $tap-facilities return matches( $f, $name)
                let $has-records := if( true() = $has-records) then <i class="glyphicon glyphicon-ok"/> else ()

                where  not($name = ("DEMO", "Paranal", "Sutherland") )
                return
                    <tr>
                        <th><a href="search.html?facility={$name}">{$name}</a></th><td>{$desc}</td><td>{string-join($coords,",")}</td><td>{$lat},{$lon} </td><td>{$has-records}</td>
                    </tr>
        }
        {
            let $aspro-facilities := distinct-values(data(collection($config:aspro-conf-root)/*:interferometerSetting/*:description/*:name))
            for $facility in $tap-facilities
                where  not( $facility = $aspro-facilities )
                return
                    <tr>
                        <th><a href="search.html?facility={$facility}">{$facility}</a></th><td></td><td></td><td></td><td><i class="glyphicon glyphicon-ok"/></td>
                    </tr>
        }
        </table>

    return map { 'tap-facilities' : $tap-facilities , 'facilities' : $aspro-table }
};

declare variable $app:data-pis-query := adql:build-query(( 'col=datapi', 'distinct' ));
declare variable $app:obs-creator-names-query := adql:build-query(( 'col=obs_creator_name', 'distinct' ));

declare variable $app:data-pis-roles := <roles>
            <e><k>tech</k><icon>glyphicon glyphicon-wrench</icon><description>Service account</description></e>
            <e><k>instrument-pi</k><icon>glyphicon glyphicon-certificate</icon><description>Instrument PI</description></e>
            <e><k>unregistered</k><icon>glyphicon glyphicon-bell</icon><description>Unregistered user</description></e>
        </roles>;

(:~
 : Build a list of dataPI roles and put it in the model for templating.
 :
 : It creates a 'roles' entry in the model for the children of the node.
 :
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with one icon and description subelement per role
 :)
declare
    %templates:wrap
function app:data-pis-roles($node as node(), $model as map(*)) as map(*) {
    let $roles := $app:data-pis-roles//e
    return map:merge(($model, map:entry('roles', $roles)))
};

 (:~
 : Build a list of dataPIs and put it in the model for templating.
 :
 : It creates a 'datapis' entry in the model for the children of the node.
 : It also extract the people informations from the xml db in a 'persons' entry.
 :
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with dataPI names and persons fragments
 :)
declare
    %templates:wrap
function app:data-pis($node as node(), $model as map(*)) as map(*) {
    (: fill datapis with datapi and obs_creator_name entries :)
    let $data := tap:retrieve-or-execute($app:data-pis-query)
    let $datapis := $data//*:TD/text()
    let $data := tap:retrieve-or-execute($app:obs-creator-names-query)
    let $datapis := distinct-values(($datapis, $data//*:TD/text()))

    let $persons := for $p in doc($config:data-root||"/people/people.xml")//person[alias=$datapis]
        let $icons := $app:data-pis-roles//e[k=$p/flag]/icon
        order by normalize-space(upper-case($p/lastname))
        return
            element {name ($p)} { $p/@*, $icons, $p/*[name()!='alias'], $p/alias[.=$datapis], element {"id"} {data($p/alias[1])} , element {"email"} {data($p/alias[@email]/@email[1])}}

    let $missings := for $p in $datapis[not(.=$persons/alias)]
        let $e:=<person><missing/>{$app:data-pis-roles//e[k='unregistered']/icon}<firstname></firstname><lastname></lastname><alias>{$p}</alias></person>
(:        let $u := update insert $e into doc($config:data-root||"/people/people.xml")/people:)
        return
            $e

    return map:merge(($model, map:entry('datapis', $datapis), map:entry('persons', ($missings, $persons))))
};

(:~
 : Build a list of dataPIs and put it in the model for templating.
 :
 : It creates a 'datapis' entry in the model for the children of the node.
 : It also extract the people informations from the xml db in a 'persons' entry.
 :
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with dataPI names and persons fragments
 :)
declare
    %templates:wrap
function app:user-names-options($node as node(), $model as map(*)) as map(*) {
    let $user-names := for $p in doc($config:data-root||"/people/people.xml")//person[alias/text()]
        let $user-name := data($p/alias[text()][1])
        order by normalize-space(upper-case($user-name))
        return $user-name

    return map:merge(($model, map:entry('user-names', $user-names)))
};

(:~
 : Helper to build an URL for a given datapi on the search URL.
 :
 : @param $datapi-key model's key for data pi value
 : @param $node the current node
 : @param $model the current model
 : @return an URL to search page for the specified data-pi as string
 :)
declare function app:data-pi-search-url($node as node(), $model as map(*), $datapi-key as xs:string, $label-key as xs:string?) as node() {
    let $datapi := map:get($model, $datapi-key)
    let $label := if($label-key) then  data(map:get($model, $label-key)) else data($datapi)
    return
        <a href="search.html?datapi={$datapi}" alt="search for {$label}">{$label}</a>
};

declare
    %templates:wrap
function app:sort-by($node as node(), $model as map(*)) as map(*) {
    map:merge((
        map:entry('sortbys',
            map {
                (: column name       displayed text :)
                't_min'           : "Date",
                'target_name'     : "Target name",
                'instrument_name' : "Instrument"
            }),
        map:entry('sortbys-default-keys-order', ('t_min', 'instrument_name', 'target_name'))
    ))
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
            templates:process($node/node(), map:merge(($model, map:entry('band', $n))))
        }
};

(:~
 : Build a list of bands and put it in the model for templating.
 :
 : It creates a 'bands' entry in the model for the children of the node.
 :
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with band names
 :)
declare
	%templates:wrap
function app:bands($node as node(), $model as map(*)) as map(*) {
    map:merge(($model, map:entry('bands', jmmc-astro:band-names())))
};

(:~
 : Build a list of wavelength divisions and put it in the model for templating.
 :
 : It creates a 'wavelength-ranges' entry in the model for the children of the node.
 :
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with band names
 :)
declare function app:wavelength-divisions($node as node(), $model as map(*)) as map(*) {
    map:merge(($model, map:entry('wavelength-divisions', jmmc-astro:wavelength-division-names())))
};

declare variable $app:data-quality-levels := map {
                                0:"Unknown",
                                1:"Trash",
                                2:"To be reduced again",
                                3:"Quick look (risky to publish)",
                                4:"Science ready",
                                5:"Outstanding quality" };

(:~
 : Put a map for data quality levels in the model for templating.
 : Levels are 0 to 4 for respectivly,
 : Trash, To be reduced again, Quick look (risky to publish), Science ready, Outstanding quality
 :
 : @param $node the current node
 : @param $model the current model
 : @return a new map as model with quality levels
 :)
declare function app:data-quality-flags($node as node(), $model as map(*)) as map(*) {
    (: map:merge(($model, map:entry('data-quality-flags', $jmmc-astro:data-quality-flags))) :)
    map:merge(($model, map:entry('data-quality-flags', $app:data-quality-levels)))
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
    let $count := function($q) { tap:execute($q)//*:TD/text() }
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
    %templates:default("order", "t_min")
function app:search($node as node(), $model as map(*),
                    $page as xs:integer, $perpage as xs:integer, $order as xs:string?, $all as xs:string?) as map(*) {
    try {
        (: Search database, use request parameters :)
        (: clean up pagination stuff, recovered later from function parameters :)
        let $params := adql:clear-pagination(adql:split-query-string())

        return if (empty($params)) then map {}
        else
        (: append default order param if not present  :)    
        let $params := ($params,("order="||$order)[not($params[starts-with(., "order=")])] )

        let $paginated-query := adql:build-query((
                $params,
                (: force query pagination to limit number of rows returned :)
                'page=' || $page, 'perpage=' || $perpage))
        let $votable := tap:execute( $paginated-query )
        let $overflow := tap:overflowed($votable)
        let $data := app:transform-votable($votable)

        (: default columns to display :)
        let $column-names := if($all) then
                $data//th/@name/string()
            else
                $app:main-metadata

        let $stats   := app:data-stats($params)

        (: select columns, keep order :)
        let $columns :=
            for $name in $column-names
            let $th := $data//th[@name=$name]
            let $unit := if($th/@unit) then " [" || $th/@unit || "]" else ()
            return map {
                'name'    : $name,
(:                'ucd'     : $th/a/text(),:)
(:                'ucd-url' : data($th/a/@href),:)
                'description' : data($th/@description) || $unit,
                'label'   : switch ($name)
                    case "em_min" return "wlen_min"
                    case "em_max" return "wlen_max"
                    default return $name
            }

        (: pick rows from transformed votable - skip row of headers :)
        let $rows    := $data//tr[position()!=1]

        (: the query shown to the user :)
        let $query := adql:build-query($params)

        (: add log request :)
        let $log := log:search(<success/>)
        return map {
            'query' :      $query,
            'query-edit' : 'query.html?query=' || encode-for-uri($query),
            'columns' :    $columns,
            'rows' :       $rows,
            'overflow' :   if ($overflow) then true() else (),
            'stats' :      $stats,
            'pagination' : map { 'page' : $page, 'npages' : ceiling(number($stats/@nobservations) div $perpage) }
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
    map:merge((
        (: --- FILTERS --- :)
        (: target=[!][~]<data> :)
        map {
            'target_name' : substring-after(request:get-parameter('target', ''), '~')
        },
        (: conesearch=<position>,<equinox>,<radius>,<unit> :)
        let $tokens := tokenize(request:get-parameter('conesearch', ''), ',')
        return if(count($tokens) = 4) then
            map {
                'cs_position'    : $tokens[1],
                'cs_equinox'     : $tokens[2],
                'cs_radius'      : $tokens[3],
                'cs_radius_unit' : $tokens[4]
            }
        else
        (
            (: observationdate=[<start>]..[<end>] :)
            map {
                'date_start'  : substring-before(request:get-parameter('observationdate', ''), '..'),
                'date_end'    : substring-after(request:get-parameter('observationdate', ''), '..')
            },
            (: instrument=[!]<data> :)
            map {
                'instrument'  : request:get-parameter('instrument', '')
            },
            (: wavelengthband=<band>[,<band>]* :)
            map {
                'band'        : tokenize(request:get-parameter('wavelengthband', ''), ',')
            },
            (: collection=[!][~]<data> :)
            map {
                'collection'  : substring-after(request:get-parameter('collection', ''), '~')
            },
            (: datapi=[!][~]<data> :)
            map {
                'datapi'      : substring-after(request:get-parameter('datapi', ''), '~')
            },
            (: caliblevel=<level>[,<level>]* :)
            map {
                'reduction'   : tokenize(request:get-parameter('caliblevel', ''), ',')
            },
            (: public=yes|no|all :)
            map {
                'available'   : request:get-parameter('public', 'all')
            },
            (: --- ORDERING --- :)
            let $order := request:get-parameter('order', '')[1]
            let $desc := starts-with($order, '^')
            return map {
                'sortby'     : if($desc) then substring($order, 2) else $order,
                'descending' : if($desc) then () else 'yes'
            },
            (: --- PAGINATION --- :)
            map {
                'perpage'    : request:get-parameter('perpage', '25')
            }
        )
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
 : Put datalink elements for a given id into model for templating.
 : Not yet used by show because of non templated app:show
 : It takes the granule ID from a 'id' HTTP parameter in the request.
 :
 : @param $node
 : @param $model the current model
 : @return a submodel with datalink elements i.e a transformed votable
 :)
declare function app:datalink($node as node(), $model as map(*)) as map(*) {
    let $id := request:get-parameter('id', '')
    (: which elements has the model inside ? :)
    (: we could get the id but the collection, target ... :)
    let $datalink:= datalink:datalink($id)
    (: TO BE CONTINUED ... :)
    return if ($datalink)
        then
            map { 'datalink' : $datalink }
        else
            ()
};


(:~
 : Display all columns from the selected row.
 :
 : A query with the identifier for the row is passed to the TAP service and the
 : returned VOTable is formatted as an HTML table.
 : TODO refactor using templating and td-cells()
 :
 : @param $node
 : @param $model
 : @param $id the row identifier
 : @return a <table> filled with data from the raw row
 :)
declare function app:show($node as node(), $model as map(*), $id as xs:integer) {
    let $query := "SELECT * FROM " || $config:sql-table || " AS t WHERE t.id='" || $id || "'"
    (: send query by TAP :)
    let $votable := tap:execute($query)
    let $data := app:transform-votable($votable, 1, count($votable//votable:TR),"&#160;") (: leave header on a single line :)
    let $nb-granules := count($data//tr[td])

    return if ($nb-granules=0) then
            <div class="alert alert-warning fade in">
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>
                <strong>No granule found with id={$id}</strong>
            </div>
        else
            <div>
                <h1> Granule {$data//td[@colname='id']/text()}</h1>
                {()(: app:show-granule-summary($node,  map {'granule' : app:granules($query) }, "granule") :)}
                <div class="row">
                    <div class="col-md-6">
                    {app:show-granule-summary($node,  map {'granule' : $data }, "granule")}
                    {if ($data//td[@colname='calib_level'] = '0' ) then () else app:show-granule-siblings($node,  map {'granule' : $data }, "granule")}
                    </div>
                    <div class="col-md-6 acol-md-offset-1">
                    {app:show-granule-contact($node,  map {'granule' : $data }, "granule")}
                    {app:show-granule-externals($node,  map {'granule' : $data }, "granule")}
                    </div>
                </div>

                <h2><i class="glyphicon glyphicon-align-justify"/> Table of metadata for granule {$data//td[@colname='id']/text()}</h2>

                <table class="table table-striped table-bordered table-hover table-condensed">
                <!-- <caption> Details for { $id } </caption> -->
                {
                    for $th at $i in $data//th[@name!='id']
                    let $td := $data//td[position()=index-of($data//th, $th)]
                    let $tr := $td/..
                    let $tt := data($th/@description)
                    let $tt := if($th/@unit) then $tt || " co[" || $th/@unit || "]" else $tt
                    return <tr> <th> <i class="glyphicon glyphicon-question-sign" rel="tooltip" data-original-title="{$tt}"/> &#160; { $th/node() } </th> {app:td-cell($td, $tr) } </tr>
                }
                </table>
            </div>
};

(:~
 : Display the summary information for a given granule.
 :
 : @param $node
 : @param $model
 : @return a <table> filled with data from the raw row
 :)
declare function app:show-granule-summary($node as node(), $model as map(*), $key as xs:string)
{
    let $granule := map:get($model, $key)

    return <div id="summary">
                <h2><i class="glyphicon glyphicon-zoom-in"/> Summary</h2>
                <table class="table table-striped table-bordered table-hover">
                {
                    let $row := ($granule//tr[td], $granule)[1] (: use tr if votable is provided else the given node is supposed to be a tr :)
                    let $columns := ($app:main-metadata , "obs_creator_name", "quality_level", "obs_collection")
                    return app:tr-cells($row, $columns)
                }
                </table>
            </div>
};


(:~
 : Display the summary information for a given granule.
 :
 : @param $node
 : @param $model
 : @return a <table> filled with data from the raw row
 :)
declare function app:show-granule-siblings($node as node(), $model as map(*), $key as xs:string)
{
    let $granule := map:get($model, $key)


    let $query := "SELECT id FROM " || $config:sql-table || " AS t WHERE t.access_url='" || $granule//td[@colname='access_url'] || "'"
    (: send query by TAP :)
    let $votable := tap:execute($query)
    let $data := app:transform-votable($votable, 1, count($votable//votable:TR),"&#160;")
    let $nb-granules := count($data//tr[td])
    where $nb-granules >= 2
    return
        <div id="external_resources">
            <h2>Granules in the same OIFITS</h2>
            <table class="table table-striped table-bordered table-hover">
                {
                    for $row in $data//tr[td] return
                    <tr>{app:td-cell($row//td, $row)}</tr>
                }
            </table>
        </div>

};


(:~
 : Provide a javascript encoded array to fill an html attribute that can display an email after client side decoding.
 : TODO move into jmmc-auth
 :)
declare function app:get-encoded-email-array($email as xs:string) as xs:string
{
  let $pre := substring-before($email,"@")
  let $pre := translate($pre, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", "NOPQRSTUVWXYZABCDEFGHIJKLMnopqrstuvwxyzabcdefghijklm")

  let $post := substring-after($email,"@")
  let $post := translate($post, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", "NOPQRSTUVWXYZABCDEFGHIJKLMnopqrstuvwxyzabcdefghijklm")
  let $post := tokenize( $post , "\.")
  let $post := reverse( $post )
  let $mailto := translate("mailto:", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", "NOPQRSTUVWXYZABCDEFGHIJKLMnopqrstuvwxyzabcdefghijklm")
  let $mailto := $mailto ! string-to-codepoints(.) ! codepoints-to-string(.)

  return "[[&apos;"||string-join($mailto, "&apos;, &apos;")||"&apos;],[&apos;"||$pre||"&apos;],[&apos;"||string-join($post, "&apos;, &apos;")|| "&apos;]]"
};

(:~
 : Provide a javascript decoder code.
 : TODO move into jmmc-auth
 :)
declare function app:get-encoded-email-decoder() as xs:string {
    <script>
    <![CDATA[
    // connect the contact links
    $('a[data-contarr]').on('click', function (e){
        var array = eval($(this).data('contarr'))
        var str = array[0].join('')+array[1]+'@'+array[2].reverse().join('.');
        location.href=str.rot13();
        return false;
    });
    ]]>
    </script>

};


(:~
 : Clear cached data. MUST BE called after TAP datasource update.
 :)
declare function app:clear-cache(){
  tap:clear-cache()
};


(:~
 : Display the contact information for a given granule.
 :
 : @param $node
 : @param $model
 : @return a <table> filled with data from the raw row
 :)
declare function app:show-granule-contact($node as node(), $model as map(*), $key as xs:string)
{
    let $granule := map:get($model, $key)

    return
        <div id="contact">
            <h2><i class="glyphicon glyphicon-envelope"/> Contact</h2>
            {
                let $row := ($granule//tr[td], $granule)[1] (: use tr if votable is provided else the given node as supposed to be a tr :)

                let $datapi := $row//td[@colname="datapi"]

                let $obs_creator_name := data($row//td[@colname="obs_creator_name"])
                let $obs_creator_name-email := user:get-email($obs_creator_name)
                let $obs_creator_name-link := if($obs_creator_name-email) then
                                let $js :=  app:get-encoded-email-array($obs_creator_name-email)
                                    return <a href="#" data-contarr="{$js}">{$obs_creator_name}&#160;<i class="glyphicon glyphicon-envelope"/></a>
                                else $obs_creator_name

                return
                    if($obs_creator_name=$datapi) then
                        <address>
                            <strong>Data PI / OBS creator</strong><br/>
                            {$obs_creator_name-link}
                        </address>
                    else
                        let $datapi-email := user:get-email($datapi)
                        let $datapi-link := if($datapi-email) then
                                let $js :=  app:get-encoded-email-array($datapi-email)
                                    return <a href="#" data-contarr="{$js}">{$datapi}&#160;<i class="glyphicon glyphicon-envelope"/></a>
                                else <span>Sorry, no contact information have been found into the OiDB user list for <em>{data($datapi)}</em><br/>
                                If you are the associated datapi and get an account, please <a href="feedback.html"> contact the webmasters </a> to fix missing links. If you have no account, please <a href="https://apps.jmmc.fr/account/#register" target="_blank" class="btn btn-default active" role="button">Register</a> before. <br/> In the meantime every user may contact the creator of the resource just below.</span>
                        return
                        <address>
                            <strong>Data PI</strong><br/>
                            {$datapi-link}<br/>
                            <strong>OBS creator</strong><br/>
                            {$obs_creator_name-link}
                        </address>
            }
        </div>
};

(:~
 : Display the external links for a given granule.
 :
 : TODO implement logic to retrieve some external link from the fields of a given granule
 :      VLTI should not be hardcoded here!!
 :
 : @param $node
 : @param $model
 : @return a <table> filled with data from the raw row
 :)
declare function app:show-granule-externals($node as node(), $model as map(*), $key as xs:string)
{
    let $granule := map:get($model, $key)
    let $granule_id := xs:integer($granule//td[@colname='id'])
    let $facility-name := string($granule//td[@colname='facility_name'])

    let $prog_id := string($granule//td[@colname='progid'])
    (: add a fallback using obs_id to retrieve PIONIER collection's granules :)
    (: would be good to change the db content, isn't it ? :)
    let $prog_id := if ($prog_id!='') then $prog_id else string($granule//td[@colname='obs_id'])

    let $data_rights := $granule//td[@colname='data_rights']
    let $release_date := $granule//td[@colname='obs_release_date']

    let $public := if ($data_rights and $release_date) then app:public-status($data_rights, $release_date) else true()

    let $ext-res := if($facility-name="VLTI" and $prog_id!='') then
        let $url := $jmmc-eso:eos-url||"?progid="||encode-for-uri($prog_id)
        return
            <a href="{$url}">Jump to ESO archive for progid <em>{$prog_id}</em></a>
        else
            ()

    let $datalink-res :=
        let $datalink-vot := app:transform-votable( datalink:datalink($granule_id) )
        let $content_length_unit := data($datalink-vot//th[@name='content_length']/@unit)
        let $content_length_desc := data($datalink-vot//th[@name='content_length']/@description)
        return
            for $tr in $datalink-vot//tr[td]
            let $url                 := data($tr/td[@colname='access_url'])
            let $filename            := tokenize($url, '/')[last()]
            let $description         := data($tr/td[@colname='description'])
            let $description         := if($description) then $description else $url
            let $content_length      := data($tr/td[@colname='content_length'])
            let $content_type      := data($tr/td[@colname='content_type'])
            let $title := if($content_length) then $content_length_desc||": ["||$content_length||"] "||$content_length_unit else ()
            let $title := $filename || ":" || $title
            (: hide thunbnail if private ( could be shown to datapi ? ) :)
            let $thumbnail := if ($public) then
                if(contains($content_type, 'png')) then <a href="{$url}" title="{$title} "><img src="{$url}" width="60%"/></a> else ()
                else <i class="glyphicon glyphicon-lock"/>
            return
                <tr><th><a href="{$url}" title="{$title} ">{$description}</a>{$thumbnail}</th></tr>

    return
        (if(empty($datalink-res)) then () else
            <div id="quicklook_plots">
                <h2><i class="glyphicon glyphicon-eye-open"/> Quicklook plots </h2>
                <table class="table table-striped table-bordered table-hover">
                    { $datalink-res }
                </table>
            </div>,
        if (empty($ext-res)) then () else
        <div id="external_resources">
            <h2><i class="glyphicon glyphicon-new-window"/> External resources</h2>
            <table class="table table-striped table-bordered table-hover">
                { for $e in $ext-res return <tr><th>{$e}</th></tr> }
            </table>
        </div>
        )

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
    let $data := tap:execute($query)
    let $data-url := $data//*:TD/text()

    let $activate-303 := if ($data-url) then
        (response:set-header("Location", $data-url),
        response:set-status-code(303))
        else ()

    let $do-log := log:get-data( $id, $data-url )


    return  map { 'data-url' : if($data-url) then $data-url else (),
                      'flash'    : if($data-url) then () else "can't find associated data, please check your granule id (given is '" || $id || "')" }
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
    let $data := tap:retrieve-or-execute($app:latest-query)

    let $fields := data($data//votable:FIELD/@name)
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
    let $count := function($q) { tap:retrieve-or-execute('SELECT COUNT(*) FROM (' || adql:build-query($q) || ') AS e')//*:TD/text() }
    let $data := tap:retrieve-or-execute($app:data-pis-query)
    let $datapis := $data//*:TD/text()
    let $peoples := doc($config:data-root||"/people/people.xml")
    let $persons := $peoples//person[alias=$datapis]
    let $missings := $datapis[not(. = $peoples//alias)]
    return map {
        'n_facilities'  : $count(( 'distinct', 'col=facility_name' )),
        'n_instruments' : count(app:instruments($node,$model)('instruments')),
        'n_data_pis'    : count($persons) + count($missings),
        'n_collections' : $count(( 'distinct', 'col=obs_collection' )),
        'n_oifits'      : $count(( 'distinct', 'col=access_url', 'caliblevel=1,2,3' )) - 1,
        'n_granules'    : $count(( 'caliblevel=1,2,3' )),
        'n_obs_logs'    : $count(( 'caliblevel=0' ))
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
declare function app:collections($node as node(), $model as map(*), $type as xs:string*) as map(*) {
    let $collections :=
        for $collection in collection("/db/apps/oidb-data/collections")/collection
        (: open up collection and add link to full description page :)
        let $coltype := collection:get-type($collection)
        where empty($type) or $coltype = $type
        return <collection> {
            $collection/@*,
            $collection/node(),
            <url>{ 'collection.html?id=' || encode-for-uri($collection/@id) }</url>,
            if($collection/coltype) then () else <coltype>{$coltype}</coltype>,
            <coltypeurl>{ '?type=' || $coltype }</coltypeurl>
        } </collection>
    let $types := for $collection in collection("/db/apps/oidb-data/collections")/collection
                        return collection:get-type($collection)
    let $vizier-collections := $collections[collection:vizier-collection(.)]
    return map {
        'type' : $type,
        'types' : distinct-values($types),
        'vizier-collections' : $vizier-collections,
        'other-collections'  : $collections[not(.=$vizier-collections)]
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
    let $id := replace(request:get-parameter('id', '')," ","+") (: We have no space in our ids and received spaces probably comes from a CDS catalog ref with + sign... :)
    let $collection := collection("/db/apps/oidb-data/collections")/collection[@id eq $id]
    let $coltype := collection:get-type($collection)
    let $embargo := collection:get-embargo($collection)
    return if ($collection)
        then
            map { 'collection' : $collection, 'document-name' :  util:document-name($collection)
             , "embargo" : $embargo, "coltype" : $coltype}
        else
            ()
};

(:~
 : Count the number of OIFITS files and granules matching a given query. Provide the first and last observing date of records matching a given query.
 :
 : @param $query the query parameters
 : @return a map with counts of OIFITS, granules ( resp. n_oifits, n_granules) and from-date and to-date
 :)
declare %private function app:stats($query as item()*) as map(*) {
    let $count := function($q) { number(tap:retrieve-or-execute('SELECT COUNT(*) FROM (' || adql:build-query(( $q, $query )) || ') AS e')//*:TD) }
    let $instruments := tap:retrieve-or-execute('SELECT DISTINCT(e.instrument_name) FROM (' || adql:build-query( $query ) || ') AS e')//*:TD/text()
    let $tmin-tmax := tap:retrieve-or-execute('SELECT MIN(e.t_min), MAX(e.t_max) FROM (' || adql:build-query( $query ) || ') AS e')//*:TD/text()
    let $tmin-tmax := for $mjd in $tmin-tmax return jmmc-dateutil:MJDtoISO8601($mjd)

    let $n_granules := $count(( 'caliblevel=1,2,3' ))
    let $n_oifits := if($n_granules = 0 ) then 0 else $count(( 'distinct', 'col=access_url' ))
    return map {
        'n_oifits'   : $n_oifits,
        'n_granules' : $n_granules,
        'n_obs_logs' : $count(( 'caliblevel=0' )),
        'instruments' : $instruments,
        'from-date'  :$tmin-tmax[1],
        'to-date'    :$tmin-tmax[2]
    }
};

declare function app:date-multiline($node as node(), $model as map(*), $key as xs:string) as node()*{
    let $date := xs:date(map:get($model, $key))
    let $y := year-from-date($date)
    let $m := ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')[month-from-dateTime($date)]
    let $d := day-from-dateTime($date)

    return
    <div class="btn-group-vertical btn-group-xs" role="group">
        <button type="button" class="btn btn-warning">{$y}</button>
        <button type="button" class="btn btn-default">{$m}<br/>{$d}</button>
    </div>
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
 : Transform a VOTable into an intermediate format for templating.
 :
 : It turns the VOTable field descriptions into <th/> elements with name and
 : UCD. And it adds the respective field names as attributes to each cell.
 :
 : @param $votable a VOTable
 : @return a <votable/> element
 :)
declare function app:transform-votable($votable as node()) as node() {
    app:transform-votable($votable, 1)
};

(:~
 : Transform a VOTable into an intermediate format for templating.
 :
 : It turns the VOTable field descriptions into <th/> elements with name and
 : UCD. And it adds the respective field names as attributes to each cell.
 :
 : It transforms the rows starting at the given index and discards any
 : preceding rows.
 :
 : @param $votable a VOTable
 : @param $start   the starting row position
 : @return a <votable/> element
 :)
declare function app:transform-votable($votable as node(), $start as xs:double) as node() {
    app:transform-votable($votable, $start, count($votable//votable:TR), ())
};

(:~
 : Transform a VOTable into an intermediate format for templating.
 :
 : It turns the VOTable field descriptions into <th/> elements with name and
 : UCD. And it adds the respective field names as attributes to each cell.
 :
 : It transforms a given number of rows starting at the given index and
 : discards any other row.
 :
 : @param $votable a VOTable
 : @param $start   the starting row position
 : @param $length  the number of rows to transform
 : @param $ucd-separator separator between field name and ucd link. ucd is not displayed if ucd-separator is empty
 : @return a <votable/> element
 :)
declare function app:transform-votable($votable as node(), $start as xs:double, $length as xs:double, $ucd-separator ) {
    let $headers := $votable//votable:FIELD

    return <votable> <tr> {
        for $field in $headers
        return <th>
            { $field/@name }
            { attribute {"description"} {data($field/votable:DESCRIPTION)} }
            { $field/@unit }
            { data($field/@name) }
            { if($field/@ucd and exists($ucd-separator))  then ($ucd-separator, <a href="{ concat($app:UCD_URL,data($field/@ucd)) }"> { data($field/@ucd) } </a>) else () }
            <!-- { if($field/@unit) then ( <br/>, <span> [ { data($field/@unit) } ] </span> ) else () } -->
        </th>
        } </tr> {
        for $row in $votable//votable:TABLEDATA/votable:TR[position() >= $start and position() < $start + $length]
        return <tr> {
            fn:for-each-pair(
                $headers, $row/votable:TD,
                function ($header, $cell) {
                (: compare value against the null for the column :)
                let $value := if ($cell = $header/votable:VALUES/@null) then '' else $cell/text()
                return element { 'td' } {
                    $cell/@*,
                    attribute { "colname" } { data($header/@name) },
                    $value }
            } )
        } </tr>
    } </votable>
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
 : Convert rows of a granules from a VOTable to XML granules.
 :
 : @param $fields the VOTable column names
 : @param $rows    the VOTable rows
 : @return the XML granules
 :)
declare %private function app:votable-rows-to-granules($fields as xs:string*, $rows as element(votable:TR)*) as element(granules){
    <granules>{for $row in $rows
    return <granule> {
        (: turn each cell into child element whose name is the respective column name :)
        for $td at $i in $row/votable:TD
        return element { $fields[$i] } { $td/text() }
    } </granule>
    }</granules>
};

(:~
 : Return for templating the granules matching a query grouped by source.
 :
 : If the TAP service reports an overflow (number of results to query exceeds
 : row limit) the returned sequence is terminated by an overflow element.
 :
 : @param $query the description of the ADQL query
 : @return a sequence of granule grouped by source
 :)
declare function app:granules($query as item()*) as node()* {
    (: search for granules matching query :)
    let $votable := tap:execute(adql:build-query($query))

    (: transform the VOTable :)
    let $data := app:transform-votable($votable, 1, count($votable//votable:TR),"&#160;") (: leave header on a single line :)

    return (
        (: group by source file (access_url) :)
        for $rows in $data//tr[td] group by $url := $rows/td[@colname='access_url']
        return <file>
            <url>{ $url }</url>
            <url-link>{app:td-cell($rows[1]//td[@colname='access_url'], $rows[1])/a }</url-link>
            {
            for $tr in $rows
                return
                    <granule> {
                    (: turn each cell into child element whose name is the respective column name :)
                    for $td in $tr/td

                      return element { data($td/@colname) } { data($td) }
                    }
                  </granule>
            }
        </file>,
        (: potentially report result overflow :)
        if (tap:overflowed($votable)) then <overflow/> else ()
    )
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
    let $id := replace(request:get-parameter('id', '')," ","+") (: We have no space in our ids and received spaces probably comes from a CDS catalog ref with + sign... :)
    let $query := ( 'collection=' || $id, 'order=^access_url' )
    let $stats := app:stats($query)
    let $granules := app:granules(( $query, 'page=' || $page, 'perpage=' || $perpage ))

    return map {
        'granules' : $granules[name()='file'],
        (: check if too many results for query :)
        'overflow' : $granules[name()='overflow'],
        'pagination' : map { 'page' : $page, 'npages' : ceiling($stats('n_granules') div $perpage) }
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
            templates:process($node/node(), map:merge(($model, map:entry($to, $granule))))
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
    return map { 'user' : jmmc-auth:get-info($user) }
};

(:~
 : Add the user name to the model for templating associated to 'datapi' key.
 :
 : @param $node  the current node
 : @param $modem the current model
 : @return a new model with datapi entry
 :)
declare function app:get-datapi($node as node(), $model as map(*)) as map(*) {
    map {'datapi' : login:user-name() }
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
 : provide an ads link for given bibcode.
 : TODO: move to templates-helpers
 :
 : @param $node the placeholder for the ellipsized text
 : @param $model
 : @param $key the key to lookup in the model for source text
 : @param $length the maximum size of text returned
 : @return a ellipsized text if too long
 :)
declare
    %templates:wrap
function app:ads-link($node as node(), $model as map(*), $key as xs:string) as node() {
    let $bibcode := helpers:get($model, $key)
    return jmmc-ads:get-link($bibcode, ())
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
(:        attribute { "rel" }                 { "tooltip" },:)
(:        attribute { "data-original-title" } { $column('description') },:)
(:        attribute { "data-html" } { "false" },:)
        attribute { "title" } { $column('description') },

        templates:process($node/node(), $model),
        if ($same-key) then <span class="caret"/> else ()
    }
};

declare variable $app:base-upload := $config:data-root || '/oifits/staging';

(:~
 : Add upload data to model for templating.
 : calib_description entry is not present if calib_level is not valid for upload
 : @param $node
 : @param $model
 : @param $calib_level the calibration level of the data to be uploaded
 : @return a new model for templating upload page
 :)
declare
    %templates:wrap
function app:upload($node as node(), $model as map(*), $staging as xs:string?, $calib_level as xs:integer?) as map(*) {
    (: TODO check 0 < calib_level < 3 or calib_level = ( 2, 3 ) :)
    let $staging := if ($staging) then $staging else util:uuid()
    (: a short textual description of the calibration level :)
    let $map := map {
        'oifits': (),
        'staging' : $staging,
        'calib_level' : $calib_level
    }
    let $map := if($calib_level = 3) then map:merge(($map, map:entry('skip-quality-level-selector', true()))) else $map
    let $map := map:merge(($map, app:upload-check-calib-level($node, $model, $calib_level)))
    return $map
};

(:~
 : Test if calib_level param is valid and set calib_description entry to the model for templating, else leave empty map.
 :
 : @param $node  the current node
 : @param $modem the current model
 : @param $calib_level the calibration level of the data to be uploaded
 : @return a new model with calib_description entry if calib_level is valid for upload
 :)
declare function app:upload-check-calib-level($node as node(), $model as map(*), $calib_level as xs:integer?) as map(*) {
    let $calib_description :=
        if ($calib_level = 2) then'calibrated'
        else if ($calib_level = 3) then 'published'
        else ''
    return
        if($calib_level = (2,3)) then
            map{'calib_description' : $calib_description }
        else
            map{}
};

(:~
 : Make an entry in the log of visits for the current page.
 :
 : @param $node
 : @param $model
 : @return empty
 :)
declare function app:log($node as node(), $model as map(*)){
    log:visit()
};

(:~
 : Add a categorized random image as background to the node.
 :
 : @param $node     the current node to templatize
 : @param $model    the current model
 : @param $category the category from which to pick the vignette
 : @return a templatized node with vignette as background
 :)
declare function app:random-vignette($node as node(), $model as map(*), $category as xs:string) as node() {
    let $path := 'resources/images/vignettes/' || $category || '/'

    (: build sequence of vignettes for this category :)
    let $filenames :=
        for $filename in xmldb:get-child-resources($config:app-root || '/' || $path)
        let $extension := lower-case(tokenize($filename, "\.")[last()])
        where $extension = ( 'png', 'jpg', 'tiff', 'gif' )
        return $filename
    (: pick one at random :)
    let $idx := 1+util:random(count($filenames))
    let $filename := $filenames[position()=$idx]

    (: prepare a CSS property with the image as background :)
    let $background := "background: url('" || $path || $filename || "') no-repeat center center; "

    return element { node-name($node) } {
        $node/@* except $node/@style,
        attribute { 'style' } { $background || data($node/@style) },
        templates:process($node/node(), $model)
    }
};

declare function app:rssItems($max as xs:integer) as node()* {
    let $latest-granules := adql:build-query(( 'order=subdate','order=^id', 'limit='||$max ))
    let $votable         := tap:retrieve-or-execute($latest-granules)
    let $data            := app:transform-votable($votable)

    let $granule-items :=
        for $rows in $data//tr[td]
            group by $url:=$rows/td[@colname="access_url"]
            order by ($rows/td[@colname="subdate"])[1] descending

            return
            let $first-row := ($rows)[1]
            let $date := xs:dateTime($first-row/td[@colname="subdate"])
            let $first-id := $first-row/td[@colname="id"]
            let $summary :=
                <table border="1" class="table table-striped table-bordered table-hover">
                    {
                        let $columns := ("id", $app:main-metadata ,"obs_collection", "obs_creator_name", "quality_level")
                        return app:tr-cells($rows, $columns)
                    }
                </table>
            let $c := count($rows)
            let $authors := distinct-values($rows//td[@colname="datapi"])
(:            app:show-granule-summary(<a/>,  map {'granule' : $rows }, "granule"):)
            return
                <item xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <link>{app:fix-relative-url("/show.html?id="||$first-id)}</link>
                    <title> {$c} last submitted granules</title>
                    <dc:creator>{$authors}</dc:creator>
                    <description>
                        {
                            serialize(
                                (
                                    <h2>Description:</h2>
                                    , <br/>
                                    , $summary
                                )
                            )
                        }
                    </description>
                    <pubDate>{jmmc-dateutil:ISO8601toRFC822($date)}</pubDate>
                </item>

    let $last-comments := comments:last-comments($max)
    let $comment-items := for $c in $last-comments
        let $granule-id := $c/@granule-id
        let $date   := $c/date
        let $text   := data($c/text)
        let $author := data($c/author)

        return
                <item xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <link>{app:fix-relative-url("/show.html?id="||$granule-id)}</link>
                    <title> granule comment </title>
                    <dc:creator>{$author}</dc:creator>
                    <description>
                        {   (: content could remember the thread ... :)
                            serialize( <div><b>From {$author}</b> on {$date}:<br/> <em>{$text}</em></div> )
                        }
                    </description>
                    <pubDate>{$date}</pubDate>
                </item>


    return for $item in ($granule-items, $comment-items) order by $item/pubDate descending return $item
};
