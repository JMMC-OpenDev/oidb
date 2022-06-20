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
 : and depending on whether it is prefixed by '!', '~' or '!~'.
 : 
 : @param $params the text prefixed by '~' or '!~'
 : @return a LIKE predicate
 :)
declare %private function filters:like-text($params as xs:string, $column as xs:string) {
    let $not := if (starts-with($params, '!')) then ' NOT ' else ''
    let $pattern :=
        if ((starts-with($params, '~') or starts-with($params, '!~'))) then
            '%' || substring-after($params, '~') || '%'
        else
            if ($not) then substring-after($params, '!') else $params
    return
        "( " || $adql:correlation-name || "." || $column || $not || " LIKE " || "'" || adql:escape($pattern) || "' )"
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
 : Format an ADQL condition for matching/not matching the data PI.
 : 
 : @params $params the pattern for the data pi name
 : @return an ADQL condition or ()
 :)
declare function filters:datapi($params as xs:string) {
    filters:like-text($params, 'datapi')
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
 : Format an ADQL condition for matching/not matching a facility
 : name.
 : 
 : @param $params the pattern for the facility name
 : @return an ADQL condition or ()
 :)
declare function filters:facility($params as xs:string) {
    filters:like-text($params, 'facility_name')
};

(:~
 : Format an ADQL condition for matching/not matching a progid
 : name.
 : 
 : @param $params the pattern for the facility name
 : @return an ADQL condition or ()
 :)
declare function filters:progid($params as xs:string) {
    filters:like-text($params, 'progid')
};

(:~
 : Format an ADQL condition for matching/not matching a proposal_subid
 : name.
 : 
 : @param $params the pattern for the proposal_subid
 : @return an ADQL condition or ()
 :)
declare function filters:proposal_subid($params as xs:string) {
    filters:like-text($params, 'proposal_subid')
};


(:~
 : Format an ADQL condition for matching/not matching a obs_id
 : name.
 : 
 : @param $params the pattern for the facility name
 : @return an ADQL condition or ()
 :)
declare function filters:obs_id($params as xs:string) {
    filters:like-text($params, 'obs_id')
};


(:~
 : Format an ADQL condition matching rows with calibration levels. 
 : 
 : @param $params the calibration levels, comma separated
 : @return an ADQL condition selecting rows by calibration level
 :)
declare function filters:caliblevel($params as xs:string) {
    let $not := if (starts-with($params, '!')) then 'NOT ' else ''
    let $params := adql:escape(if ($not != '') then substring($params, 2) else $params)
    let $levels :=
        for $l in tokenize($params, ',')
        let $n := xs:integer($l)
        return if ($n ge 0 and $n lt 4) then $n else ()
    return "( " || 
        string-join(
            for $l in $levels return $not || $adql:correlation-name || ".calib_level=" || $l,
            " OR ")
        || " )"
};
(:~
 : Format an ADQL condition matching rows with dataproduct_category levels. 
 : 
 : @param $params the calibration levels, comma separated
 : @return an ADQL condition selecting rows by calibration level
 :)
declare function filters:category($params as xs:string) {
    let $not := if (starts-with($params, '!')) then 'NOT ' else ''
    let $params := adql:escape(if ($not != '') then substring($params, 2) else $params)
    let $cats :=tokenize($params, ',')
    return "( " || 
        string-join(
            ( for $cat in $cats return $not || $adql:correlation-name || ".dataproduct_category LIKE '" || substring($cat,0,4) ||"%'",  if ("SCIENCE"=$cats)  then $adql:correlation-name || ".dataproduct_category IS NULL" else ()),
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
            if( empty($coords ) and (count($tokens) gt 3)) then
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
    let $cs     := filters:parse-conesearch($params)
    let $ra     := xs:double($cs[1])
    let $dec    := xs:double($cs[2])
    let $radius := xs:double($cs[3])
    
    return "( CONTAINS(" ||
        "POINT('ICRS', " || $adql:correlation-name || ".s_ra, " || $adql:correlation-name || ".s_dec), " ||
        "CIRCLE('ICRS', " || $ra || ", " || $dec || ", " || $radius || ")" ||
        ")=1 )"
};

(:~
 : Format an ADQL condition on observation date as interval.
 : 
 : If there is a single date, it is taken as the start date (start of the day) of
 : the interval. If the single date is prefixed by '..', the date
 : is taken as the upper limit of the interval ( end of the day ).
 :  
 : It generates an error if the format of the dates is incorrect.
 : 
 : @param $params a '..' separated couple of date as YYYY-MM-DD
 : @return an ADQL condition selecting items in the time interval
 : @error Invalid date format
 :)
declare function filters:observationdate($params as xs:string) as xs:string {
    (: string -> MJD (+1 day if it is an upper date), false if empty string, error if malformed string :)
    let $to-mjd := function ($x as xs:string?, $from-date as xs:boolean) {
        if (exists($x) and $x != '') then
            try { 
                let $d := if($from-date) then xs:date($x) else xs:date($x) + xs:dayTimeDuration('P1D')
                return jmmc-dateutil:ISO8601toMJD(xs:dateTime($d))
            } catch * {
                error(xs:QName("filters:error"), "Invalid date " || $x)
            }
        else
            false()
    }
    let $dates := tokenize($params, '\.\.')
    let $start-date := $to-mjd($dates[1], true()), $end-date := $to-mjd($dates[2], false())
    return "( " || string-join((
        if ($start-date) then 
            $adql:correlation-name || ".t_max >= " || $start-date
        else
            (),
        if ($start-date and $end-date) then "AND" else (),
        if ($end-date) then
            $adql:correlation-name || ".t_min <= " || $end-date
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
        return try {
                jmmc-astro:wavelength-range($b)
            } catch * {
                error(xs:QName('filters:error'), "Unknown band id " || $b,$b)
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
(:~
 : Format an ADQL condition for a given record given its id.
 : if param id=name:value instead of id=value the given name will be used instead of 'id'.
 : 
 : @param $id to return only given id
 : @return an ADQL condition selecting items id
 :)
declare function filters:id($params as xs:string) {
    let $p := tokenize($params, ":")
    return 
        if (count($p)=1) then 
            $adql:correlation-name || ".id=" || $params
        else
            $adql:correlation-name || "." || $p[1] || "=" || $p[2]
};

