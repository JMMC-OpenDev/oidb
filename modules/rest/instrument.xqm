xquery version "3.0";

(:~
 : This module provides a REST API to data in the ASPRO configuration files
 : for facilities, instruments and modes.
 :)
module namespace instrument="http://apps.jmmc.fr/exist/apps/oidb/restxq/instrument";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";

declare namespace rest="http://exquery.org/ns/restxq";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

declare namespace a="http://www.jmmc.fr/aspro-oi/0.1";
declare namespace json="http://www.json.org";

(:~
 : Return a list of all instruments known with their hosting facilities.
 : 
 : It accepts patterns for instrument name and/or facility name and return only
 : matching pairs or the full set for empty cases. The patterns are normalized: they are stripped of any
 : non-alphabetic characters that are typically appended to instrument names
 : for description of the instrument mode.
 : 
 : The name comparison is case-insensitive.
 : 
 : Note: the suffix for the number of telescopes in the names of instruments is
 : ignored.
 : 
 : @return an XML documents with <instrument/> elements.
 :)
declare
    %rest:GET
    %rest:path("/oidb/instrument")
    %rest:query-param("facility_name", "{$facname}")
    %rest:query-param("instrument_name", "{$insname}")
function instrument:list($facname as xs:string*, $insname as xs:string*) as element(instruments) {
    <instruments> {
        (: keep leading alphabetic chars from string :)
        let $normalize := function ($x as xs:string?) {
            upper-case(tokenize($x, '[^A-Za-z]')[1])
        }
        (: list of facilities matching $facname :)
        let $facilities :=
            let $all      := collection($config:aspro-conf-root)/a:interferometerSetting/description
            let $filtered := $all[upper-case(./name)=$normalize($facname)]
            return if (empty($filtered)) then $all else $filtered
        for $f in $facilities
            (: list of instruments matching $insname in given facility :)
            let $instruments :=
                let $instruments := if ($insname != '') then
                        let $res := $f/focalInstrument[starts-with(upper-case(./name), $normalize($insname))]
                        return if($res) then $res else $f/focalInstrument
                    else
                        $f/focalInstrument
                (: filter out number of telescopes from full names :)
                let $names := for $x in $instruments/name/text() return $normalize($x)
                return $instruments[index-of($names, $normalize(./name))[1]]
            return
                for $i in $instruments[not($normalize(name)="FAKE")]
                return <instrument facility="{$f/name}" name="{$normalize($i/name)}"/>
    } </instruments>
};

(:~
 : Return a list of modes of a given instrument.
 : 
 : @param $name the name of the instrument in ASPRO conf
 : @return an XML documents with <mode/> elements.
 :)
declare
    %rest:GET
    %rest:path("/oidb/instrument/{$name}/mode")
    %output:media-type("application/json")
    %output:method("json")
function instrument:modes($name as xs:string) as element(modes) {
    <modes> {
        (: find instrument by name or canonical name (no _xT suffix) :)
        let $instrument := collection($config:aspro-conf-root)//focalInstrument[./name=$name or starts-with(./name, $name || '_')]
        let $modes := $instrument/mode
        (: for same instrument at 2 facilities, return only one set of modes :)
        for $m in distinct-values($modes/name/text())
        let $mode := $modes[name=$m][1]
        return <json:value json:array="true"> {
            $mode/*[name()=( 'name', 'waveLengthMin', 'waveLengthMax' )]
        } </json:value>
    } </modes>
};
