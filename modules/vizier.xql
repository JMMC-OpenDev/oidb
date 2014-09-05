xquery version "3.0";

(:~
 : This module contains functions for templating VizieR catalogs.
 :)
module namespace vizier="http://apps.jmmc.fr/exist/apps/oidb/vizier";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";

import module namespace jmmc-vizier="http://exist.jmmc.fr/jmmc-resources/vizier";

(:~
 : Add a catalog description to the model for templating.
 : 
 : It takes the catalog ID from a 'catalog' HTTP parameter in the request.
 : 
 : If no catalog exists with the given ID, it requests a redirect to the
 : submission start page.
 : 
 : @param $node
 : @param $model
 : @return a model with description of VizieR catalog
 :)
declare
    %templates:wrap
function vizier:catalog-description($node as node(), $model as map(*)) as map(*) {
    let $id := request:get-parameter('catalog', '')
    (: TODO check id :)
    let $readme := try {
            jmmc-vizier:catalog($id)
        } catch * {
            (: back to submit start page :)
            (: TODO display status message :)
            response:redirect-to(resolve-uri('submit.html')), ''
        }
    return map {
        'source'        := 'http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat=' || encode-for-uri($id),
        'name'          := $id,
        'title'         := jmmc-vizier:catalog-title($readme),
        'description'   := jmmc-vizier:catalog-description($readme),
        'last-modified' := jmmc-vizier:catalog-date($readme),
        'bibcodes'      := jmmc-vizier:catalog-bibcodes($readme)
    }
};

(:~
 : Add the list of OIFITS URLs associated with catalog to the model for templating.
 : 
 : It expects an entry named 'catalog' with the catalog ID in the current model.
 : 
 : @param $node
 : @param $model
 : @return a model with URLs of OIFITS files for catalog
 :)
declare
    %templates:wrap
function vizier:catalog-files($node as node(), $model as map(*)) as map(*) {
    let $id := request:get-parameter('catalog', '')
    return map {
        'oifits' := jmmc-vizier:catalog-fits($id)
    }
};

(:~
 : Iterate over each OIFITS URL.
 : 
 : It expects a model entry named 'oifits' containing a sequence of OIFITS URL. 
 : Each time it sets an 'url' entry in the model for the URL of the current
 : OIFITS file.
 : 
 : @param $node  the current node with children to templatize.
 : @param $model the current model.
 : @return a sequence of template processed nodes, one for each OIFITS URL.
 :)
declare
function vizier:each-oifits($node as node(), $model as map(*)) as node()* {
    for $url in $model('oifits')
    (: Add the OIFITS URL to the current model and process nodes :)
    return templates:process($node/node(), map:new(($model, map:entry('url', $url))))
};
