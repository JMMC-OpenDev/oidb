xquery version "3.0";

(:~
 : This module provides a helper function to resolve star names and retrieve
 : position information and type from Sesame Name Resolver
 : (http://cds.u-strasbg.fr/cgi-bin/Sesame/).
 : 
 : Be kind: split your big queries and throttle the requests!
 :)
module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame";


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
declare variable $sesame:SCHEMA := doc('/db/apps/oidb/data/schemas/sesame_4x.xsd');

(:~
 : Resolve names with Sesame.
 : (http://cds.u-strasbg.fr/cgi-bin/Sesame/SNV)
 : 
 : @param names a sequence of star names.
 : @return a <sesame> element a <target> with data for each input name.
 : @error Failed to retrieve data from Sesame
 : @error Invalid response from Sesame
 :)
declare function sesame:resolve($names as xs:string+) as node() {
    <sesame> {
        let $uri := concat($sesame:SESAME_URL, string-join($names, '&amp;'))
        let $response := httpclient:get($uri, false(), <headers/>)
        
        return if ($response/@statusCode != 200 or $response/httpclient:body/@type != "xml") then
            error(xs:QName('sesame:HTTP'), 'Failed to retrieve data from Sesame')
        else if (not(validation:validate($response//httpclient:body/Sesame, $sesame:SCHEMA))) then
            error(xs:QName('sesame:validation'), 'Invalid response from Sesame')
        else
            (: check there is something returned for each name :)
            for $name in $names
            let $target := $response//httpclient:body/Sesame/Target[./name=$name]
            return if (exists($target) and exists($target/Resolver)) then
                    sesame:target($target)
                else
                    <warning> No result for {$name} </warning>
    } </sesame>
};
