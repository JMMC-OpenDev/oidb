xquery version "3.1";

declare function local:search($collection-uri as xs:anyURI, $callback as function(xs:anyURI) as item()*) {
try{    for $res in xmldb:get-child-resources($collection-uri)
        return $callback(xs:anyURI(string-join(($collection-uri,$res),"/")))
}catch * {"error for " || $collection-uri}
    ,
try{    for $sub-col in xmldb:get-child-collections($collection-uri)
        let $do := $callback(xs:anyURI(string-join(($collection-uri,$sub-col),"/")))
        return local:search(xs:anyURI(string-join(($collection-uri,$sub-col),"/")), $callback)
}catch * {"error for " || $collection-uri}
};

declare function local:show($resource-uri as xs:anyURI*) as item()* {
    $resource-uri 
};

declare function local:fix($resource-uri as xs:anyURI*) as item()* {
    let $perms := sm:get-permissions($resource-uri)
    let $owner := $perms//@owner
    let $old := "tstuber@astrophysik.uni-kiel.de"
    where $owner=$old
    let $new := "tstuber@arizona.edu"
    let $update := sm:chown($resource-uri, $new)
    return 
        ( $resource-uri || " updated for "|| $new)
        
};

local:search(xs:anyURI("/db/apps/oidb-data"), local:fix(?))

