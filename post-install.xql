xquery version "3.0";

(: The following external variables are set by the repo:deploy function :)

(: file path pointing to the exist installation directory :)
declare variable $home external;
(: path to the directory containing the unpacked .xar package :)
declare variable $dir external;
(: the target collection into which the app is deployed :)
declare variable $target external;

(:~
 : Apply set of permissions to a resource.
 : 
 : If any of the permission items is false or unspecified, the respective 
 : permission of the resource is not modified.
 : 
 : @param $path the path to the resource to modify (relative to package root)
 : @param $perms a sequence of user, group and mods to set
 : @return empty
 :)
declare function local:set-permissions($path as xs:string, $perms as item()*)  {
    let $uri := xs:anyURI($path)
    return (
        let $user := $perms[1]
        return if ($user)  then sm:chown($uri, $user) else (),
        let $group := $perms[2]
        return if ($group) then sm:chgrp($uri, $group) else (),
        let $mod := $perms[3]
        return if ($mod)   then sm:chmod($uri, $mod) else ()
    )
};

(: set of permissions to require oidb or jmmc admin credentials :)
let $oidb-credentials := ( false(), 'oidb', 'rwxr-x---' )

(: set of permissions to require oidb admin credentials and execute as dba :)
let $oidb-credentials-dba := ( 'admin', 'oidb', 'rwsr-x---' )
(: FIXME : eval is not working anymore since 5.2? even if logged user get perms to read the content :)
let $oidb-credentials-dba := ( 'admin', 'oidb', 'rwsr-xr-x' )

let $jmmc-credentials-dba := ( 'admin', 'jmmc', 'rwsr-xr-x' )
let $guest-credentials-rw := ( 'guest', 'oidb', 'rw-rw-rw-' )

(: check some cache files :)
let $doc := doc($target || '-data/tmp/tap-cache.xml')
let $doc := if($doc/cache) then $doc else doc(xmldb:store($target|| '-data/tmp', 'tap-cache.xml', <cache/>))

(: restrict execution of XQuery modules :)

let $perms := map {
    $target || '/' || 'modules/assert.xql'       : $jmmc-credentials-dba,
    $target || '/' || 'modules/schedule-job.xql' : $oidb-credentials-dba,
    $target || '/' || 'modules/update-doc.xql'   : $oidb-credentials,
    $target || '/' || 'modules/upload-chara.xql' : $oidb-credentials,
    $target || '/' || 'modules/upload-vega.xql'  : $oidb-credentials,
    $target || '/' || 'modules/upload-obsportal.xql'  : $oidb-credentials,
    $target || '/' || 'modules/upload-eso.xql'  : $oidb-credentials,
    $target || '/' || 'tests.xml'  : $guest-credentials-rw,
    $target || '-data/' || 'tmp/tap-cache.xml'  : $guest-credentials-rw
}

return map:for-each($perms, local:set-permissions(?, ?))
