xquery version "3.0";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "modules/config.xqm";

try {
    let $cat := request:get-parameter("cat", "facilities")
    let $col := $config:app-root||"/resources/images/vignettes/"||$cat
    
    (: first get all the files in the collection :)
    let $all-files := xmldb:get-child-resources($col)
    
    (: now just get the files with known image file type extensions :)
    let $image-files :=
       for $file in $all-files[
          ends-with(.,'.png') or 
          ends-with(.,'.jpg') or 
          ends-with(.,'.tiff') or 
          ends-with(.,'.gif')]
       return $file
    
    let $filename  := $col||"/"||$image-files[1+util:random(count($image-files))][1]
    let $extension := tokenize($filename, ".")[last()]
    
    let $icon := util:binary-doc($filename)
    return
        (: response:stream-binary(image:crop($icon, (0,0,130,300),"image/png"), "image/png", ()) :)
        response:stream-binary($icon, "image/"||$extension, ())
} catch * {
        let $log := util:log("warn", $err:description)
        return
        response:stream-binary(util:binary-doc($config:app-root||"/icon.png"), "image/png", ())
}
