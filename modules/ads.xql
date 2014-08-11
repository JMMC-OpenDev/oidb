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
 : Return a description of an article from its ADS record as map for templating.
 : 
 : @param $bibcode the bibcode to search
 : @return a map as model for templating
 :)
declare %private function ads:article($bibcode as xs:string) as map(*)? {
    map:new((
        map:entry('bibcode', $bibcode),
        let $record := jmmc-ads:get-record($bibcode)
        return if ($record) then
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
            ()))
};

(:~
 : Add article descriptions to model from bibcodes.
 : 
 : It creates an entry with name 'articles' and value as sequence of
 : description of articles.
 : 
 : @param $node  the current node
 : @param $model the current model
 : @param $key   the name of the entry containing the bibcodes to search.
 : @return a new model with article descriptions
 :)
declare function ads:articles($node as node(), $model as map(*), $key as xs:string) as map(*) {
    let $bibcodes := helpers:get($model, $key)
    return map { 'articles' :=
        for $bibcode in $bibcodes
        return ads:article($bibcode)
    }
};
