xquery version "3.0";

(:~
 : This module provides a set of utility function on top of eXist-db module
 : for performing SQL queries against databases.
 :)
module namespace sql-utils="http://apps.jmmc.fr/exist/apps/oidb/sql-utils";

import module namespace sql="http://exist-db.org/xquery/sql";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

(:~
 : Escape a string for SQL query.
 : 
 : @param $str the string to escape
 : @return the escaped string
 :)
declare function sql-utils:escape($str as xs:string) as xs:string {
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
declare function sql-utils:within-transaction($db_handle as xs:long, $func as function(xs:long) as item()*) as item()* {
    try {
        let $log := util:log("info", "START TRANSACTION")
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
declare function sql-utils:within-transaction($func as function(xs:long) as item()*) as item()* {
    (: sql-utils:within-transaction(sql:get-jndi-connection($config:jndi-name), $func) :)
    sql-utils:within-transaction(sql:get-jndi-connection($config:jndi-name), $func)
};

(:~
 : Wrapper of SQL execute function.
 : Executes a SQL statement against a SQL db using the connection indicated by the connection handle or use config:get-db-connection if nothing returned.
 :
 : @param $connection-handle  The connection handle
 : @param $sql-statement The SQL statement
 : @param $make-node-from-column-name The flag that indicates whether the xml nodes should be formed from the column names (in this mode a space in a Column Name will be replaced by an underscore
 : @return the results
 :)
declare function sql-utils:execute($connection-handle as xs:long, $sql-statement as xs:string, $make-node-from-column-name as xs:boolean) as node()? {

    let $log := util:log("info", "execute : " || $sql-statement || " with handle = "|| $connection-handle)
    let $ret := sql:execute($connection-handle, $sql-statement, $make-node-from-column-name)
    let $ret := if (exists($ret)) then $ret else 
        let $log := util:log("error", "no result using given handle (" || $connection-handle ||") :  trying with a new one ")
        (: Next line MUST NOT USE  config:get-db-connection else we are out of context after and lose connection :)
        return 
            sql:execute(sql:get-jndi-connection($config:jndi-name), $sql-statement, $make-node-from-column-name)
    let $ret := if (exists($ret)) then $ret else util:log("error", "Fatal case can't execute : " || $sql-statement)
    
    return 
      $ret
};
