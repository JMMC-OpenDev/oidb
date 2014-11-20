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

declare %private function oifits:get-data($model as map(*)) as item()* {
    if (map:contains($model, 'url')) then
        map:get($model, 'url')
    (: try using request parameters instead of model :)
    else if ('url' = request:get-parameter-names()) then
        request:get-parameter('url', false())
    else
        let $staging := request:get-parameter('staging', false())
        let $path    := request:get-parameter('path', false())
        (: TODO check $staging and $path :)

        (: TODO create a route in controller for staged files :)
        let $url := '/exist/apps/oidb-data/oifits/staging/' || encode-for-uri($staging) || '/' || encode-for-uri($path)
        let $data := util:binary-doc($oifits:staging || $staging || '/' || $path)
        return ( $url, $data )
};

(:~
 : Extract granules from OIFITS file and put granule in model for templating.
 : 
 : The input file is taken at the URL in the 'url' key of the current model.
 : 
 : @param $node  the current node in the template
 : @param $model the current model
 : @return a model with granule for the file as sequence of XML fragments.
 :)
declare
    %templates:wrap
function oifits:granules($node as node(), $model as map(*)) as map(*) {
    let $data := oifits:get-data($model)
    (: process OIFITS file with OIExplorer to extract metadata :)
    let $oifits := jmmc-oiexplorer:to-xml($data[last()])/oifits
(:    let $oifits := jmmc-oiexplorer:to-xml(if (starts-with($data[last()], '/db/')) then util:binary-doc($data[last()]) else $data[last()])/oifits:)
    let $url := $data[1]
    let $granules := 
        for $target in $oifits/metadata/target
        return element { 'granule' } { 
            $target/*,
            (: add missing metadata items from extract :)
            <access_url>{ $url }</access_url>,
            (: convert file size B to kB :)
            <access_estsize>{ $oifits/size/text() idiv 1000 }</access_estsize> 
        }
    let $report := $oifits/checkReport/text()

    return map { 'oifits' :=
        map {
            'url'      := $url,
            'granules' := $granules,
            'report'   := $report
        }
    }
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