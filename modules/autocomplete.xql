xquery version "3.0";

(:~
 : Return as JSON the values matching a search criteria in the specified column
 : from the VOTable.
 : 
 : Parameter 'column' is the column name.
 : Parameter 'search' is the pattern to find in values for the given column.
 :)

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "/db/apps/oidb/modules/tap.xqm";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "text/javascript";

let $column := request:get-parameter("column", "")
let $search := request:get-parameter("search", "")

(: FIXME: SQL injection :)
let $query  := "SELECT DISTINCT t." || $column || " FROM " || $config:sql-table || " AS t WHERE t." || $column || " LIKE '%" || $search || "%'"
(:  execute request and extract only text data in the cells :)
let $values := data(tap:execute($query, false())//*:TD)

(: reformat sequence of values to JavaScript array :)
return concat(
    "[",
    string-join(for $n in $values return '"' || $n || '"', ','),
    "]")
