xquery version "3.1";

(:~
 : Return the VOTable for the serialized query.
 : 
 : If the query can not be built or executed, it instead returns an <error> 
 : element with error text.
 :)

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "xml";
declare option output:media-type "application/x-votable+xml";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

declare function local:param($parent, $name, $value ) {
    element {QName(namespace-uri($parent), "PARAM")} { 
                attribute {"arraysize"} {"*"}, attribute {"datatype"} {"char"},
                attribute {"ID"} {$name}, attribute {"name"} {$name}, attribute {"value"} {$value}
            }
};

let $response :=
    try {
        (: build the query from the request query string :)
        let $query := adql:build-query(
            (: remove pagination and column set :)
            adql:clear-pagination(
                adql:clear-select-list(
                    adql:split-query-string()))
        )
        (: run the ADQL SELECT :)
        let $votable := tap:execute($query)
        let $table := $votable//*:TABLE
        let $instrument_name_index := index-of( $table/*:FIELD/@name, 'instrument_name')
        let $instruments := distinct-values($table//*:TR/*:TD[position()=$instrument_name_index])
        let $params := if( count($instruments) = 1 )
        then
            (: TODO improve selection of proper stations instead of first one :)
            let $stations := (collection($config:aspro-conf-root)//instrument[focalInstrument=$instruments or starts-with(focalInstrument, $instruments || '_')][1]//stations)[1]
            return
                if($stations)
                then
                    let $interferometer := $stations/ancestor::*:interferometerSetting/description/name
                    let $instruments := if($instruments = "MATISSE") then "MATISSE_LM" else $instruments
                    let $period := collection($config:aspro-conf-root)//configuration[instrument[focalInstrument=$instruments or starts-with(focalInstrument, $instruments || '_')]]//version[1]
                    let $period := string-join( collection($config:aspro-conf-root)//configuration[instrument[focalInstrument=$instruments or starts-with(focalInstrument, $instruments || '_')]]//version , ",")
                    return
                    (
                        local:param($votable, "INSTRUMENT", $instruments),
                        local:param($votable, "INTERFEROMETER", $interferometer),
                        local:param($votable, "PERIOD", $interferometer||" "||$period),
                        local:param($votable, "CONFIGURATIONS", $stations),
                        local:param($votable, "OPERATION", "NEW"), (: ADD do not change config :)
                        ()
                    )
                else
                    ()
        else
            ()

        return 
            if(exists($params))
            then
                let $resource := $votable/*:RESOURCE
                return
                    element {QName(namespace-uri($votable), name($votable))} 
                        {
                            $votable/@*, 
                            element {QName(namespace-uri($resource), name($resource))} {$resource/@*, $params, $resource/*}
                        } 
            else
                $votable
    } catch * {
        response:set-status-code(400),
        <error> Error: { $err:code } - { $err:description } </error>
    }
    
return (
    response:set-header('Content-Disposition', 'attachment; filename="' || 'oidb-votable.xml' || '"'),
    $response
)
