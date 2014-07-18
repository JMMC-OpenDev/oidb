xquery version "3.0";

(:~
 : Resolve a target with the help of Simbad.
 : 
 : It searches first by name the given name against the aliases known by Simbad
 : and then searches for possible candidates in the vicinity of the position
 : provided.
 : 
 : TODO handle equinox of the coordinates / epoch
 :)

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace jmmc-simbad="http://exist.jmmc.fr/jmmc-resources/simbad";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";

(: Search radius :)
declare variable $local:MAX_DISTANCE := 0.01;

(:~
 : Return a target description from the VOTable row.
 : 
 : The description is made from the oid, ra and dec coordinates and the main
 : name.
 : 
 : @param $row a VOTable row
 : @return a target description as sequence 
 :)
declare function local:target($targets as element(target)*) as element(target)* {
    for $target in $targets
    return element { node-name($target) } { 
        $target/@*,
        $target/node(),
        (: add HMS/DMS formatted coords :)
        <ra_hms>{  jmmc-astro:to-hms($target/ra)  }</ra_hms>,
        <dec_dms>{ jmmc-astro:to-dms($target/dec) }</dec_dms>
    }
};

let $ra    := number(request:get-parameter('ra', ()))
let $dec   := number(request:get-parameter('dec', ()))
let $name  := request:get-parameter('name', false())
return <targets> {
    try {
        (: first resolve by name against Simbad :)
        let $by-name   := jmmc-simbad:resolve-by-name($name, $ra, $dec)
        (: and then resolve by coords against Simbad :)
        let $by-coords := jmmc-simbad:resolve-by-coords($ra, $dec, $local:MAX_DISTANCE)

        return local:target((
            $by-name,
            (: filter out duplicates from resolution by name :)
            $by-coords[not(./name=$by-name/name/text())]
        ))
    } catch * {
        (: TODO better logging when something goes wrong! :)
        util:log('warn', $err:description)
    }
} </targets>
