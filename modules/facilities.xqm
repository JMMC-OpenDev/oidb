xquery version "3.0";

(:~
 : This module provides functions to handle facilities.
 :)
module namespace facilities="http://apps.jmmc.fr/exist/apps/oidb/facilities";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

declare variable $facilities:aspro := collection($config:aspro-conf-root)/*:interferometerSetting;

declare variable $facilities:oidb := <facilities>
        <facility>
            <name>CHARA</name>
            <description>Center for High Angular Resolution Astronomy</description>
            <homepage>http://www.chara.gsu.edu/</homepage>
        </facility>
        <facility>
            <name>MROI</name>
            <description>Magdalena Ridge Observatory Interferometer</description>
             <homepage>http://www.mro.nmt.edu/about-mro/interferometer-mroi/</homepage>
        </facility>
        <facility>
            <name>NPOI</name>
            <description>Navy Precision Optical Interferometer</description>
            <homepage>http://www2.lowell.edu/rsch/npoi/index.php</homepage>
        </facility>
        <facility>
            <name>SUSI</name>
            <description>Sydney University Stellar Interferometer</description>
            <homepage>https://www.sydney.edu.au/science/our-research/research-centres/sydney-institute-for-astronomy/astronomy-facilities.html</homepage>
        </facility>
        <facility>
            <name>VLTI</name>
            <description>Very Large Telescope Interferometer</description>
            <homepage>https://www.eso.org/sci/facilities/paranal/telescopes/vlti.html</homepage>
        </facility>
        <facility>
            <name>PTI</name>
            <description>Palomar Testbed Interferometer</description>
            <homepage>https://nexsci.caltech.edu/missions/Palomar/</homepage>
        </facility>
        <facility>
            <name>IOTA</name>
            <description>Infrared Optical Telescope Array</description>
            <homepage>https://en.wikipedia.org/wiki/Infrared_Optical_Telescope_Array</homepage>
        </facility>
    </facilities>;
    
declare variable $facilities:hidden := ("DEMO", "OHP", "Paranal", "Sutherland");  
    

declare %private function facilities:aspro-facility($name as xs:string) {
    $facilities:aspro[*:description/*:name=$name]
};

declare function facilities:description($facility-name as xs:string) {
    let $desc := $facilities:oidb/facility[name=$facility-name]/description
    let $desc := if($desc) then $desc else facilities:aspro-facility($facility-name)/*:description/*:description
    return $desc
};

declare function facilities:homepage($facility-name as xs:string) {
    (: not provided by aspro2 :)
    $facilities:oidb/facility[name=$facility-name]/homepage
};

declare function facilities:coords($facility-name as xs:string) {
    (: only those of aspro2 :)
    let $facility := facilities:aspro-facility($facility-name)
    let $coords := data($facility/*:description/*:position/*)
    (: http://stackoverflow.com/questions/1185408/converting-from-longitude-latitude-to-cartesian-coordinates :)
(:    let $x := xs:double($coords[1]):)
(:    let $y := xs:double($coords[2]):)
(:    let $z := xs:double($coords[3]):)
(:    let $r := xs:double(6371000):)
(:    let $lat := math:asin( $z div $r ) * 180 div math:pi():)
(:    let $lon := math:atan2($y, $x) * 180 div math:pi():)
      let $lat := ()
      let $lon := ()
    return
        (
            string-join($coords,",")
            ,<a href="http://www.openstreetmap.org/?mlat={$lat}&amp;mlon={$lon}&amp;zoom=12">{string-join((format-number($lat, '###.00'),format-number($lon, '###.00')),",")}</a>
        )
    
};

declare function facilities:table($tap-facilities as xs:string*) {
(:    let $aspro-facilities := distinct-values(data(collection($config:aspro-conf-root)/*:interferometerSetting/*:description/*:name)):)
(:    if ($tap-facilities[not(.)=$aspro-facilities]) then recompute facilities else use cache:)

    let $facilities := 
        <facilities>
            {
                for $lname in distinct-values(($tap-facilities, $facilities:aspro/*:description/*:name, $facilities:oidb//name)) 
                group by $name := upper-case(if (matches($lname,"\.")) then substring-after($lname,".") else if (matches($lname,"_")) then substring-before($lname,"_")else $lname) 
                order by $name
                let $coords := facilities:coords($name)
                return 
                    <facility>
                        { for $n in $lname order by $n return <name>{$n}</name> }
                        <description>{facilities:description($name)}</description>
                        <homepage>{facilities:homepage($name)}</homepage>
                        <coords>{$coords[1]}</coords>
                        <latlon>{$coords[2]}</latlon>
                    </facility>
            }
        </facilities>
    
    return
    <table class="table table-striped table-bordered table-hover">
        <tr><th>Name</th><th>Description / homepage</th><th>X,Y,Z coordinates</th><!--<th>Lat,Lon approx. </th>--><th>records in the database</th></tr>
        {
            for $facility in $facilities/*
                let $names :=  for $name in $facility/name return (<a href="search.html?facility={$name}">{$name}</a>,<br/>)
                let $desc := $facility/description/*
                let $homepage := $facility/homepage
                let $homepage := if (string-length($homepage)>0) then <a href="{$homepage}"><i class="glyphicon glyphicon-link"/></a> else ()
                let $coords := data($facility/coords)
(:                let $latlon := $facility/latlon/*:)
                let $has-records := if( $facility/name=$tap-facilities) then <i class="glyphicon glyphicon-ok"/> else ()
                where  not($facility/name = $facilities:hidden)
                return
                    <tr>
                        <th>{$names}</th><td>{$desc}&#160;{$homepage}</td><td>{$coords}</td><!--<td>{$latlon} </td>--><td>{$has-records}</td>
                    </tr>
        }
    </table>
};
