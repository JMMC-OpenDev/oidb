xquery version "3.0";

(:~
 : This module contains functions for templating VizieR catalogs and use TAP access to synchronize L0 Eso obs log.
 :)
module namespace vizier="http://apps.jmmc.fr/exist/apps/oidb/vizier";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "config.xqm";
import module namespace flash="http://apps.jmmc.fr/exist/apps/oidb/flash" at "flash.xqm";
import module namespace collection="http://apps.jmmc.fr/exist/apps/oidb/collection" at "collection.xqm";

import module namespace jmmc-vizier="http://exist.jmmc.fr/jmmc-resources/vizier";
import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil";

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
        map:merge()
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
    let $description := jmmc-vizier:catalog-abstract($readme)
    let $description := if( string-length($description) < 10 ) then jmmc-vizier:catalog-description($readme) else $description
    return map {
        'source'        := 'http://cdsarc.u-strasbg.fr/viz-bin/Cat?cat=' || encode-for-uri($id),
        'id'            := $id,
        'name'          := $id,
        'title'         := jmmc-vizier:catalog-title($readme),
        'description'   := $description,
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


(:~
 : Turn a row observation from TAP Vizier into a metadata fragment for upload.
 : 
 : @param $row an observation 
 : @return a 'metadata' element for the observation
 :)
declare function vizier:l0-metadata($row as node(), $col-indexes as map(xs:string, xs:integer), $collection-id as xs:string) as node() {
    (:AirMass:? AirMass:)
    (:DataID:Dataset identification:)
    (:DEJ2000:Declination in mas (J2000):)
    (:Filter:Filter Path (4):)
    (:Grating:Grating Path (4):)
    (:Grism:Grism Path (4):)
    (:InstMode:Instrument mode (4):)
    (:InstrID:Instrument identification:)
    (:naxis1:? Detector size in X direction:)
    (:naxis2:? Detector size in Y direction:)
    (:ObsName:Observation name (3):)
    (:Obs:Observation start date (UT):)
    (:ObsTech:Observation technique (2):)
    (:ProgID:Program identification:)
    (:RAJ2000:Right Ascension in mas (J2000):)
    (:recno:Record number assigned by the VizieR team. Should Not be used for identification.:)
    (:Rel_date:Release date of data:)
    (:Slit:Slit Path (4):)
    (:Target:Target name (3):)
    (:TelID:? Telescope identification:)
    (:tExp:? Exposure time:)

    let $values := $row/*

    let $target-name   := $values[ map:get($col-indexes,"Target")  ]
    let $ra            := $values[ map:get($col-indexes,"RAJ2000") ]
    let $dec           := $values[ map:get($col-indexes,"DEJ2000") ]
    
    let $ut            := $values[ map:get($col-indexes,"Obs") ]
    let $t-min         := jmmc-dateutil:UTtoMJD($ut,())
    let $t-exp          := $values[ map:get($col-indexes,"tExp") ]
    let $t-exp          := if(string-length($t-exp)>0) then $t-exp else 0
    let $t-max         := try {jmmc-dateutil:UTtoMJD($ut + $t-exp ,())} catch * { $t-min }
    let $release-date  := jmmc-dateutil:JDtoISO8601( $values[ map:get($col-indexes,"Rel_date") ] )
    
    let $facility-name := "VLTI"
    let $prog-id       := $values[ map:get($col-indexes,"ProgID") ]
    let $obs-id        := $values[ map:get($col-indexes,"DataID") ]
    let $obs-creator   := "ESO"
    
    (:    let $data-pi       := if( exists($prog-id)) then jmmc-eso:get-pi-from-progid($prog-id) else ():)
    (: decided to be left blank on 2018-dec with XH :)
    let $data-pi       := ""
    let $bib-ref       := "" (: if( exists($prog-id)) then http://telbib.eso.org/api.php?programid= :)
    
    let $ins-name      := $values[ map:get($col-indexes,"InstrID") ]
(:    let $tel-conf    := "NOT USED in ObsCore schema" (: We could resolv TelId :):)
    
    let $ins-mode      :=  $values[ map:get($col-indexes,"InstMode") ]
    let $nb-channels   := -1 (: get it from InstMode x AsprocConf + Filter :)
    let $em-min        := 0 
    let $em-max        := 0
    
    return <metadata> {
        (: all entries are L0 :)
        <calib_level>0</calib_level>,
        <target_name>{ $target-name }</target_name>,
        <datapi>{ $data-pi }</datapi>,
        <obs_collection>{ $collection-id }</obs_collection>,
        <obs_creator_name>{ $obs-creator}</obs_creator_name>,
        <obs_release_date>{ $release-date}</obs_release_date>,
        <obs_id>{ $obs-id }</obs_id>,
        <progid>{ $prog-id }</progid>,
        <s_ra>  { $ra } </s_ra>,
        <s_dec> { $dec } </s_dec>,
        <t_min> { $t-min } </t_min>,
        <t_max> { $t-max } </t_max>,
        <t_exptime>{ $t-exp }</t_exptime>, (: FIXME :)
        <em_min>{ $em-min }</em_min>,
        <em_max>{ $em-max }</em_max>,
        <em_res_power>-1</em_res_power>, (: FIXME :)
        <facility_name>{$facility-name}</facility_name>,
        <instrument_name>{$ins-name}</instrument_name>,
        <instrument_mode>{ $ins-mode }</instrument_mode>,
        <nb_channels>{$nb-channels}</nb_channels>,
        (: FIXME  below :)
        (: nb_vis, nb_vis2 and nb_t3 left empty :)
        <data_rights>public</data_rights>,
        <access_url>-/-</access_url> (: FIXME no file :)
    } </metadata>
};


