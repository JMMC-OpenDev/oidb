xquery version "3.0";

(:~
 : Return a curl config file to download the OIFits files from a selection.
 : TODO add datapi if given for associated contact
 : TODO include in every file comment the creator and datapi 
 :)

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "application/text";

import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";
import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

let $response :=
(:    <collection> :)
(:        {:)
            try {
                let $columns := ( 'access_url', 'data_rights', 'obs_release_date', 'obs_creator_name' )
                (: tweak the query string to build a custom ADQL query :)
                let $query := adql:build-query(
                    (
                        (: remove pagination and set of columns :)
                        adql:clear-pagination(
                            adql:clear-select-list(
                                (: FIXME should not have to clear order :)
                                adql:clear-order(
                                    adql:split-query-string()))),
                        (: select columns of interest :)
                        for $c in $columns return 'col=' || $c,
                        'caliblevel=1,2,3', (: filter out L0 :)
                        'distinct'
                    )
                )
                (: run the ADQL SELECT :)
                let $data := tap:execute($query)
                let $lines := (
                    '# Use this file as a config file for curl to retrieve data from the OiDB portal.',
                    '# Example       : curl --config <file>',
                    '#',
                    "# Collected from http://oidb.jmmc.fr on "|| current-dateTime(),
                    '# ADQL query    : ' || $query ,     
(:                    '# tap response  : ' || serialize($data) ,     :)
(:                    '# Nb records    : ' || count($data//*:TR) ,     :)
                    '#',
                    '# To retrieve private data protected by password, you may add --netrc option to curl and fill ',
                    '# $HOME/.netrc file with following template (see man curl / man netrc for more details) :',
                    '# machine <host.domain.net> login <myself> password <secret>',
                    '#',
                    "# A contact is given for every private files if any",                    
                    '',
                    let $fields           := data($data//*:TABLE/*:FIELD/@name)
                    let $access-url-idx   := index-of($fields, 'access_url')
                    let $data-rights-idx  := index-of($fields, 'data_rights')
                    let $obs-release-date := index-of($fields, 'obs_release_date')
                    let $obs-creator-name := index-of($fields, 'obs_creator_name')
                    let $datapi           := index-of($fields, 'datapi')

                    for $row in $data//*:TR
                    (: get only first url of the group and force it to be a string to avoid empty param :)
                    let $url := app:fix-relative-url(string(($row/*:TD[$access-url-idx])[1]))
                    where starts-with($url[1], 'http')
                    group by $url-group:=$url
                    return (
                        (: grouped tuples so there may be more than a single row, pick first for now:)
                        let $row := $row[1]
(:                        let $public := app:public-status( ($row/*:TD[$data-rights-idx])[1][1], ($row/*:TD[$obs-release-date])[1][1]):)
                        let $public := app:public-status( "public", ())
                        return if ($public) then 
                            ()
                        else
                            '# Note: the following file is not public, contact ' || $row/*:TD[$datapi] || ' or ' || $row/*:TD[$obs-creator-name] || ' for availability',
                        concat('url = ', $url-group),
                        'remote-name'
                    ))
                return string-join($lines, '&#xa;')
            } catch * {
                '# Sorry an error occured: ' || $err:description || "&#10;#&#10;#&#10;# Please contact the user support"
            }
(:        }:)
(:    </collection>:)
    
return (
    response:set-header('Content-Disposition', 'attachment; filename="' || 'oidb-curl.config' || '"'),
    $response
)
