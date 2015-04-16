xquery version "3.0";

(:module namespace rss="http://apps.jmmc.fr/exist/apps/oidb/rss";:)

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "modules/config.xqm";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "modules/app.xql";

(:declare option exist:serialize "method=xml media-type=application/rss+xml";:)

(: TODO move back to 20 when it will be in production :)
let $max := number(request:get-parameter("max", 20))

return
    <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <channel>
            <title>RSS - {config:app-title(<e/>,map {})} </title>
            <link>{app:fix-relative-url("/")}</link>
            <description></description>
            {
                app:rssItems($max)
            }
        </channel>
    </rss>