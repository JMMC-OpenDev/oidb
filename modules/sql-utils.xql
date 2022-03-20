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
 : Get db connection handle from jndi-connection.
 : WARNING !! this connection must be closed after use with sql-utils:close-connection. Not closing connection may starve connection pool. 
 :)
declare function sql-utils:get-jndi-connection(){
    let $connection-handle := sql:get-jndi-connection($config:jndi-name)
    let $log := util:log("info", "sql-utils:get-jndi-connection() => " || $connection-handle)
(:    util:log("info", "please replace this code by sql:get-jndi-connection(sql-utils:get-jndi-name()) and use sql:execute in caller code"),:)
    return $connection-handle
    
};

(:~ 
 : Close a sql connection.
 :)
declare function sql-utils:close-connection($connection-handle){
    util:log("info", "sql-utils:close-connection() => "|| $connection-handle),
    sql:close-connection($connection-handle)
};

(:~ 
 : Get jndi name so the caller can get the connection handle on it's side, so it will be removed '

:)
declare function sql-utils:get-jndi-name(){
    $config:jndi-name
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
        let $log := util:log("info", "COMMIT TRANSACTION")
        return $ret
    } catch * {
        util:log("info", "ROLLBACK TRANSACTION"),
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
    let $db-handle := sql-utils:get-jndi-connection()
    let $res := sql-utils:within-transaction($db-handle, $func)
    let $close := sql:close-connection($db-handle)
    return 
        $res
};

declare function sql-utils:execute($sql-statement as xs:string, $make-node-from-column-name as xs:boolean) as node()?
{
    let $db-handle := sql-utils:get-jndi-connection()
    let $res := 
        try {
            sql-utils:execute($db-handle, $sql-statement, $make-node-from-column-name)
        } catch * {
            sql:close-connection($db-handle),
            (: pass error :)
            error($err:code, $err:description, $err:value)
        }
    let $close := sql-utils:close-connection($db-handle)
    return 
        $res
};
(:~
 : Wrapper of SQL execute function.
 : Executes a SQL statement against a SQL db using the connection indicated by the connection handle (that MUST be created with sql-utils:get-jndi-connection.
 :
 : @param $connection-handle  The connection handle 
 : @param $sql-statement The SQL statement
 : @param $make-node-from-column-name The flag that indicates whether the xml nodes should be formed from the column names (in this mode a space in a Column Name will be replaced by an underscore
 : @return the results
 :)
declare function sql-utils:execute($connection-handle as xs:long, $sql-statement as xs:string, $make-node-from-column-name as xs:boolean) as node()? {

    try {
        let $log := util:log("info", "execute : " || $sql-statement || " with handle = "|| $connection-handle)
        let $ret := sql:execute($connection-handle, $sql-statement, $make-node-from-column-name)
        return $ret
    } catch * {
        let $log := util:log("error", "exception occurs using given handle (" || $connection-handle ||")")
        let $log := util:log("error", $err:description)
        return 
            error($err:code, $err:description, $err:value)
    }
        
(:    let $ret := if (exists($ret)) then $ret else :) 
(:        let $log := util:log("error", "no result using given handle (" || $connection-handle ||") :  trying with a new one ") :) 
        (: Next line MUST NOT USE  config:get-db-connection else we are out of context after and lose connection :)
(:        return  :)
(:            sql:execute(sql:get-jndi-connection($config:jndi-name), $sql-statement, $make-node-from-column-name) :)

(:    let $ret := if (exists($ret)) then $ret else util:log("error", "Fatal case can't execute : " || $sql-statement):)
    
(:    return :)
(:      $ret:)
};
