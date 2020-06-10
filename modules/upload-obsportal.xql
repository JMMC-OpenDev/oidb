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

import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";
import module namespace obsportal="http://apps.jmmc.fr/exist/apps/oidb/obsportal" at "obsportal.xqm";

(: job name provided by scheduler :)
declare variable $local:name external;
(: action requested could be used in the future to switch harvesting on obsportal's collection subset VLTI, CHARA.... :)
declare variable $local:action external;

let $response :=
    <response> { 
        try {
            <success>
                <method>{$local:name} - {$local:action}</method>
                {
                    obsportal:sync($local:action)
                }
            </success>
        } catch * {
            <error> { $err:code, $err:description } </error>
        }
    } </response>

return ( log:submit($response), $response )
