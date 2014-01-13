xquery version "3.0";

(:~
 :)
module namespace cs="http://apps.jmmc.fr/exist/apps/oidb/conesearch";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

declare namespace votable="http://www.ivoa.net/xml/VOTable/v1.1";

(: UCD (Unified Content Descriptor) description service :)
declare variable $cs:UCD_URL := "http://cdsws.u-strasbg.fr/axis/services/UCD?method=explain&amp;ucd=";

declare %private function cs:nodes-from-field-name($votable as node()?) as node() {
    let $headers := $votable//votable:FIELD
    let $header_names := for $header in $headers return data($header/@name)

    return <votable> <tr> {
        for $field in $votable//votable:FIELD
        return <th>
            { $field/@name } 
            { data($field/@name) } 
            { if($field/@ucd)  then ( <br/>, <a href="{ concat($cs:UCD_URL,data($field/@ucd)) }"> { data($field/@ucd) } </a>) else () }
            { if($field/@unit) then ( <br/>, <span> [ { data($field/@unit) } ] </span> ) else () }
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
 : Do a cone search given a sky position and angular distance.
 : 
 : See http://www.ivoa.net/Documents/latest/ConeSearch.html
 : 
 : @param $ra right-ascension for the position of center (decimal degrees)
 : @param $dec declination for the position of center (decimal degrees)
 : @param $radius radius of the cone search (decimal degrees)
 : @param $make-node-from-field-name A flag to request processing of cells
 : @return a VOTABLE node as returned by DSA or a votable node of cells with 
 : the field name as attribute 'colname'.
 :)
declare function cs:execute($ra as xs:double, $dec as xs:double, $radius as xs:double, $make-node-from-field-name as xs:boolean) as node()? {
    (: make the request to DSA :)
    let $uri  := concat($config:CS_DSA_URL, concat("&amp;RA=", $ra, "&amp;DEC=", $dec, "&amp;SR=", $radius))
    let $data := httpclient:get($uri, false(), <headers/> )//httpclient:body
    
    return if ($make-node-from-field-name) then
        (: convert VOTABLE to table and add 'colname' attribute to cells :)
        cs:nodes-from-field-name($data/node())
    else
        $data/node()
};
