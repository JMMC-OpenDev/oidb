xquery version "3.1";

module namespace stats="http://apps.jmmc.fr/exist/apps/oidb/stats";

import module namespace templates="http://exist-db.org/xquery/html-templating";

import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";

import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";


import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace comments="http://apps.jmmc.fr/exist/apps/oidb/comments" at "comments.xql";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";

declare namespace sql="http://exist-db.org/xquery/sql";


(:~
 : Show general statistics .
 :
 : @param $node
 : @param $model the current model
 : @return stats infos
 :)
 declare
    %templates:wrap
function stats:show($node as node(), $model as map(*)) {
    let $collections := collection:list()
    let $id2colname := map:merge((
        for $c in $collections return map:entry(data($c/@id),data($c/name) )
        ))

    let $res := sql-utils:execute("SELECT DATE_PART('Year', subdate) as subdate_year, obs_collection, instrument_name FROM oidb WHERE calib_level > 0 group by DATE_PART('Year', subdate), obs_collection, instrument_name ORDER by subdate_year DESC;", false())
    let $rows := $res//sql:row
    let $by-instr := map:merge((
        for $row in reverse($rows)
        group by $year := data($row/sql:field[@name="subdate_year"])
        where $year = 2023
        return
            map:entry($year,map:merge(( 
                for $row2 in $row group by $instr := $row2/sql:field[@name="instrument_name"]
                return
                    map:entry(translate($instr,".-","__"), count($row2))
            )))
        ))

    let $log := util:log("info", $by-instr)
    let $res := sql-utils:execute("SELECT DATE_PART('Year', subdate) as subdate_year ,calib_level, obs_collection, count(*) FROM oidb WHERE calib_level > 0 group by DATE_PART('Year', subdate), calib_level,obs_collection ORDER by subdate_year DESC;", false())
    let $rows := $res//sql:row
    
    let $colid-pos := index-of(data($rows[1]/sql:field/@name), "obs_collection")
    let $trs := for $row in $rows 
        let $c := collection:get(""||$row/sql:field[@name="obs_collection"])
        return <tr>{for $field at $pos in $row/sql:field return <td>{if ($pos=$colid-pos ) then <a href="search.html?collection={$field}">{$id2colname(data($field))}</a> else data($field)}</td>}<td>{data($c/datapi)}</td><td>{collection:get-type($c)}</td> </tr>
    let $table :=
    <table class="table table-striped table-bordered table-hover table-condensed datatable">
            <thead><tr>{for $field in $rows[1]/sql:field return <th>{data($field/@name)}</th>}<th>obsCreator/dataPI</th><th>Type</th></tr></thead>
        {$trs}
    </table> 

    let $by-year := map:merge((
        for $row in reverse($rows)
        group by $year := data($row/sql:field[@name="subdate_year"])
        return
            map:entry($year,map:merge(( 
                for $row2 in $row group by $calib_level := $row2/sql:field[@name="calib_level"]
                return
                    map:entry($calib_level, count($row2))
            )))
        ))
    
    let $by-type := map:merge((
        for $row in reverse($rows)
        group by $year := data($row/sql:field[@name="subdate_year"])
        return
            map:entry($year,map:merge(( 
                for $row2 in $row group by $coltype := collection:get-type(""||$row2/sql:field[@name="obs_collection"])
                return
                    map:entry($coltype, count($row2))
            )))
        ))
    
    let $log := util:log("info", $by-type)
        
    let $xbin-end := xs:integer(max(map:keys($by-year)))
    let $xbin-start := xs:integer(min(map:keys($by-year)))
    let $xbin-size := 1
    let $xbins := data(<text>xbins: {{
                end: {$xbin-end},
                size: .1,
                start:{$xbin-start}
            }}</text>)

    let $calib_levels := sort(distinct-values(for $ym in $by-year?* return map:keys($ym)))
    let $col_types := sort(distinct-values(for $tm in $by-type?* return map:keys($tm)))
    let $instrs := sort(distinct-values(for $m in $by-instr?* return map:keys($m)))

    let $script := <script type="text/javascript">
        {
        for $calib_level in $calib_levels return data(<text>
        var x_{$calib_level} = [ { string-join( for $y in $xbin-start to $xbin-end return $y, ", " ) } ];
        var y_{$calib_level} = [ { string-join( for $y in $xbin-start to $xbin-end return ($by-year($y)($calib_level),0)[1] , ", " ) } ];
        var data_{$calib_level} = {{ y: y_{$calib_level}, x: x_{$calib_level}, type: "bar", name: "L{$calib_level}", opacity: 0.75 }};
        </text>)
        ,
        for $col_type in $col_types return data(<text>
        var typex_{$col_type} = [ { string-join( for $y in $xbin-start to $xbin-end return $y, ", " ) } ];
        var typey_{$col_type} = [ { string-join( for $y in $xbin-start to $xbin-end return ($by-type($y)($col_type),0)[1] , ", " ) } ];
        var typedata_{$col_type} = {{ y: typey_{$col_type}, x: typex_{$col_type}, type: "bar", name: "{$col_type}", opacity: 0.75 }};
        </text>)
        ,
        let $prefix := "instr"
        let $by := $by-instr
        for $t at $pos in $instrs return data(<text>
        var {$prefix}x_{$t} = [ { string-join( for $y in xs:integer(min(map:keys($by))) to xs:integer(max(map:keys($by))) return $y, ", " ) } ];
        var {$prefix}y_{$t} = [ { string-join( for $y in xs:integer(min(map:keys($by))) to xs:integer(max(map:keys($by))) return ($by($y)($t),0)[1] , ", " ) } ];
        var {$prefix}data_{$t} = {{ y: {$prefix}y_{$t}, x: {$prefix}x_{$t}, type: "bar", name: "{$t}", opacity: 0.75 }};
        </text>)
        
        }
        
        var data = [{string-join( (for $calib_level in $calib_levels return "data_"||$calib_level) , ", " )}];
        var layout = {{ barmode: "stack", title: "Collections count by calibration level"}};

        var typedata = [{string-join( (for $col_type in $col_types return "typedata_"||$col_type) , ", " )}];
        var typelayout = {{ barmode: "stack", title: "Collections count by type"}};
        
        var instrdata = [{string-join( (for $t in $instrs return "instrdata_"||$t) , ", " )}];
        var instrlayout = {{ barmode: "stack", title: "Collections count by instrument"}};
        
        Plotly.newPlot('collectionCalibLevels', data, layout);
        Plotly.newPlot('collectionTypes', typedata, typelayout);
        Plotly.newPlot('collectionInstruments', instrdata, instrlayout);
    </script>

    return
        (
            <div id='collectionCalibLevels'/>,
            <div id='collectionTypes'/>,
            <div id='collectionInstruments'/>,
            $script,
            $table
        )
};
