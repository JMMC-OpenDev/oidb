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

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";


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
declare %private function upload:insert-statement($metadata as node()*) {
    let $obs_release_date :=    if($metadata/self::obs_release_date) then
                                    () (: node is already in metadata :)
                                else if($metadata/self::data_rights="secure") then
                                    (: compute obs_release_date with t_max + embargo duration 
                                       TODO put this constant out and make it adjustable by user before submission if consensus 
                                    :)
                                    <obs_release_date>
                                        {substring(string(jmmc-dateutil:MJDtoISO8601($metadata/self::t_max) + xs:yearMonthDuration('P1Y')) , 0, 22) }
                                    </obs_release_date>
                                else
                                    () (: TODO check that this empty case is normal :)
    let $nodes := ($metadata, $obs_release_date)
    let $columns := for $x in $nodes return name($x)
    let $values  := for $x in $nodes return "'" || upload:escape($x) || "'"
    return 
    concat(
        "INSERT INTO ",
        $config:sql-table,
        " ( " || string-join($columns, ', ') || " ) ",
        "VALUES",
        " ( " || string-join($values,  ', ') || " )")
};

(:~
 : Put the data in the SQL database.
 : 
 : If the operation fails, it generates an error.
 :
 : @param $db_handle database handle 
 : @param $metadata a sequence of nodes with the metadata
 : @error failed to upload (SQL exception)
 : @return nothing
 :)
declare function upload:upload($db_handle as xs:long, $metadata as node()*) {
    let $statement := upload:insert-statement($metadata)
    let $result := sql:execute($db_handle, $statement, false())
    return
        if ($result/name() = "sql:exception") then
            error(xs:QName('upload:SQLInsert'),
                "Failed to upload: " || $result//sql:message/text() || ", query: " || $statement)
        else
            ()
};

(:~
 : Save metadata from file at URL into database.
 : 
 : The file at the URL is processed with OIFitsViewer to extract metadata.
 : If an error occurs when saving a row, the process is stopped and an 
 : error is generated.
 : 
 : TODO: check errors if viewer fails
 : TODO: wrap in transaction, rollback if error
 : 
 : @param $db_handle database handle
 : @param $url the URL where to retrieve the file
 : @param $more additionnal metadata not in the file
 : @error failed to upload (SQL exception) (from upload:upload)
 : @return the check report from the OIFits file parser
 :)
declare function upload:upload-uri($db_handle as xs:long, $url as xs:anyURI, $more as node()*) {
    let $data := util:parse(oi:viewer($url))
    let $more := (
        $more,
        (: add missing access information :)
        (: FIXME kludge, better find file size elsewhere (parser) :)
        let $estsize := number(httpclient:get($url, false(), <headers/>)//httpclient:headers/httpclient:header[@name='Content-Length']/@value)
        return <access_estsize>{ $estsize }</access_estsize>,
        <access_format>application/fits</access_format>
    )
    (: validation report for file by OIFitsViewer :)
    let $report := $data//checkReport/node()
    (: TODO check report for major problems before going further :)
    return (
        for $target in $data//metadata/target
        return try {
            upload:upload($db_handle, ($target/*, <access_url> { $url } </access_url>, $more))
        } catch * {
            (: add report to exception value :)
            error($err:code , $err:description, ($err:value, $report))
        },
        $report
    )
};

(:~
 : Escape a string for SQL query.
 : 
 : @param $str the string to escape
 : @return the escaped string
 :)
declare %private function upload:escape($str as xs:string) as xs:string {
    (: FIXME more escapes? same as adql:escape()? :)
    replace($str, "'", "''")
};
