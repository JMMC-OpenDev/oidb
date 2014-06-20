xquery version "3.0";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "modules/config.xqm";

let $cat := request:get-parameter("cat", "facilities")
let $col := $config:app-root||"/resources/images/vignettes/"||$cat

(: TODO read content of collection and use random index on this collection :)
let $filename := util:random(9)||".png"

let $icon := util:binary-doc($col||"/"||$filename)
return
    (: response:stream-binary(image:crop($icon, (0,0,130,300),"image/png"), "image/png", ()) :)
    response:stream-binary($icon, "image/png", ())