xquery version "3.0";

module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log";

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at 'config.xqm';

declare variable $log:submits := $config:data-root || '/log/submits.xml';

(:~
 : Add an element to the submits log detailing the request parameters and the
 : response.
 : 
 : @param $response
 : @return ignore
 :)
declare function log:submit($response as node()) {
    update
        insert
            <submit time="{ current-dateTime() }" user="{ request:get-attribute('user') }">
                <request> {
                    for $n in request:get-parameter-names()
                    return element { $n } { request:get-parameter($n, '') }
                } </request>
                { $response }
            </submit>
        into doc($log:submits)/submits
};
