xquery version "3.0";

(:~
 :)
module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.2";

(: UCD (Unified Content Descriptor) description service :)
declare variable $tap:UCD_URL := "http://cdsws.u-strasbg.fr/axis/services/UCD?method=explain&amp;ucd=";

(:~
 :)
declare %private function tap:nodes-from-field-name($votable as node()?) as node() {
    let $headers := $votable//votable:FIELD
    let $header_names := for $header in $headers return data($header/@name)

    return <votable> <tr> {
        for $field in $votable//votable:FIELD
        return <th>
            { $field/@name } 
            { data($field/@name) } 
            { if($field/@ucd)  then ( <br/>, <a href="{ concat($tap:UCD_URL,data($field/@ucd)) }"> { data($field/@ucd) } </a>) else () }
            <!-- { if($field/@unit) then ( <br/>, <span> [ { data($field/@unit) } ] </span> ) else () } -->
        </th> 
        } </tr> {       
        for $row in  $votable//votable:TABLEDATA/votable:TR
        return <tr> {
            for $node at $i in $row/votable:TD
            return <td>
                { $node/@*, 
                  attribute { "colname" } { $header_names[$i] },
                  $node/node() }
            </td>
        } </tr>
    } </votable>
};

(:~
 : Executes an ADQL statement against the database with TAP.
 : 
 : @param $adql-statement the ADQL statement
 : @param $make-node-from-field-name A flag to request processing of cells
 : @return a VOTABLE node as returned by the TAP service or a votable node of 
 : cells with the field name as attribute 'colname'.
 :)
declare function tap:execute($adql-statement as xs:string, $make-node-from-field-name as xs:boolean) as node()? {
    (: make the request to database :)
    let $uri     := $config:TAP_SYNC || '?' || string-join((
        'REQUEST=doQuery',
        'LANG=ADQL',
        'FORMAT=votable',
        'QUERY=' || encode-for-uri($adql-statement)), '&amp;')
    let $data    := httpclient:get($uri, false(), <headers/> )//httpclient:body

    return if ($make-node-from-field-name) then
        (: convert VOTABLE to table and add 'colname' attribute to cells :)
        tap:nodes-from-field-name($data//votable:VOTABLE)
    else
        $data//votable:VOTABLE
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