xquery version "3.0";

(:~
 : This module provides a helper function to resolve star names and retrieve
 : position information and type from Sesame Name Resolver
 : (http://cds.u-strasbg.fr/cgi-bin/Sesame/).
 : 
 : It builds up a cache of previous resolutions to avoid repetitive queries
 : to Sesame.
 :)
module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame";

(: The cache of resolved stars :)
declare variable $sesame:resolved := doc('/db/apps/oidb-data/sesame.xml');

(:~
 : Return a target element with data on name, position and type as attributes.
 : 
 : @param $target a <Target> element from a Sesame response
 : @return a <target> element with data as attributes.
 :)
declare %private function sesame:target($target as node()) as node() {
    <target> {
        attribute { 'name' }  { $target/name/text() },
        (: use data from first database with result :)
        attribute { 's_ra' }  { ($target//jradeg)[1]/text() },
        attribute { 's_dec' } { ($target//jdedeg)[1]/text() },
        (: :)
        attribute { 'otype' } { ($target//otype)[1]/text() }
    } </target> 
};

(: Sesame base URL: resolve name with with Simbad database, XML output  :)
declare variable $sesame:SESAME_URL := "http://cdsweb.u-strasbg.fr/cgi-bin/nph-sesame/-ox/S?";
(:declare variable $sesame:SESAME_URL := "http://vizier.cfa.harvard.edu/viz-bin/nph-sesame/-ox/S?";:)

(: Sesame 4X XML Schema for validation :)
declare variable $sesame:SCHEMA := doc('/db/apps/oidb/resources/schemas/sesame_4x.xsd');

(:~
 : Resolve names with Sesame.
 : (http://cds.u-strasbg.fr/cgi-bin/Sesame/SNV)
 : 
 : @param names a sequence of star names.
 : @return a <sesame> element a <target> with data for each input name.
 : @error Failed to retrieve data from Sesame
 : @error Invalid response from Sesame
 : @error No result found
 :)
declare function sesame:resolve-sesame($names as xs:string+) as item()* {
    let $uri := concat($sesame:SESAME_URL, string-join(for $name in $names return encode-for-uri($name), '&amp;'))
    let $response := httpclient:get($uri, false(), <headers/>)
    
    return if ($response/@statusCode != 200 or $response/httpclient:body/@type != "xml") then
        error(xs:QName('sesame:HTTP'), 'Failed to retrieve data from Sesame')
    (: @todo response not always valid, see HD166014, report upstream? :)
(:    else if (not(validation:validate($response//httpclient:body/Sesame, $sesame:SCHEMA))) then:)
(:        error(xs:QName('sesame:validation'), 'Invalid response from Sesame' || $response):)
    (: check there is something returned for each name :)
    else if($response//httpclient:body/Sesame/Target[not(./Resolver)]) then
        let $idx := count($response//Target[not(./Resolver)]/preceding-sibling::*)+1
        return error(xs:QName('sesame:resolve'), 'No result for ' || $names[$idx])
    else
        for $target in $response//httpclient:body/Sesame/Target
        return sesame:target($target)
};

(:~
 : Resolve star names.
 : 
 : It returns the coordinates and the object type corresponding to
 : the specified names.
 : 
 : It builds a local cache of previous request. If there are unknown
 : names, the function queries the Sesame service with these names and
 : updates the cache.
 : 
 : @param $names a set of star names to resolve
 : @return a <sesame> element a <target> with data for each input name.
 :)
declare function sesame:resolve($names as xs:string+) as node() {
    (: FIXME no caching for the time being :)
    <sesame> { sesame:resolve-sesame($names) } </sesame>
};
