xquery version "3.0";

(:~
 : This module contains functions for templating articles identified by bibcodes.
 :)
module namespace ads="http://apps.jmmc.fr/exist/apps/oidb/ads";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace jmmc-ads="http://exist.jmmc.fr/jmmc-resources/ads";

(:~
 : Return the URL of the ADS abstract page of given bibcode.
 : 
 : @param $bibcode the article bibcode
 : @return the abstract URL at ADS
 :)
declare %private function ads:abstract-url($bibcode as xs:string) as xs:string {
    'http://cdsads.u-strasbg.fr/cgi-bin/nph-bib_query?' || encode-for-uri($bibcode)
};

(:~
 : Render the current node and its children with article info.
 : 
 : It expects an entry named 'bibcode' in the current model. The data from the 
 : abstract record are added to the model for templating children node.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @return the templatized current node or nothing if the bibcode is not linked
 : to any abstract at ADS.
 :)
declare function ads:article($node as node(), $model as map(*)) as node()? {
    let $bibcode := map:get($model, 'bibcode')
    let $record := jmmc-ads:get-record($bibcode)
    return element { node-name($node) } {
        $node/@*,
        if ($record) then
            let $record-model := map {
                'bibcode'  := $bibcode,
                'title'    := jmmc-ads:get-title($record),
                'authors'  := jmmc-ads:get-authors($record),
                'pubdate'  := jmmc-ads:get-pub-date($record),
                'keywords' := jmmc-ads:get-keywords($record),
                'ads-url'  := ads:abstract-url($bibcode)
            }
            (: templatize child nodes with article data :)
            return templates:process($node/node(), map:new(( $model, $record-model )))
        else
            '&#160;'
    }
};
