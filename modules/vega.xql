xquery version "3.0";

module namespace vega="http://apps.jmmc.fr/exist/apps/oidb/vega";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";

(:  :)
declare variable $vega:VEGAWS_URL := "http://vegaobs-ws.oca.eu/axis2/services/VegaWs.VegaWsHttpport/VegaWs/";


declare function vega:get-users() as node() ?{
    let $uri     := concat($vega:VEGAWS_URL, '/', 'getUserList')
    let $data    := httpclient:get($uri, false(), <headers/> )//httpclient:body
    
    for $return in $data//return
    return <user> {
        let $tokens := tokenize($return, '\t')
        return attribute { "id" } { $tokens[0] }, attribute { "name" } { concat($tokens[1], "-",$tokens[2]) }
    } </user>
};
