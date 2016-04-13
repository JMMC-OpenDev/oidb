xquery version "3.0";

module namespace login="http://apps.jmmc.fr/exist/apps/oidb/login";

import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth" ;

(:~
 : Retrieve info from JMMC authentication database for the current
 : user.
 : 
 : @return account data for the current user
 :)
declare %private function login:user-info() as node()? {
    (: FIXME does not work with HTTP Basic Auth :)
    let $user := request:get-attribute("fr.jmmc.oidb.login.user")
    (: See bug 388: sm:id() in module throws error :)
    (: https://github.com/eXist-db/exist/issues/388 :)
    (: let $user := sm:id()//sm:real/sm:username/text() :)
    return jmmc-auth:get-info($user)
};

(:~
 : Return the email address of the current user, if any.
 : 
 : @return an email address or nothing if no user
 :)
declare function login:user-email() as xs:string? {
    (: using email to ask for the email! :)
    (login:user-info()//email)[last()]
};

(:~
 : Return the name of the current user, if any.
 : 
 : @return thename of the user or nothing if no user
 :)
declare function login:user-name() as xs:string? {
    login:user-info()//name
};
