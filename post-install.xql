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
declare function local:set-permissions($path as xs:string, $perms as item()*) as empty() {
    let $uri := xs:anyURI($target || '/' || $path)
    return (
        let $user := $perms[1]
        return if ($user)  then sm:chown($uri, $user) else (),
        let $group := $perms[2]
        return if ($group) then sm:chgrp($uri, $group) else (),
        let $mod := $perms[3]
        return if ($mod)   then sm:chmod($uri, $mod) else ()
    )
};

(: set of permissions to require oidb admin credentials :)
let $oidb-credentials := ( false(), 'oidb', 'rwxr-x---' )

(: set of permissions to require oidb admin credentials and execute as dba :)
let $oidb-credentials-dba := ( 'admin', 'oidb', 'rwsr-x---' )

(: restrict execution of XQuery modules :)
let $perms := map {
    'modules/schedule-job.xql' := $oidb-credentials-dba,
    'modules/update-doc.xql'   := $oidb-credentials,
    'modules/upload-chara.xql' := $oidb-credentials,
    'modules/upload-vega.xql'  := $oidb-credentials
}

return map:for-each-entry($perms, local:set-permissions(?, ?))
