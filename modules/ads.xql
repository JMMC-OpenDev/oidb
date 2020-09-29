xquery version "3.0";

(:~
 : This module contains functions for templating articles identified by bibcodes.
 :)
module namespace ads="http://apps.jmmc.fr/exist/apps/oidb/ads";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers" at "templates-helpers.xql";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs";

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
    let $record := adsabs:get-records($bibcode)
    return map { 'article' :
        map:merge((
            map:entry('bibcode', $bibcode),
            if ($record) then
                (: turn record into model entries :)
                map {
                    'title'    : adsabs:get-title($record),
                    'authors'  : adsabs:get-authors($record),
                    'pubdate'  : adsabs:get-pub-date($record),
                    'keywords' : adsabs:get-keywords($record),
                    'ads-url'  : adsabs:get-link($bibcode, ())/@href
                }
            else
                (: unknown article, return only bibcode in model :)
                ()
        ))
    }
};
