xquery version "3.0";

import module namespace request="http://exist-db.org/xquery/request";

import module namespace login="http://apps.jmmc.fr/exist/apps/oidb/login" at "modules/login.xqm";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

if($exist:path eq '') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{concat(request:get-uri(), '/')}"/>
    </dispatch>
else if ($exist:path eq "/") then
    (: forward root path to index.xql :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="index.html"/>
    </dispatch>
else if ($exist:path eq "/submit.html") then
    (: require authentification for submitting new data :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        { 
            login:set-user(),
            if (request:get-attribute("user")) then
                (: user logged in, can proceeed to submit page :)
                ()
            else
                (: unknown user, log in first :)
                <forward url="{$exist:controller}/login.html"/>
        }
        <view>
            <forward url="{$exist:controller}/modules/view.xql">
                <set-attribute name="warning" value="true"/>
                <set-header name="Cache-Control" value="no-cache"/>
            </forward>
        </view>
    </dispatch>
else if (starts-with($exist:path, '/modules/upload-')) then (
    (: also protect the submit endpoints to prevent anonymous submit :)
    login:set-user(),
    if (request:get-attribute("user")) then
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
            <cache-control cache="yes"/>
        </dispatch>
    else
        (: unauthenticated direct access to endpoint :)
        <response>
            <error>Authentication required</error>
        </response>
    )
else if (ends-with($exist:resource, ".html")) then
    (: the html page is run through view.xql to expand templates :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        {
            (: user may have signed out :)
            login:set-user()
        }
        <view>
            <forward url="{$exist:controller}/modules/view.xql">
                <!-- hide prototype warning on the feedback page -->
                <set-attribute name="warning" value="{ if ($exist:resource = "feedback.html") then "" else true() }"/>
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
else if (starts-with($exist:path, "/typeahead")) then
    (: forward to autocomplete for data source of typeahead enabled fields :)
    (: /typeahead/xxx?search=yy for suggestions like yy on column xxx of database :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/modules/autocomplete.xql">
            <add-parameter name="column" value="{$exist:resource}"/>
        </forward>
    </dispatch>
else
    (: everything else is passed through :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <cache-control cache="yes"/>
    </dispatch>
