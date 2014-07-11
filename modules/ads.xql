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
 : Add the description of an article to the model for children of node.
 : 
 : It expects an entry named 'bibcode' in the current model.
 : 
 : @param $node
 : @param $model
 : @return a new model
 :)
declare
    %templates:wrap
function ads:article($node as node(), $model as map(*)) as map(*) {
    let $bibcode := map:get($model, 'bibcode')
    (: TODO check returned record :)
    let $record := jmmc-ads:get-record($bibcode)

    return map {
        'bibcode'  := $bibcode,
        'title'    := jmmc-ads:get-title($record),
        'authors'  := jmmc-ads:get-authors($record),
        'pubdate'  := jmmc-ads:get-pub-date($record),
        'keywords' := jmmc-ads:get-keywords($record),
        'ads-url'  := ads:abstract-url($bibcode)
    }
};
