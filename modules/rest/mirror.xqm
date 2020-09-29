xquery version "3.1";
(:~
 : This module provides a REST API for oidb-mirror and utility functions.
 :)
module namespace mirror="http://apps.jmmc.fr/exist/apps/oidb/restxq/mirror";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "../config.xqm";
(:import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "../tap.xqm";:)
(:import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "../sql-utils.xql";:)
(:import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "../log.xqm";:)
(:import module namespace gran="http://apps.jmmc.fr/exist/apps/oidb/granule" at "../granule.xqm";:)
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "../app.xql";

declare namespace rest="http://exquery.org/ns/restxq";

(: 
  
  Idea here is to handle mirror of remote data (look at jmmc-web/exist/oidb-tools module).

:)

(:~
 : Get list of granules. query parameters may be added to filter granules of interest.
 : @return granules grouped by files
 :)
declare
    %rest:GET
    %rest:path("/oidb/mirror/granules")
function mirror:access_urls() {
    <granules>
        {app:granules((('caliblevel=1,2,3'),for $p in request:get-parameter-names() return $p|| "=" || request:get-parameter($p, ()) ))}
    </granules>
};
