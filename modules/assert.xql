xquery version "3.0";

(:~
 : This module launches xquery with dba priviledges and perform following operations :
 : - set primary group to every user ( TODO try to avoid one test per request )
 : TODO
 : - check (and fix) permissions on oifits/staging, comments, collection and all other user writable resources
 : 
 : @note
 : This script must be run as database administrator as requested by next operations (must have sticky bit).
 :)

import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "app.xql";


if(app:user-allowed()) then
(:    assert that user has jmmc has primary group::)
(:    help to workarround write permission in apps/oidb-data/oifits/staging:)
    let $user := app:user-name()
    let $group  := sm:get-user-primary-group($user)
    return if ($group = 'jmmc')
        then 
            ()
        else
            let $op1  := sm:set-user-primary-group($user, 'jmmc')
            let $op2  := util:log("info", "fix jmmc as primary group for "|| app:user-name())
            return ()
else
    ()
