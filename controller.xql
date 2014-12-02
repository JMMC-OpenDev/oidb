xquery version "3.0";

import module namespace request="http://exist-db.org/xquery/request";
import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "modules/config.xqm";
import module namespace restxq="http://exist-db.org/xquery/restxq" at "modules/restxq.xql";
import module namespace app="http://apps.jmmc.fr/exist/apps/oidb/templates" at "modules/app.xql";
import module namespace adql="http://apps.jmmc.fr/exist/apps/oidb/adql" at "modules/adql.xql";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

declare variable $domain := "fr.jmmc.oidb.login";
declare variable $login := function () { login:set-user($domain, (), false()) };

declare function local:user-allowed() as xs:boolean {
    (
        request:get-attribute($domain || '.user') and
        request:get-attribute($domain || '.user') != "guest"
    )
};

let $store-res-name := request:set-attribute("exist:path", $exist:path)
return 
if($exist:path eq '') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{concat(request:get-uri(), '/')}"/>
    </dispatch>
else if ($exist:path eq "/") then
    (: forward root path to index.xql :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="index.html"/>
    </dispatch>
else if ($exist:path eq "/submit.html" or $exist:path eq "/backoffice.html" or $exist:path eq "/collection-vizier.html") then
    (: require authentification for submitting new data :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        { 
            $login(),
            if (local:user-allowed()) then
                (: user logged in, can proceeed to submit page :)
                ()
            else
                (: unknown user, log in first :)
                <forward url="{$exist:controller}/login.html"/>
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
else if ($exist:path eq "/search.html" and request:get-method() = 'POST') then
    (: interception of POST requests from search page :)
    (: serialize from form elements and redirect (303 See Other) :)
    let $query-string := adql:to-query-string(app:serialize-query-string())
    let $location := if($query-string = '') then '.' || $exist:path else '.' || $exist:path || '?' || $query-string
    return (
        response:set-status-code(303),
        response:set-header('Location', $location)
    )

else if (starts-with($exist:path, '/restxq/oidb')) then
    let $login := $login()
    let $path := substring-after($exist:path, '/restxq')
    let $prefix := tokenize($exist:path, '[^a-zA-Z]')[4]
    let $module-uri := 'http://apps.jmmc.fr/exist/apps/oidb/restxq/' || $prefix
    let $location := 'modules/rest/' || $prefix || '.xqm'
    return if (util:binary-doc-available($config:app-root || '/' || $location)) then
        (
            util:import-module($module-uri, $prefix, $location),
            restxq:process($path, util:list-functions($module-uri))
        )
    else
        (
            response:set-status-code(400), (: Bad Request :)
            <response>Unknown RESTXQ path</response>
        )

else if (ends-with($exist:resource, ".html")) then
    (: the html page is run through view.xql to expand templates :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        {
            (: user may have signed out :)
            $login()
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
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <cache-control cache="yes"/>
    </dispatch>
