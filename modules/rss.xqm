xquery version "3.0";

module namespace rss="http://apps.jmmc.fr/exist/apps/oidb/rss";



import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "adql.xqm";
import module namespace comments="http://apps.jmmc.fr/exist/apps/oidb/comments" at "comments.xql";
import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";

import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";


declare function rss:rssItems($max as xs:integer) as node()* {
    let $latest-granules := adql:build-query(( 'order=subdate','order=^id', 'limit='||$max ))
    let $votable         := tap:retrieve-or-execute($latest-granules)
    let $data            := app:transform-votable($votable)

    let $granule-items :=
        for $rows in $data//tr[td]
            group by $url:=$rows/td[@colname="access_url"]
            order by ($rows/td[@colname="subdate"])[1] descending

            return
            let $first-row := ($rows)[1]
            let $date := data(jmmc-dateutil:ISO8601toRFC822(xs:dateTime($first-row/td[@colname="subdate"])))
            let $first-id := $first-row/td[@colname="id"]
            let $link := app:fix-relative-url("/show.html?id="||$first-id)
            let $guid := $link
            let $summary :=
                <table border="1" class="table table-striped table-bordered table-hover">
                    {
                        let $columns := ("id", $app:main-metadata ,"obs_collection", "obs_creator_name", "quality_level")
                        return app:tr-cells($rows, $columns)
                    }
                </table>
            let $c := count($rows)
            let $authors := distinct-values($rows//td[@colname="datapi"])
(:            app:show-granule-summary(<a/>,  map {'granule' : $rows }, "granule"):)
            return
                <item xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <link>{$link}</link>
                    <guid>{$guid}</guid>
                    <title> {$c} last submitted granules</title>
                    <dc:creator>{$authors}</dc:creator>
                    <description>
                        {
                            serialize(
                                (
                                    <h2>Description:</h2>
                                    , <br/>
                                    , $summary
                                )
                            )
                        }
                    </description>
                    <pubDate>{$date}</pubDate>
                </item>

    let $last-comments := comments:last-comments($max)
    let $comment-items := for $c in $last-comments
        let $granule-id := $c/@granule-id
        let $link := app:fix-relative-url("/show.html?id="||$granule-id)
        let $guid := $link
        let $date   := data(jmmc-dateutil:ISO8601toRFC822($c/date))
        let $text   := data($c/text)
        let $author := data($c/author)

        return
                <item xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <link>{$link}</link>
                    <guid>{$guid}</guid>
                    <title> granule comment </title>
                    <dc:creator>{$author}</dc:creator>
                    <description>
                        {   (: content could remember the thread ... :)
                            serialize( <div><b>From {$author}</b> on {$date}:<br/> <em>{$text}</em></div> )
                        }
                    </description>
                    <pubDate>{$date}</pubDate>
                </item>


    return for $item in ($granule-items, $comment-items) order by $item/pubDate descending return $item
};
