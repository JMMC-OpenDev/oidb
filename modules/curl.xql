xquery version "3.0";

(:~
 : Return a curl config file to download the OIFits files from a selection.
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
                        'distinct'
                    )
                )
                (: run the ADQL SELECT :)
                let $data := tap:execute($query)

                return string-join((
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
                    "# A contact is given for every private files",                    
                    '',
                    let $fields := data($data//*:TABLE/*:FIELD/@name)
                    let $access-url-idx   := index-of($fields, 'access_url')
                    let $data-rights-idx  := index-of($fields, 'data_rights')
                    let $obs-release-date := index-of($fields, 'obs_release_date')
                    let $obs-creator-name := index-of($fields, 'obs_creator_name')

                    for $row in $data//*:TR
                    let $url := app:fix-relative-url($row/*:TD[$access-url-idx]/text()) 
                    where starts-with($url, 'http')
                    group by $url-group:=$url
                    return (
                        (: grouped tuples so there may be more than a single row, pick first for now:)
                        let $row := $row[1]
                        let $public := app:public-status(
                            $row/*:TD[$data-rights-idx],
                            $row/*:TD[$obs-release-date])
                        return if ($public) then 
                            ()
                        else
                            '# Note: the following file is not public, contact ' || $row/*:TD[$obs-creator-name] || ' for availability',
                        concat('url = "', $url-group),
                        'remote-name'
                    )
                ), '&#xa;')
            } catch * {
                '# Error: ' || $err:description
            }
(:        }:)
(:    </collection>:)
    
return (
    response:set-header('Content-Disposition', 'attachment; filename="' || 'oidb-curl.config' || '"'),
    $response
)
