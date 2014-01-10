xquery version "3.0";

(:~
 : Save metadata from OIFits files whose URL have been passed as parameter.
 :
 : Each file is processed by OIFitsViewer to extract metadata.
 : 
 : It returns a <response> fragment with the status of the operation for each
 : URL (<success> or <error>).
 :)

import module namespace tap="http://apps.jmmc.fr/exist/apps/oidb/tap" at "tap.xqm";

(: TODO: distinct access_url ? :)
declare variable $query := "SELECT t.access_url, t.data_rights, t.obs_release_date FROM oidata2 AS t";

declare function local:public-status($data_rights as xs:string?, $release_date as xs:string?) {
    switch ($data_rights)
        case "public"
            (: data is explicitly public :)
            return true()
        (: TODO: difference between secure and proprietary? :)
        default
            (: or wait until release_date :)
            return if ($release_date != '') then
                (: build a datetime from a SQL timestamp :)
                let $release_date := dateTime(
                    xs:date(substring-before($release_date, " ")),
                    xs:time(substring-after($release_date, " ")))
                (: compare release date to current time :)
                return if (current-dateTime() gt $release_date) then true() else false()
            else 
                (: never gonna be public :)
                false()
};

declare option exist:serialize "method=text media-type=text/plain omit-xml-declaration=yes";

let $collection := request:get-parameter("obs_collection", "", true())
let $data := tap:execute(concat($query," WHERE t.obs_collection='", $collection, "'"), true())
for $access_url in distinct-values($data[.//tr[not(local:public-status(data(./td[@colname="data_rights"]), data(./td[@colname="release_date"])))]]//td[@colname="access_url"])
return
    <p>
# obs_release_date: { $data//tr[./td[@colname="access_url"]=$access_url][1]/td[@colname="obs_release_date"]/text() }
&lt;Files "{ tokenize($access_url, "/")[last()] }"&gt;
    Allow from all
    Satisfy any
&lt;/Files&gt;

    </p>
