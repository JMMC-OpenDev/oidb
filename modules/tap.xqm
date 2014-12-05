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
 : @error bad response or problem reported by TAP server
 :)
declare function tap:execute($adql-statement as xs:string) as node()? {
    (: make the request to database :)
    let $uri     := $config:TAP_SYNC || '?' || string-join((
        'REQUEST=doQuery',
        'LANG=ADQL',
        'FORMAT=votable',
        'QUERY=' || encode-for-uri($adql-statement)), '&amp;')
    let $data    := httpclient:get($uri, false(), <headers/> )//httpclient:body

    return if (empty($data) or empty($data/votable:VOTABLE)) then
        error(xs:QName('tap:error'), 'Bad response from the TAP server')
    else if ($data//votable:INFO[@name='QUERY_STATUS'][@value='ERROR']) then
        let $error := $data//votable:INFO[@name='QUERY_STATUS']/text()
        return error(xs:QName('tap:error'), 'The TAP server reported an error', $error)
    else
        $data/votable:VOTABLE
};

(:~
 : Return whether the VOTable contains all available results.
 : 
 : @param $votable the VOTable to check
 : @return true if the result overflowed
 :)
declare function tap:overflowed($votable as node()) as xs:boolean {
    exists($votable//votable:TABLE/following-sibling::votable:INFO[@name='QUERY_STATUS' and @value='OVERFLOW'])
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
    else if (name($tables/*) != 'tableset') then
        'bad response (no table metadata)'
    else
        ()
};
