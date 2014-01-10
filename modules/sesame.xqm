xquery version "3.0";

(:~
 : This module provides a helper function to resolve star names and retrieve
 : position information from Sesame Name Resolver
 : (http://cds.u-strasbg.fr/cgi-bin/Sesame/SNV).
 :)
module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

(: resolve name with with all databases :)
declare variable $sesame:SESAME_URL := "http://cdsweb.u-strasbg.fr/cgi-bin/nph-sesame/-oxp/A?";

(:~
 : Resolve names with SESAME.
 : (http://cds.u-strasbg.fr/cgi-bin/Sesame/SNV)
 : 
 : @param names a sequence of star names.
 : @return a <sesame> element a <target> with data for each input name.
 :)
declare function sesame:get-positions($names as xs:string*)as node()* {
    <sesame> {
        let $uri  := concat($sesame:SESAME_URL, string-join($names, '&amp;'))
        let $data := httpclient:get($uri, false(), <headers/>)//httpclient:body

        for $target in $data//Target
        return <target> { 
            attribute { 'name' }  { $target/name/text() },
            (: use data from first database with result :)
            attribute { 's_ra' }  { ($target//jradeg)[1]/text() },
            attribute { 's_dec' } { ($target//jdedeg)[1]/text() }
        } </target> 
    } </sesame>
};
