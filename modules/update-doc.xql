xquery version "3.0";

(:~
 : This module handle inline documentation.
 : 
 : The source for the documentation is hosted on the JMMC's TWiki. The purpose
 : of this module is to fetch on demand the HTML from the wiki and save it in
 : the database to be used as inline documentation.
 :)

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

declare namespace xhtml="http://www.w3.org/1999/xhtml";


(:~
 : Fetch the HTML formatted documentation from the TWiki page.
 : 
 : @return a fragment of the TWiki page for documentation
 :)
declare function local:get-doc() as element() {
    let $uri := xs:anyURI($config:maindoc-twiki-url)
    (: some twiki install return headers with an empty  : charset=  that broke the process. Have a look on the content-type header line :)
    return hc:send-request(<hc:request method="GET" href="http://www.jmmc.fr/twiki/bin/view/Jmmc/Software/OiDbInlineDoc"/>)//xhtml:div[@class="patternContent"]
};

(:~
 : Apply transformation to HTML content with special filtering to counterpass twiki tips.
 : 
 : @param $nodes the node to transform
 : @return the transformed nodes
 :)
declare function local:transform($nodes as node()*) as item()* {
    for $node in $nodes
    return typeswitch($node)
        case text() return $node
        case comment() return $node
        case attribute() return
            if (name($node)="href" and ends-with($node, '/OiDB')) 
            then 
                attribute { 'href' } { './' } 
            else if (name($node)="src" and starts-with($node, '/')) 
            then
                attribute { 'src' } { "http://www.jmmc.fr" || $node } 
            else
                $node
        default return 
            if(name($node)="a" and contains($node/@href, "/bin/edit/")) then ()
            else element { QName(namespace-uri($node), name($node)) } { ( local:transform($node/@*), local:transform($node/node()) ) }
};

(:~
 : Save fragment as documentation, replacing older documentation if any.
 : 
 : @param $node the new documentation
 :)
declare function local:save($node as node()) {
    if(doc($config:data-root || "/" || $config:maindoc-filename)) then
        xmldb:remove($config:data-root, $config:maindoc-filename)
    else
        (),
    xmldb:store($config:data-root, $config:maindoc-filename, $node)
};

let $response :=
    <response> {
        try {
            <success> {
                let $doc := local:get-doc()
                return local:save(local:transform($doc))
            } </success>
        } catch * {
            <error> { $err:code, $err:description } </error>
        }
    } </response>

return $response
