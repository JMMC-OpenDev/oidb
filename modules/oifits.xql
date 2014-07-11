xquery version "3.0";

(:~
 : This module provides templating functions for OIFITS granules.
 :)

module namespace oifits="http://apps.jmmc.fr/exist/apps/oidb/oifits";

import module namespace templates="http://exist-db.org/xquery/templates";

import module namespace jmmc-oiexplorer="http://exist.jmmc.fr/jmmc-resources/oiexplorer";
import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";


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
    let $url := map:get($model, 'url')
    (: process OIFITS file with OIExplorer to extract metadata :)
    let $oifits := jmmc-oiexplorer:to-xml("" || $url)/oifits
    let $granules := 
        for $target in $oifits/metadata/target
        return element { 'granule' } { 
            $target/*,
            (: add missing metadata items from extract :)
            <access_url>{ $url }</access_url>,
            (: convert file size B to kB :)
            <access_estsize>{ $oifits/size/text() idiv 1000 }</access_estsize> 
        }

    return map {
        'granules' := $granules
    }
};

(:~
 : Iterate over each granule in the model and templatize child nodes.
 : 
 : The granules are taken from the 'granules' key in the current model as XML
 : fragments. The children of the root element are translated into model
 : entries for templating.
 : 
 : @param $node  the current node, taken as pattern at each iteration
 : @param $model the current model
 : @return a sequence of nodes, one for each granule
 :)
declare function oifits:each-granule($node as node(), $model as map(*)) as node()* {
    for $granule in $model('granules')
    return element { node-name($node) } {
        $node/@*,
        (: templatize child nodes with granule data :)
        templates:process($node/node(), 
            map:new((
                $model, 
                (: add the raw XML fragment of granule to model... :)
                map:entry('granule', $granule),
                (: ... and break out granule data into individual model entries :)
                for $e in $granule/* return map:entry($e/name(), $e/text()))))
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
    let $date := map:get($model, $key)
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
    jmmc-astro:to-hms(map:get($model, $key))
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
    jmmc-astro:to-dms(map:get($model, $key))
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
    tokenize(map:get($model, $key), '/')[last()]
};