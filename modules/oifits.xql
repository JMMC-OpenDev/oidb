xquery version "3.0";

(:~
 : This module provides templating functions for OIFITS granules.
 :)

module namespace oifits="http://apps.jmmc.fr/exist/apps/oidb/oifits";

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace templates="http://exist-db.org/xquery/templates";

import module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers";

import module namespace jmmc-oiexplorer="http://exist.jmmc.fr/jmmc-resources/oiexplorer";
import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";

declare variable $oifits:staging := $config:data-root || '/oifits/staging/';

(: Replace some escaped chars to beautify the provided urls :)
declare %private function oifits:unescape-uri-path($path as xs:string) as xs:string
{
 $path ! replace(.,"%2522","%22") ! replace(.,"%253C","%3C")  ! replace(.,"%253E","%3E")  ! replace(.,"%255C","%5C")  ! replace(.,"%255E","%5E") ! replace(.,"%2560","%60")  ! replace(.,"%257B","%7B")  ! replace(.,"%257C","%7C") ! replace(.,"%257D","%7D")
};
declare %private function oifits:get-data($model as map(*)) as item()* {
    if (map:contains($model, 'url')) then
        map:get($model, 'url')
    (: try using request parameters instead of model :)
    else if ('url' = request:get-parameter-names()) then
        request:get-parameter('url', false())
    else
        (: TODO check $staging and $path :)
        let $staging := request:get-parameter('staging', false())
        let $path    := request:get-parameter('path', false())
        
        (: TODO create a route in controller for staged files :)
        let $url-file := string-join(tokenize($path, '/') ! encode-for-uri(.), '/') ! oifits:unescape-uri-path(.)
        let $url := '/exist/apps/oidb-data/oifits/staging/' || encode-for-uri($staging) || '/' || $url-file
        
        let $data := util:binary-doc($oifits:staging || $staging || '/' || $path)
        
        return ( $url, $data )
};

(:~
 : Pick metadata from the OIFITS serialized to XML by OIExplorer and build XML granules.
 : 
 : @param $oifits the XML serialization of an OIFITS file
 : @param $url    the URL of the source file
 : @return XML granules for the file
 :)
declare %private function oifits:prepare-granules($oifits as node(), $url as xs:string) as element(granule)* {
    for $target in $oifits/metadata/target
    return element { 'granule' } {
        $target/*,
        (: add missing metadata items from extract :)
        <access_url>{ $url }</access_url>,
        (: convert file size B to kB :)
        <access_estsize>{ $oifits/size/text() idiv 1000 }</access_estsize>
    }
};

(:~
 : Extract granules from OIFITS file and put granule in model for templating.
 : 
 : The input file is taken at the URL in the 'url' key of the current model.
 : 
 : If an error is detected in the input file (L3 excepted) , an error message is added to the
 : model and no granule is returned.
 : 
 : @param $node  the current node in the template
 : @param $model the current model
 : @param $calib_level calibration level (1 to 3)
 : @return a model with granule for the file as sequence of XML fragments.
 :)
declare
    %templates:wrap
function oifits:granules($node as node(), $model as map(*), $calib_level as xs:integer) as map(*) {
    let $data := oifits:get-data($model)
    let $url := $data[1]
    let $map := map { 
        'oifits' := map:new((
        map:entry('url', $url),
        try {
            let $oifits := jmmc-oiexplorer:to-xml($data[last()])/oifits

            let $report := $oifits/checkReport/text()
            let $cnt-severe := count(tokenize($report,"SEVERE"))-1
            let $cnt-warning := count(tokenize($report,"WARNING"))-1
            let $warn-msg := if ($cnt-severe > 0 ) then $cnt-severe||" SEVERE" else if ($cnt-warning > 0) then $cnt-warning || " WARNING" else () 
            
            let $reject-nonl3-severe := false() (: true rejects L1/L2 with SEVERE entry :)
            return map:new(( 
                map:entry('report', $report),
                if ($warn-msg) then
                    map:entry('warning', <span class="text-danger">&#160; {$warn-msg} errors, please try to fix your file and resubmit it later.Please send feedback, if some SEVERE level are too strict. </span>)
                else
                    (),
                (: TODO better tests on report, better report? :)
                if ($reject-nonl3-severe and $calib_level<3 and $cnt-severe>0) then
                    map:entry('message', 'Invalid OIFITS file, no granule retained, see report for details. Please send feedback, if some SEVERE level are too strict.')
                else
                    let $granules := oifits:prepare-granules($oifits, $url)
                    return map:entry('granules', $granules)))
        } catch * {
            map { 'message' := 'error parsing the OIFITS file at ' || $url || '.' }
        }))
    }
    let $s1-map := if ($calib_level=3) then map:entry('skip-quality-level-selector', true()) else ()
    let $s2-map := if ( $calib_level=2 and count(map:get(map:get($map,'oifits'),'granules'))>1) then () else map:entry('skip-oifits-quality-level-selector', true()) 
    return map:new(($map, $s1-map, $s2-map))
};

(:~
 : Insert into the current node the missing data for a granule.
 : 
 : It produces an hidden input element for each piece of data from the granule
 : that has not yet been associated with a form input in the current node.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @return a sequence of hidden <input/> elements.
 :)
declare function oifits:hidden-inputs($node as node(), $model as map(*)) as node()* {
    let $granule := $model('granule')
    (: list of name already included in the form :)
    let $names := data($node/..//*:input[@type='hidden']/@name)
    for $e in $granule/*[not(./name()=$names)]
    (: one hidden input for each name not already included in the form :)
    return <input type="hidden" name="{$e/name()}" value="{$e/text()}"/>
};

(:~
 : Print an MJD date from model to YYYY-MM-DD HH:mm:ss format.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @param $key   the key to lookup in model for the date to templatize
 : @return a string with the formatted date
 :)
declare function oifits:date($node as node(), $model as map(*), $key as xs:string) as xs:string {
    let $date := helpers:get($model, $key)
    return format-dateTime(jmmc-dateutil:MJDtoISO8601($date), "[Y0001]-[M01]-[D01] [H01]:[m01]:[s01]")
};

(:~
 : Print a right ascension angle from model to HMS format.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @param $key   the key to lookup in model for the angle to templatize
 : @return a string with the formatted angle
 :)
declare function oifits:hms($node as node(), $model as map(*), $key as xs:string) as xs:string {
    jmmc-astro:to-hms(helpers:get($model, $key))
};

(:~
 : Print a declination angle from model to DMS format.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @param $key   the key to lookup in model for the angle to templatize
 : @return a string with the formatted angle
 :)
declare function oifits:dms($node as node(), $model as map(*), $key as xs:string) as xs:string {
    jmmc-astro:to-dms(helpers:get($model, $key))
};

(:~
 : Return the basename of a path from model.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @param $key   the key to lookup in model for the path to templatize
 : @return a string with the basename of the path
 :)
declare function oifits:basename($node as node(), $model as map(*), $key as xs:string) as xs:string {
    xmldb:decode(tokenize(helpers:get($model, $key), '/')[last()])
};
