xquery version "3.0";

(:~
 : This module contains functions for templating VizieR catalogs.
 :)
module namespace vizier="http://apps.jmmc.fr/exist/apps/oidb/vizier";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace flash="http://apps.jmmc.fr/exist/apps/oidb/flash" at "flash.xqm";
import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";

import module namespace jmmc-vizier="http://exist.jmmc.fr/jmmc-resources/vizier";

declare
    %templates:wrap
function vizier:assert-empty-collection($node as node(), $model as map(*), $catalog as xs:string?) as map(*) {
    let $catalog := normalize-space($catalog)
    return 
    if( collection:retrieve($catalog||"") ) then 
        (
            flash:error(<span xmlns="http://www.w3.org/1999/xhtml"><strong>Error!</strong>&#160;{ 'Catalog ' || $catalog || ' already exists.' }</span>),
            (: back to submit start page :)
            response:redirect-to(xs:anyURI('submit.html'))
        )
    else
        map:new()
};

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
    let $id := normalize-space(request:get-parameter('catalog', ''))
    let $readme := try {
            jmmc-vizier:catalog($id)
        } catch * {
            flash:error(
                let $msg := if ($err:code = 'jmmc-vizier:error') then
                    $err:description
                else
                    'Failed to retrieve description for catalog ' || $id || '. See log for details.'
                return <span xmlns="http://www.w3.org/1999/xhtml"><strong>Error!</strong>&#160;{ $msg }</span>),
            (: back to submit start page :)
            response:redirect-to(xs:anyURI('submit.html')), ''
        }
    return map {
        'source'        := 'http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat=' || encode-for-uri($id),
        'id'            := $id,
        'name'          := $id,
        'title'         := jmmc-vizier:catalog-title($readme),
        'description'   := jmmc-vizier:catalog-description($readme),
        'last-modified' := jmmc-vizier:catalog-date($readme),
        'bibcodes'      := jmmc-vizier:catalog-bibcodes($readme),
        'datapi'        := jmmc-vizier:catalog-creator($readme)
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
    let $id := normalize-space(request:get-parameter('catalog', ''))
    return map {
        'oifits' := jmmc-vizier:catalog-fits($id),
        'skip-quality-level-selector' := true()
    }
};
