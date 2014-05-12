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
                        adql:split-query-string()[not(starts-with(., ('page', 'perpage', 'col=')))],
                        (: select columns of interest :)
                        for $c in $columns return 'col=' || $c,
                        'distinct'
                    )
                )
                (: run the ADQL SELECT :)
                let $data := tap:execute($query, true())

                return string-join((
                    '# Use this file as a config file for curl to retrieve data from the OiDB portal.',
                    '# Example       : curl -f --config <file>',
                    '#',
                    "# Collected from http://oidb.jmmc.fr on "|| current-dateTime(),
                    '# ADQL query    : ' || $query ,                    
                    '#',
                    '# To retrieve private data protected by password, you may add --netrc option to curl and fill ',
                    '# $HOME/.netrc file with following template (see man curl / man netrc for more details) :',
                    '# machine <host.domain.net> login <myself> password <secret>',
                    '#',
                    "# A contact is given for every private files",                    
                    '',
                    for $url in distinct-values($data//td[@colname='access_url' and starts-with(., 'http')])
                    return (
                        (: public status of the url :)
                        let $row := $data//tr[td[@colname="access_url"]=$url][1]
                        let $public := app:public-status(
                            $row/td[@colname="data_rights"]/text(),
                            $row/td[@colname="obs_release_date"]/text())
                        return if ($public) then 
                            ()
                        else
                            '# Note: the following file is not public, contact ' || $row/td[@colname="obs_creator_name"] || ' for availability',
                        concat('url = "', $url),
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
