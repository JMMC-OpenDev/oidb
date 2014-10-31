xquery version "3.0";

(:~
 : This module contains functions for templating articles identified by bibcodes.
 :)
module namespace ads="http://apps.jmmc.fr/exist/apps/oidb/ads";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers" at "templates-helpers.xql";

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
 : Add article description from ADS to model from bibcode.
 : 
 : The bibcode to search is taken from the 'bibcode' key of the current model 
 : or from a 'bibcode' HTTP request parameter.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @return a new model with article description
 :)
declare
    %templates:wrap
function ads:article($node as node(), $model as map(*)) as map(*)? {
    let $bibcode := if (map:contains($model, 'bibcode')) then map:get($model, 'bibcode') else request:get-parameter('bibcode', false())
    let $record := jmmc-ads:get-record($bibcode)
    
    return map { 'article' :=
        map:new((
            map:entry('bibcode', $bibcode),
            if ($record) then
                (: turn record into model entries :)
                map {
                    'title'    := jmmc-ads:get-title($record),
                    'authors'  := jmmc-ads:get-authors($record),
                    'pubdate'  := jmmc-ads:get-pub-date($record),
                    'keywords' := jmmc-ads:get-keywords($record),
                    'ads-url'  := ads:abstract-url($bibcode)
                }
            else
                (: unknown article, return only bibcode in model :)
                ()
        ))
    }
};
