xquery version "3.0";

(:~
 : Perform an upload of all observations from ObsPortal service.
 :
 : The observations previously imported by the same way are deleted.
 : 
 : All database operations in this script are executed within a 
 : transaction: if any failure occurs, the database is left unchanged.
 : 
 : It returns a <response> fragment with the status of the operation.
 :)

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils" at "sql-utils.xql";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";
import module namespace obsportal="http://apps.jmmc.fr/exist/apps/oidb/obsportal" at "obsportal.xqm";
import module namespace sql="http://exist-db.org/xquery/sql";
import module namespace sesame="http://apps.jmmc.fr/exist/apps/oidb/sesame" at "sesame.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";
import module namespace jmmc-cache="http://exist.jmmc.fr/jmmc-resources/cache";

(: job name provided by scheduler :)
declare variable $local:name external;
(: action requested could be used in the future to switch harvesting on obsportal's collection subset VLTI, CHARA.... :)
declare variable $local:action external;

let $response :=
    <response> {
        try {
            <success>
                <method>{$local:name}</method>
                {
                    let $new := obsportal:get-observations()
                    let $ids := sql-utils:within-transaction(obsportal:upload(?, $new))
                    return $ids
(:                util:log("info", "mockup"):)
                }
            </success>
        } catch * {
            <error> { $err:code, $err:description } </error>
        }
    } </response>

return ( log:submit($response), $response )
