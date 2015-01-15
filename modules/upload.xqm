xquery version "3.0";

module namespace upload="http://apps.jmmc.fr/exist/apps/oidb/upload";

import module namespace sql="http://exist-db.org/xquery/sql";

(: Import SQL config :)
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

(:~
 : Escape a string for SQL query.
 : 
 : @param $str the string to escape
 : @return the escaped string
 :)
declare function upload:escape($str as xs:string) as xs:string {
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
