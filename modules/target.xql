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

import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";


declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";

(: Search radius :)
declare variable $local:MAX_DISTANCE := 0.01;

(: Simbad TAP endpoint :)
declare variable $local:SIMBAD-TAP-SYNC := "http://simbad.u-strasbg.fr/simbad/sim-tap/sync";


(:~
 : Execute an ADQL query against a TAP service.
 : 
 : @param $uri   the URI of a TAP sync resource
 : @param $query the ADQL query to execute
 : @return a VOTable with results for the query
 : @error service unavailable, bad response
 :)
declare %private function local:tap-adql-query($uri as xs:string, $query as xs:string) as node() {
    let $uri := $uri || '?' || string-join((
        'REQUEST=doQuery',
        'LANG=ADQL',
        'FORMAT=votable',
        'QUERY=' || encode-for-uri($query)), '&amp;')
    let $response := http:send-request(<http:request method="GET" href="{$uri}"/>)
    
    return if ($response[1]/@status != 200) then
        error(xs:QName('local:TAP'), 'Failed to retrieve data for target', $query)
    else if (count($response[1]/http:body) != 1) then
        error(xs:QName('local:TAP'), 'Bad content returned')
    else
        let $body := $response[2]
        return if ($body instance of node()) then $body else util:parse($body)
};

(:~
 : Return a target description from the VOTable row.
 : 
 : The description is made from the oid, ra and dec coordinates and the main
 : name.
 : 
 : @param $row a VOTable row
 : @return a target description as sequence 
 :)
declare function local:target($row as element(votable:TR)) as element(target) {
    <target> {
        for $f at $i in $row/ancestor::votable:TABLE/votable:FIELD
        let $name  := $f/@name
        let $value := $row/votable:TD[position() = $i]/text()
        return (
            element { $name } { $value },
            (: format conversion for ra and dec :)
            if ($name = 'ra')       then  <ra_hms>{ jmmc-astro:to-hms($value) }</ra_hms>
            else if ($name = 'dec') then <dec_dms>{ jmmc-astro:to-dms($value) }</dec_dms>
            else ()
        )
    } </target>
};

(:~
 : Run an ADQL query against a TAP service and return the rows of results.
 : 
 : @param $uri the TAP resource to query
 : @param $query the ADQL query to execute
 : @return target descriptions if resolution succeeds
 : @error not found, off coord hit
 :)
declare %private function local:resolve($uri as xs:string, $query as xs:string) as node()* {
    let $result   := local:tap-adql-query($uri, $query)
    let $resource := $result//votable:RESOURCE
    let $rows     := $resource//votable:TR
    (: return target details :)
    for $r in $rows return local:target($r)
};

(:~
 : Try to identify a target from its fingerprint with Simbad.
 : 
 : @param $identifier the target name
 : @param $ra the target right ascension in degrees
 : @param $dec the target declination in degrees
 : @return a target identifier if target is found or a falsy if target is unknown
 :)
declare %private function local:resolve-simbad($identifier as xs:string, $ra as xs:double, $dec as xs:double) as item()* {
    let $query :=
        "SELECT oid AS id, ra, dec, main_id AS name, DISTANCE(POINT('ICRS', ra, dec), POINT('ICRS', " || $ra || ", " || $dec || ")) AS dist " ||
        "FROM basic JOIN ident ON oidref=oid " ||
        "WHERE id = '" || encode-for-uri($identifier) || "' " ||
        "ORDER BY dist"
    let $result := local:resolve($local:SIMBAD-TAP-SYNC, $query)
    (: TODO check distance of result from coords :)
    return $result
};

(:~
 : Search for targets in the vicinity of given coords.
 : 
 : @param $ra a right ascension in degrees
 : @param $dec a declination in degrees
 : @return a sequence of identifiers for targets near the coords (sorted by distance)
 :)
declare %private function local:resolve-simbad-by-coords($ra as xs:double, $dec as xs:double) as item()* {
    let $query :=
        "SELECT oid AS id, ra, dec, main_id AS name, DISTANCE(POINT('ICRS', ra, dec), POINT('ICRS', " || $ra || ", " || $dec || ")) AS dist " ||
        "FROM basic " ||
        "WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', " || $ra || ", " || $dec || ",  " || $local:MAX_DISTANCE || " )) = 1 " ||
        "ORDER BY dist"
    let $result := local:resolve($local:SIMBAD-TAP-SYNC, $query)
    return $result
};

let $ra    := number(request:get-parameter('ra', ()))
let $dec   := number(request:get-parameter('dec', ()))
let $name  := request:get-parameter('name', false())
return <targets> {
    try {
        (: first resolve by name against Simbad :)
        let $by-name   := local:resolve-simbad($name, $ra, $dec)
        (: and then resolve by coords against Simbad :)
        let $by-coords := local:resolve-simbad-by-coords($ra, $dec)

        return (
            $by-name,
            (: filter out duplicates from resolution by name :)
            $by-coords[not(./name=$by-name/name/text())]
        )
    } catch * {
        (: TODO better logging when something goes wrong! :)
        util:log('warn', $err:description)
    }
} </targets>
