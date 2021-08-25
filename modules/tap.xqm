xquery version "3.0";

(:~
 : TAP module that forward requested to the endpoint and return votables.
 : Some constant an highly repeated requests are cached until tap:cache-destroy() call
 : app:clear-cache() MUST BE called by every part of code that modify the SQL database side.
 : 
 :)
module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace jmmc-cache="http://exist.jmmc.fr/jmmc-resources/cache";



(:  prepare a cache for some classical requests :)
declare variable $tap:cache :=
    try {
        let $doc := doc($config:data-root || '/tmp/tap-cache.xml')
        let $doc := if($doc/cache) then $doc else doc(xmldb:store($config:data-root || '/tmp', 'tap-cache.xml', <cache/>))
        return $doc/cache
    } catch * {
        error(xs:QName('error'), 'Failed to create cache for tap-cache.xql: ' || $err:description, $err:value)
    };
declare variable $tap:cache-insert   := jmmc-cache:insert($tap:cache, ?, ?);
declare variable $tap:cache-get      := jmmc-cache:get($tap:cache, ?);
declare variable $tap:cache-contains := jmmc-cache:contains($tap:cache, ?);
declare variable $tap:cache-flush  :=  jmmc-cache:flush($tap:cache,()); 


(:~
 : Executes an ADQL statement against the database with TAP.
 : 
 : @param $adql-statement the ADQL statement
 : @return a VOTABLE node as returned by the TAP service.
 : @error bad response or problem reported by TAP server
 :)
declare function tap:execute($adql-statement as xs:string) as node()? {
    tap:execute($adql-statement, ())
};

(:~
 : Executes an ADQL statement against the database with TAP and limit number of rows.
 : 
 : @param $adql-statement the ADQL statement
 : @param $maxrec         the maximum number of table records to return
 : @return a VOTABLE node as returned by the TAP service.
 : @error bad response or problem reported by TAP server
 :)
declare function tap:execute($adql-statement as xs:string, $maxrec as xs:integer?) as node()? {
    tap:execute($adql-statement, $maxrec, ())
};

(: STILL TO BE CONTINUED TO SUPPORT JSON AS RETURN VALUE :)
(:~
 : Executes an ADQL statement against the database with TAP and limit number of rows.
 : 
 : @param $adql-statement the ADQL statement
 : @param $maxrec         the maximum number of table records to return
 : @param $format         the expected return format to return
 : @return a VOTABLE node as returned by the TAP service.
 : @error bad response or problem reported by TAP server
 :)
declare function tap:execute($adql-statement as xs:string, $maxrec as xs:integer?, $format as xs:string?) {
    (: make the request to database :)
    let $uri     := $config:TAP_SYNC || '?' || string-join((
        'REQUEST=doQuery',
        'LANG=ADQL',
        'FORMAT=' || ( if( $format) then $format else 'votable/td' ) , (: votable/td replaces in vollt old votable of taplib :)
        'MAXREC=' || ( if ($maxrec) then  $maxrec else '-1' ),
        'QUERY=' || encode-for-uri($adql-statement)), '&amp;')
        
    (: let $log := util:log('info', "Querying TAP : " || $uri) :)
    let $data    := hc:send-request(<hc:request method="get" href="{$uri}"/> )

    return if (empty($data) or empty($data/*:VOTABLE)) then
(:        error(xs:QName('tap:error'), 'Bad response from the TAP server:'||(string-join((for $e in $data return name($e)),"-")) ):)
        error(xs:QName('tap:error'), 'Bad response from the TAP server:'||serialize($data) )
    else if ($data//*:INFO[@name='QUERY_STATUS'][@value='ERROR']) then
        let $error := $data//*:INFO[@name='QUERY_STATUS']/text()
        return error(xs:QName('tap:error'), 'The TAP server reported an error', $error)
    else
        $data/*:VOTABLE
};


(:~
 : Executes an ADQL statement against the database with TAP and limit number of rows if not present in cache.
 : 
 : @param $adql-statement the ADQL statement
 : @return a VOTABLE node as returned by the TAP service.
 : @error bad response or problem reported by TAP server
 :)
declare function tap:retrieve-or-execute($adql-statement as xs:string) as node()? {
   tap:retrieve-or-execute($adql-statement,())
};

(:~
 : Executes an ADQL statement against the database with TAP and limit number of rows if not present in cache.
 : 
 : @param $adql-statement the ADQL statement
 : @param $maxrec         the maximum number of table records to return
 : @return a VOTABLE node as returned by the TAP service.
 : @error bad response or problem reported by TAP server
 :)
declare function tap:retrieve-or-execute($adql-statement as xs:string, $maxrec as xs:integer?) as node()? {
    let $key := if(empty($maxrec)) then $adql-statement else $adql-statement||$maxrec
    let $cached := $tap:cache-get($key) 
    
    return 
        if(exists($cached)) then 
            $cached[1]
        else
            let $log := util:log("info", "add new tap cache entry [count="||count($tap:cache/*)||"] for"||$key)
            return
                $tap:cache-insert($adql-statement, tap:execute($adql-statement, $maxrec))
};


(:~
 : Return whether the VOTable contains all available results.
 : 
 : @param $votable the VOTable to check
 : @return true if the result overflowed
 :)
declare function tap:overflowed($votable as node()) as xs:boolean {
    exists($votable//*:TABLE/following-sibling::*:INFO[@name='QUERY_STATUS' and @value='OVERFLOW'])
};

(:~
 : Return the status of the TAP service.
 : 
 : @return empty if service OK, a diagnostic of the issue as a string otherwise.
 :)
declare function tap:status() as xs:string?
{
    let $tables := doc($config:TAP_TABLES)
    return if (empty($tables)) then
        'service error (no /tables resource)'
    else if (not(exists($tables/*:tableset))) then
        'bad response (no table metadata)'
    else
        ()
};

(:~
 : clear the cache associated to hardcoded TAP queries
 :)
declare function tap:clear-cache(){
    jmmc-cache:flush($tap:cache,())
};
