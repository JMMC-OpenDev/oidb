xquery version "3.0";

module namespace oifits="http://apps.jmmc.fr/exist/apps/oidb/oifits";

import module namespace templates="http://exist-db.org/xquery/templates";

import module namespace jmmc-oiexplorer="http://exist.jmmc.fr/jmmc-resources/oiexplorer";
import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-astro="http://exist.jmmc.fr/jmmc-resources/astro";


(:~
 :)
declare
    %templates:wrap
function oifits:granules($node as node(), $model as map(*)) as map(*) {
    let $url := map:get($model, 'url')
    let $oifits := jmmc-oiexplorer:to-xml("" || $url)/oifits
    let $granules := 
        for $target in $oifits/metadata/target
        return element { 'granule' } { 
            $target/*,
            <access_url>{ $url }</access_url>,
            <access_estsize>{ $oifits/size/text() idiv 1000 }</access_estsize> 
        }

    return map {
        'granules' := $granules
    }
};

(:~
 :)
declare function oifits:each-granule($node as node(), $model as map(*)) as node()* {
    for $granule in $model('granules')
    return element { node-name($node) } {
        $node/@*,
        templates:process($node/node(), 
            map:new((
                $model, 
                map:entry('granule', $granule),
                for $e in $granule/* return map:entry($e/name(), $e/text()))))
    }
};

(:~
 :)
declare function oifits:hidden-inputs($node as node(), $model as map(*)) as node()* {
    let $granule := $model('granule')
    (: list of name already included in the form :)
    let $names := data($node/..//*:input[@type='hidden']/@name)
    for $e in $granule/*[not(./name()=$names)]
    return <input type="hidden" name="{$e/name()}" value="{$e/text()}"/>
};

(:~
 :)
declare function oifits:date($node as node(), $model as map(*), $key as xs:string) as xs:string {
    let $date := map:get($model, $key)
    return format-dateTime(jmmc-dateutil:MJDtoISO8601($date), "[Y0001]-[M01]-[D01] [H01]:[m01]:[s01]")
};

(:~
 :)
declare function oifits:hms($node as node(), $model as map(*), $key as xs:string) as xs:string {
    jmmc-astro:to-hms(map:get($model, $key))
};

(:~
 :)
declare function oifits:dms($node as node(), $model as map(*), $key as xs:string) as xs:string {
    jmmc-astro:to-dms(map:get($model, $key))
};

(:~
 :)
declare function oifits:basename($node as node(), $model as map(*), $key as xs:string) as xs:string {
    tokenize(map:get($model, $key), '/')[last()]
};