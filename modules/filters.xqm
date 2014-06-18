xquery version "3.0";

(:~
 : This modules contains functions to serialize filter requests as ADQL
 : conditions.
 : 
 : Each filter function takes a single string as parameter. The function is in
 : charge of analyzing and parsing the parameter and may raise an error if it 
 : fails building a proper condition.
 : 
 : @note
 : Only filter functions should be made public within this module.
 :)
module namespace filters="http://apps.jmmc.fr/exist/apps/oidb/filters";

import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";

import module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame" at "sesame.xqm";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";

(:~
 : Prepare a LIKE/NOT LIKE ADQL condition for a pattern on
 : a given column.
 : 
 : It builds the condition matching the text of the parameter
 : and depending on whether it is prefixed by '~' or '!~'.
 : 
 : @param $params the text prefixed by '~' or '!~'
 : @return a LIKE predicate or () if bad pattern format
 :)
declare %private function filters:like-text($params as xs:string, $column as xs:string) {
    if (starts-with($params, '~') or starts-with($params, '!~')) then
        let $not  := if (starts-with($params, '!')) then 'NOT ' else ''
        let $name := adql:escape(substring-after($params, '~'))
        return
            "( " || $adql:correlation-name || "." || $column || " " || $not || "LIKE " || "'%" || $name || "%' )"
    else
        ()
};

(:~
 : Format an ADQL condition for matching/not matching target names.
 : 
 : @param $params the pattern for the target name
 : @return an ADQL condition or ()
 :)
declare function filters:target($params as xs:string) {
    filters:like-text($params, 'target_name')
};

(:~
 : Format an ADQL condition for matching/not matching the owner of the data.
 : 
 : @params $params the pattern for the data pi name
 : @return an ADQL condition or ()
 :)
declare function filters:datapi($params as xs:string) {
    filters:like-text($params, 'obs_creator_name')
};

(:~
 : Format an ADQL condition for matching/not matching a collection
 : name.
 : 
 : @param $params the pattern for the collection name
 : @return an ADQL condition or ()
 :)
declare function filters:collection($params as xs:string) {
    filters:like-text($params, 'obs_collection')
};

(:~
 : Format an ADQL condition not/equals on instrument name.
 : 
 : @param $params the instrument name optionnaly prefixed by '!'
 : @return a comparison operation on column instrument_name
 :)
declare function filters:instrument($params as xs:string) {
    let $not := if (starts-with($params, '!')) then 'NOT' else ''
    let $instrument := adql:escape(if ($not != '') then substring($params, 2) else $params)
    return
        "( " || $adql:correlation-name || ".instrument_name " || $not || " LIKE '" || $instrument || "%' )"
};

(:~
 : Format an ADQL condition matching rows with calibration levels. 
 : 
 : @param $params the calibration levels, comma separated
 : @return an ADQL condition selecting rows by calibration level
 :)
declare function filters:caliblevel($params as xs:string) {
    let $levels :=
        for $l in tokenize($params, ',')
        let $n := xs:integer($l)
        return if ($n ge 0 and $n lt 4) then $n else ()
    return "( " || 
        string-join(
            for $l in $levels return $adql:correlation-name || ".calib_level=" || $l,
            " OR ")
        || " )"
};

(:~
 : Helper function for splitting a string of coordinates for a cone search.
 : 
 : The coordinates is made of:
 :  - a position as coords for right ascension and declination or a star name
 :  - an equinox (FIXME currently unused)
 :  - a radius
 :  - the radius unit (deg, arcmin, arcsec)
 : These values are comma-separated in the filter string.
 : 
 : For example:
 : <ul>
 : <li>*%20alf%CMa,J2000,0.1,arcsec</li>
 : <li>06:45:08.91 -16:42:58.0,J2000,0.1,arcsec</li>
 : <li>101.28715533 -16.71611586,J2000,0.1,arcsec</li>
 : </ul>
 : 
 : @param $coords
 : @return a three items sequences: ra, dec and radius in degrees
 : @error malformed parameter, failed to extract values
 :)
declare %private function filters:parse-conesearch($coords as xs:string) as item()* {
    let $tokens := tokenize($coords, ',')
    (: requested position, three format possible :)
    let $position :=
        let $p := $tokens[1]
        let $tokens := tokenize($p, '[ :]')[. != '']
        let $coords := 
            if(count($tokens) = 2) then
                (: ra and dec in degrees (space between ra and dec) ? :)
                try {
                    ( xs:double($tokens[1]), xs:double($tokens[2]) )
                } catch * { () }
            else 
                ()
        let $coords := 
            if(empty($coords)) then
                (: then maybe ra and dec in sexagesimal ? :)
                try {
                    let $a := string-join(subsequence($tokens, 1, 3), ' ')
                    let $d := string-join(subsequence($tokens, 4, 3), ' ')
                    return ( jmmc-astro:from-hms($a), jmmc-astro:from-dms($d) )
                } catch * { () }
            else
                $coords
        return if (empty($coords) and count($tokens) lt 5) then
            (: everything else failed, is it a name? use sesame :)
            try {
                let $resolved := sesame:resolve($p)/target[1]
                return ( xs:double($resolved/@s_ra), xs:double($resolved/@s_dec) )
            } catch sesame:resolve {
                (: tried everything by now, we give up :)
                error(xs:QName("filters:error"), "Failed to resolve position " || $p)
            }
        else
            $coords
    (: cone search radius: apply conversion on params for a radius in degree :)
    let $radius :=
        let $r := try {
            xs:double($tokens[3])
        } catch * {
            error(xs:QName("filters:error"), "Failed to parse search radius " || $tokens[3])
        }
        let $u := $tokens[4]
        return switch($u) 
            case "deg"    return $r
            case "arcmin" return $r div 60
            case "arcsec" return $r div 3600
            default
                return error(xs:QName("filters:error"), "Unknown conesearch radius unit " || $u)

    return ( $position, $radius )
};

import module namespace m="http://exist-db.org/xquery/math";

(:~
 : Format a Cone Search as an ADQL condition.
 : 
 : @see filters.xqm;parse-conesearch;Parameter format
 : 
 : @param $params coordinates as comma-separated list of angles
 : in degree or space separated sexagesimal values.
 : @return an ADQL condition selecting items for the defined region
 :)
declare function filters:conesearch($params as xs:string) as xs:string {
    let $cs     := filters:parse-conesearch(xmldb:decode($params))
    let $ra     := xs:double($cs[1])
    let $dec    := xs:double($cs[2])
    let $radius := xs:double($cs[3])
    
(:    return "( CONTAINS(" ||:)
(:        "POINT('ICRS', " || $adql:correlation-name || ".s_ra, " || $adql:correlation-name || ".s_dec), " ||:)
(:        "CIRCLE('ICRS', " || $ra || ", " || $dec || ", " || $radius || ")" ||:)
(:        ")=1 )":)

    (: alternate SQL condition for Cone Search with AstroGrid DSA :)
    let $dec-min := $dec - $radius
    let $dec-max := $dec + $radius
    let $ra-min := $ra - m:degrees(m:radians($radius) div m:cos(m:radians($dec)))
    let $ra-max := $ra + m:degrees(m:radians($radius) div m:cos(m:radians($dec)))
    (: rough bounding box, then spherical law of cosine :)
    return "( " ||
            $adql:correlation-name || ".s_dec <= " || $dec-max || " AND " || $adql:correlation-name || ".s_dec >= " || $dec-min || " AND " ||
            $adql:correlation-name || ".s_ra  <= " || $ra-max  || " AND " || $adql:correlation-name || ".s_ra  >= " || $ra-min  || " AND " ||
            "ACOS(" ||
                "SIN(RADIANS(" || $adql:correlation-name || ".s_dec)) * SIN(" || m:radians($dec) || ") + " ||
                "COS(RADIANS(" || $adql:correlation-name || ".s_dec)) * COS(" || m:radians($dec) || ") * COS(RADIANS(" || $adql:correlation-name || ".s_ra) - " || m:radians($ra) || ")" ||
            ") <= " || m:radians($radius) ||
        " )"
};

(:~
 : Format an ADQL condition on observation date as interval.
 : 
 : If there is a single date, it is taken as the start date of
 : the interval. If the single date is prefixed by '..', the date
 : is taken as the upper limit of the interval.
 : 
 : It generates an error if the format of the dates is incorrect.
 : 
 : @param $params a '..' separated couple of date as YYYY-MM-DD
 : @return an ADQL condition selecting items in the time interval
 : @error Invalid date format
 :)
declare function filters:observationdate($params as xs:string) as xs:string {
    (: string -> MJD, false if empty string, error if malformed string :)
    let $to-mjd := function ($x as xs:string?) {
        if (exists($x) and $x != '') then
            try { 
                jmmc-dateutil:ISO8601toMJD(xs:dateTime(xs:date($x)))
            } catch * {
                error(xs:QName("filters:error"), "Invalid date " || $x)
            }
        else
            false()
    }
    let $dates := tokenize($params, '\.\.')
    let $start-date := $to-mjd($dates[1]), $end-date := $to-mjd($dates[2])
    return "( " || string-join((
        if ($start-date) then 
            $adql:correlation-name || ".t_min >= " || $start-date
        else
            (),
        if ($start-date and $end-date) then "AND" else (),
        if ($end-date) then
            $adql:correlation-name || ".t_max <= " || $end-date
        else
            ()
    ), ' ') || " )"
};

(:~
 : Format an ADQL condition for observations in given bands.
 : 
 : @note
 : This function only checks that the limits of the wavelength values for an
 : item are within the band span. As a result some middle bands may have no
 : measurement.
 : 
 : @param $params a comma-separated list of band names
 : @return an ADQL condition selecting items with measurements in the given bands
 : @error Unknown band name
 :)
declare function filters:wavelengthband($params as xs:string) {
    let $p := tokenize($params, ',')
    (: all band limits :)
    let $limits :=
        for $b in $p 
        return switch ($b)
        (: wavelength ranges :)
        case "visible" return ( 0.3, 1 )
        case "near-ir" return ( 1,   5 )
        case "mid-ir"  return ( 5,   18.6 )
        (: individual band names :)
        default return 
            try {
                jmmc-astro:wavelength-range($b)
            } catch * {
                error(xs:QName('filters:error'), "Unknown band id " || $b)
            }
    (: upper and lower wavelengths, convert to meter :)
    let $minlambda := min($limits) * 1e-6
    let $maxlambda := max($limits) * 1e-6
    return "( " ||
            $adql:correlation-name || ".em_min > " || $minlambda || " AND " ||
            $adql:correlation-name || ".em_max < " || $maxlambda ||
        " )"
};

(:~
 : Format an ADQL condition for public or private observations.
 : 
 : @param $params 'yes' to return only available observations
 : @return an ADQL condition selecting public or private items
 :)
declare function filters:public($params as xs:string) {
    let $not  := if ($params = 'yes') then '' else 'NOT '
    return $not || "( " ||
            $adql:correlation-name || ".data_rights='public' OR " ||
            $adql:correlation-name || ".obs_release_date < '" || string(current-dateTime()) || "'" ||
        " )"
};
