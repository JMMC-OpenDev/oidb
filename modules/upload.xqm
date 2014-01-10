xquery version "3.0";

(:~
 : This module provides functions to save the metadata to the underlying 
 : SQL database.
 :)
module namespace upload="http://apps.jmmc.fr/exist/apps/oidb/upload";

import module namespace util="http://exist-db.org/xquery/util";
import module namespace sql="http://exist-db.org/xquery/sql";

(: Import SQL config :)
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

(: Module for OIFitsViewer with metadata export :)
import module namespace oi="http://jmmc.fr/exist/oi" at "java:fr.jmmc.exist.ViewerModule";

(:~
 : Derive the filename from an URI.
 : 
 : @param $uri the URI to parse
 : @return the substring following the last '/' in the URI
 :)
declare %private function upload:basename($uri as xs:anyURI) {
    tokenize($uri, "/")[last()]
};

(:~
 : Format an INSERT SQL request with column names from the node names and 
 : values from the node values.
 : 
 : @param $nodes a sequence of nodes with row values
 : @return an INSERT statement
 :)
declare %private function upload:insert-statement($nodes as node()*) {
    fn:concat(
        "INSERT INTO ",
        $config:sql-table,
        " SET ",
        fn:string-join(
            for $node in $nodes 
            return concat(name($node), "=&quot;", data($node), "&quot;"), ','),
        "")
};

(:~
 : Put the data in the SQL database.
 : If the operatio fails, it returns the error message in a <error> element,
 : otherwise it returns a <success> element.
 : 
 : @param $metadata a sequence of nodes with the metadata
 : @return <success> or <error> element
 :)
declare function upload:upload($metadata as node()*) {
    let $db_handle := sql:get-connection(
        $config:sql-driver-classname,
        $config:sql-url,
        $config:sql-username,
        $config:sql-password)
    let $statement := upload:insert-statement($metadata)
    let $result := sql:execute($db_handle, $statement, false())
    return
        if ($result/name() = "sql:exception") then
            <error>
                Failed to upload file: { $result//sql:message/text() }
            </error>
        else
            <success>
                Uploaded file successfully
            </success>
};

(:~
 : Save metadata into database with additional info (contact an dataset ID).
 : 
 : @param $metadata a node with elements as metadata
 : @param $url the URI to the source file
 : @param $collection an optional identifier for a containing dataset
 : @param $contact an optional contact info to associate to data
 : @return <success> or <error> element
 :)
declare function upload:upload-file($metadata as node(), $url as xs:anyURI, $collection as xs:string?, $contact as xs:string?) {
    upload:upload((
        $metadata/*,
        <access_url> { $url } </access_url>))
};

(:~
 : Save metadata from file at URL into database.
 : The file at the URL is processed with OIFitsViewer to extract metadata.
 : 
 : TODO: check errors if viewer fails
 : 
 : @param $url the URL where to retrieve the file
 : @param $more additionnal metadata not in the file
 : @return <success> or <error> element
 :)
declare function upload:upload-uri($url as xs:anyURI, $more as node()*) {
    let $data := util:parse(oi:viewer($url))
    for $target in $data//metadata/target
    return upload:upload(($target/*, <access_url> { $url } </access_url>, $more))
};
