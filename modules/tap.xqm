xquery version "3.0";

(:~
 :)
module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";

(:~
 : Executes an ADQL statement against the database with TAP.
 : 
 : @param $adql-statement the ADQL statement
 : @return a VOTABLE node as returned by the TAP service.
 :)
declare function tap:execute($adql-statement as xs:string) as node()? {
    (: make the request to database :)
    let $uri     := $config:TAP_SYNC || '?' || string-join((
        'REQUEST=doQuery',
        'LANG=ADQL',
        'FORMAT=votable',
        'QUERY=' || encode-for-uri($adql-statement)), '&amp;')
    let $data    := httpclient:get($uri, false(), <headers/> )//httpclient:body

    return $data//votable:VOTABLE
};

(:~
 : Provide a status log on TAP service.
 : This status is called by backoffice:main-status()
 : 
 : @return the status information.
 :)
declare function tap:check-status()
{
    let $tap-table-list-status := try{
            let $doc := doc($config:TAP_TABLES)
            let $root-name := name ($doc/*)
            return if ($root-name="tableset") then 
                <span><i class="glyphicon glyphicon-ok"/> tap service responds properly </span>
            else if (empty($doc)) then
                <span><i class="glyphicon glyphicon-remove"/> tap service fails </span>
            else
                <span><i class="glyphicon glyphicon-remove"/> tap service does not respond properly : root name is {$root-name}</span>
        }catch * { 
                <span><i class="glyphicon glyphicon-remove"/> tap service failed : {$err:description} </span>
        }
        
    return
        <div>
            { $tap-table-list-status }<br/>
            <em>TODO add link to services</em>
        </div>
};