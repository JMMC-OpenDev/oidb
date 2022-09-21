xquery version "3.0";

(:module namespace rss="http://apps.jmmc.fr/exist/apps/oidb/rss";:)

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "modules/config.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "modules/app.xql";
import module namespace rss="http://apps.jmmc.fr/exist/apps/oidb/rss" at "modules/rss.xqm";

(:declare option exist:serialize "method=xml media-type=application/rss+xml";:)

(: TODO move back to 20 when it will be in production :)
let $max := number(request:get-parameter("max", 20))
let $rootURL := app:fix-relative-url("/")

return
    <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
            <atom:link href="{$rootURL}/rss" rel="self" type="application/rss+xml" />
            <title>RSS - {config:app-title(<e/>,map {})} </title>
            <link>{$rootURL}</link>
            <description></description>
            {
                rss:rssItems($max)
            }
        </channel>
    </rss>
