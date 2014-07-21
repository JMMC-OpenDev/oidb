xquery version "3.0";

(:~
 : Push an XML granule into the database.
 : 
 : The granule is passed as an XML fragment where element name are columns and
 : text the respective value.
 : 
 : It returns a <response> element containing either a <success> or <error>
 : element.
 :)

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace util = "http://exist-db.org/xquery/util";

import module namespace config = "http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace upload = "http://apps.jmmc.fr/exist/apps/oidb/upload" at "upload.xqm";
import module namespace log="http://apps.jmmc.fr/exist/apps/oidb/log" at "log.xqm";

let $data := request:get-data()

let $db_handle := config:get-db-connection()

let $response :=
    <response> {
        try {
            <id>{ upload:upload($db_handle, $data/granule/*) }</id>,
            <success>Successfully uploaded granule</success>
        } catch * {
            response:set-status-code(400) (: Bad Request:),
            <error> { $err:description } </error>
        }
    } </response>

return ( log:submit($response), $response )
