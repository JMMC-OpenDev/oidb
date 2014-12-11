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
        " ( " || string-join($values,  ', ') || " ) ",
        (: Note: PostgreSQL extension :)
        "RETURNING id")
};

(:~
 : Put the data in the SQL database.
 : 
 : If the operation fails, it generates an error.
 :
 : @param $db_handle database handle 
 : @param $metadata a sequence of nodes with the metadata
 : @error failed to upload (SQL exception)
 : @return the id of the just inserted row if available
 :)
declare function upload:upload($db_handle as xs:long, $metadata as node()*) as xs:integer {
    let $statement := upload:insert-statement($metadata)
    let $result := sql:execute($db_handle, $statement, false())
    return
        if ($result/name() = "sql:exception") then
            error(xs:QName('upload:SQLInsert'),
                "Failed to upload: " || $result//sql:message/text() || ", query: " || $statement)
        else
            (: return the id of the inserted row :)
            $result//sql:field[@name='id'][1]
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

(:~
 : Execute a function within an SQL transaction.
 : 
 : The function is passed the given connection handle to perform operation on
 : the database within the transaction.
 : 
 : If an error is raised, the transaction is rolled back and the error is
 : passed to the calling function.
 : 
 : @param $db_handle database handle 
 : @param $fun function to execute in transaction
 : @return the value returned by the function
 : @error any error thrown by tbe function
 :)
declare function upload:within-transaction($db_handle as xs:long, $func as function(xs:long) as item()*) as item()* {
    try {
        let $begin := sql:execute($db_handle, "START TRANSACTION", false())
        let $ret   := $func($db_handle)
        let $end   := sql:execute($db_handle, "COMMIT", false())
        return $ret
    } catch * {
        (: abort the current transaction :)
        sql:execute($db_handle, "ROLLBACK", false()),
        (: pass error :)
        error($err:code, $err:description, $err:value)
    }
};

(:~
 : Execute a function within an SQL transaction.
 :
 : The function automatically creates the database connection handle passed to
 : the function for the operation as its only parameter.
 : 
 : @param $fun function to execute in transaction
 : @return the value returned by the function
 : @error any error thrown by the function
 :)
declare function upload:within-transaction($func as function(xs:long) as item()*) as item()* {
    upload:within-transaction(config:get-db-connection(), $func)
};
