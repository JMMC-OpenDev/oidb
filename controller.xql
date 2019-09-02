xquery version "3.0";

import module namespace request="http://exist-db.org/xquery/request";
import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "modules/config.xqm";
import module namespace restxq="http://exist-db.org/xquery/restxq" at "modules/restxq.xql";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "modules/app.xql";
import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "modules/adql.xql";
import module namespace flash="http://apps.jmmc.fr/exist/apps/oidb/flash" at "modules/flash.xqm";

import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

declare variable $domain := "fr.jmmc.oidb.login";
(: call login function before any use of protected code         :)
(: app:user-admin() and app:user-allowed() uses this attributes :)
(: TODO check if we can move/hide it in app module :) 
declare variable $login := function () {
    let $set-user := login:set-user($domain, (), false())
    (: FIXME use sm:id() instead when upstream bug #388 is fixed :)
    let $user := (request:get-attribute($domain || '.user'), data(sm:id()//*:username))[1]
    let $superuser := request:set-attribute($domain || '.superuser', $user and jmmc-auth:check-credential($user, 'oidb'))
    let $assert := util:eval(xs:anyURI('./modules/assert.xql'))
    return ()
};

declare variable $cookie-agreement := 
    let $cookie-name := "cookie-agreement" (: TODO move as config constant :)
    return if ( exists(request:get-cookie-value($cookie-name))) 
        then
            request:set-attribute($cookie-name, "true") 
        else if( exists(request:get-parameter('i_agree_to_conditions', ())) ) 
        then 
            (
                response:set-cookie($cookie-name,util:uuid(), xs:yearMonthDuration('P10Y'), false()),
                request:set-attribute($cookie-name, "true") 
            )
        else 
            ();
            
(: we use following variable to simplifiy double proxy case (traefik on top of haproxy)... :)
let $exist-path := replace($exist:path, "//", "/")
            
            
let $store-res-name := request:set-attribute("exist:path", $exist:path)
return 
if($exist:path eq '') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{concat(request:get-uri(), '/')}"/>
    </dispatch>
else if($exist:path eq '/rss') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="rss.xql"/>
    </dispatch>
else if ($exist:path eq "/") then
    (: redirect root path to index.html :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="index.html"/>
    </dispatch>
else if ($exist:path eq '//') then
    (: Special case for two level proxies :)
    (: forward root path to /index.html :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/index.html"/>
        <view>
            <forward url="{$exist:controller}/modules/view.xql"/>
        </view>
    </dispatch>
else if ($exist:path eq "/search.html" and request:get-method() = 'POST') then
    (: interception of POST requests from search page :)
    (: serialize from form elements and redirect (303 See Other) :)
    let $query-string := adql:to-query-string(app:serialize-query-string())
    let $location := if($query-string = '') then '.' || $exist:path else '.' || $exist:path || '?' || $query-string
    return (
        response:set-status-code(303),
        response:set-header('Location', $location)
    )

else if (starts-with($exist-path, '/restxq/oidb')) then
    let $login := $login()
    let $path := substring-after($exist-path, '/restxq')
    let $prefix := tokenize($exist-path, '[^a-zA-Z]')[4]
    let $module-uri := 'http://apps.jmmc.fr/exist/apps/oidb/restxq/' || $prefix
    let $location := 'modules/rest/' || $prefix || '.xqm'
    return if (util:binary-doc-available($config:app-root || '/' || $location)) then
        (
            if (starts-with($exist-path, "/restxq/oidb/user") and not(app:user-admin()))
                then
                (
            response:set-status-code(403), (: Forbidden :)
            <response>your are missing the superadmin permission</response>
        )    
            else 
                (
                    util:import-module($module-uri, $prefix, $location),
                    restxq:process($path, util:list-functions($module-uri))
                )
        )
    else
        (
            response:set-status-code(400), (: Bad Request :)
            <response>Unknown RESTXQ path</response>
        )

(:  login of user via AJAX :)
else if ($exist:resource eq 'login') then
    let $login := $login()
    return <status> {
        if (app:user-allowed()) then
            'success'
        else
            ( response:set-status-code(401), 'fail' )
    } </status>

else if (ends-with($exist:resource, ".html")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        {
            $login(),
            if ($exist:path = ( '/submit.html', '/upload-vizier.html', '/upload.html', '/backoffice.html' )) then
                if (not(app:user-allowed())) then
                    (: unknown user, log in first :)
                    <forward url="{$exist:controller}/login.html"/>
                else if ($exist:path = '/backoffice.html' and not(app:user-admin())) then
                    (
                        (: no credentials for the page :)
                        flash:error(<span xmlns="http://www.w3.org/1999/xhtml"><strong>Access denied!</strong> You are not authorized to access the requested page.</span>),
                        <redirect url="index.html"/>
                    )
                else
                    (: user logged in, can proceeed to page :)
                    ()
            else
                (: no authentication required :)
                if (request:get-parameter('logout', false())) then
                    (: user requested logout :)
                    (
                        session:create(), (: session was invalidated by logout :)
                        flash:info(<span xmlns="http://www.w3.org/1999/xhtml">You have successfully logged out.</span>)
                    )
                else
                    ()
        }
        <view>
            <forward url="{$exist:controller}/modules/view.xql">
                <set-header name="Cache-Control" value="no-cache, no-store, must-revalidate"/>
                <set-header name="Pragma" value="no-cache"/>
                <set-header name="Expires" value="0"/>
            </forward>
        </view>
		<error-handler>
			<forward url="{$exist:controller}/error-page.html" method="get"/>
			<forward url="{$exist:controller}/modules/view.xql"/>
		</error-handler>
    </dispatch>
(: Resource paths starting with $shared are loaded from the shared-resources app :)
else if (contains($exist:path, "/$shared/")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="/shared-resources/{substring-after($exist:path, '/$shared/')}">
            <set-header name="Cache-Control" value="max-age=3600, must-revalidate"/>
        </forward>
    </dispatch>
else
    (: everything else is passed through :)
    (
        response:set-header("debug-resource", $exist:resource),
        response:set-header("debug-path", $exist:path),
        response:set-header("debug-controller", $exist:controller),
        response:set-header("debug-uri", request:get-uri()),
        
        
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <cache-control cache="yes"/>
    </dispatch>
    )
