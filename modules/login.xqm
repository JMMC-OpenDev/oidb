xquery version "3.0";

module namespace login="http://apps.jmmc.fr/exist/apps/oidb/login";

import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth" ;

(:~
 : Forget about user authentication, removing the current HTTP session.
 :)
declare %private function login:clear-credentials() {
    session:invalidate()
};

(:~
 : Try authenticating the user with the given password.
 : 
 : @param $user
 : @param $password
 : @return ignore
 :)
declare %private function login:create-login($user as xs:string, $password as xs:string) as empty() {
    (: use the JMMC authentication system/database :)
    if (jmmc-auth:checkPassword($user, $password)) then (
        (: persist authentication through session :)
        session:set-attribute("user", $user),
        (: set attribute for next action in controller :)
        request:set-attribute("user", $user))
    else
        (: failed to authenticate: unknown user or bad password :)
        ()
};

(:~
 : Check if the user is already logged in.
 : 
 : @return ignore
 :)
declare %private function login:get-credentials() {
    (: empty sequence if not logged in:)
    let $user := session:get-attribute("user")
    return (
        request:set-attribute("user", $user)
    )
};

(:~
 : Test authentication status of the user.
 : 
 : If the user is not logged in, it should pass it username and password as
 : parameters.
 : If the user is logged in, it can be logged out with passing a logout
 : request parameter.
 : 
 : The login status is transmitted to the next action with the controller
 : rule by a request parameter.
 : 
 : @return ignore
 :)
declare function login:set-user() as empty() {
    let $user     := request:get-parameter("user", ())
    let $password := request:get-parameter("password", ())
    let $logout   := request:get-parameter("logout", ())

    return
        if ($logout) then
            (: logout request :)
            login:clear-credentials()
        else if ($user) then
            (: login request :)
            login:create-login($user, $password)
        else
            (: already logged in? :)
            login:get-credentials()
};

(:~
 : Retrieve info from JMMC authentication database for the current
 : user.
 : 
 : @return account data for the current user
 :)
declare %private function login:user-info() as node()+ {
    let $user := session:get-attribute("user")
    return jmmc-auth:getInfo($user)
};

(:~
 : Return the email address of the current user, if any.
 : 
 : @return an email address or nothing if no user
 :)
declare function login:user-email() as xs:string? {
    (: using email to ask for the email! :)
    login:user-info()//email
};

(:~
 : Return the name of the current user, if any.
 : 
 : @return thename of the user or nothing if no user
 :)
declare function login:user-name() as xs:string? {
    login:user-info()//name
};
