xquery version "3.0";

(:~
 : This module provides a set of helper functions for HTML templating
 : that are not part of the upstream templates module.
 :)
module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers";

import module namespace templates="http://exist-db.org/xquery/templates";

(:~
 : Evaluate and output the block if the model has a given property.
 : 
 : @param $node
 : @param $model current model
 : @param $key   key to search in the model
 : @return the processed block if the model as the property, nothing otherwise.
 :)
declare
    %templates:wrap
function helpers:if-model-key($node as node(), $model as map(*), $key as xs:string) {
    if (map:contains($model, $key)) then
        templates:process($node/node(), $model)
    else
        ()
};

(:~
 : Return the value of the given key in the model as text.
 : 
 : @param $node  a placeholder for text
 : @param $model the current model
 : @param $key   the key to search in the model
 : @return the value for key in model as string or nothing
 :)
declare function helpers:model-value($node as node(), $model as map(*), $key as xs:string) as xs:string {
    xs:string($model($key))
};

(:~
 : Add to the node an attribute with a value from the model. 
 : 
 : It creates a new attribute on the node and set its value to
 : the value associated to the key in the model, then proceeds
 : to templating its child nodes.
 : 
 : @param $node  the node to process
 : @param $model the current model
 : @param $key   the key to search in the model
 : @$param $name the name of the attribute to add to node
 : @return the processed block with attribute added to node, nothing otherwise.
 :)
declare function helpers:model-value-attribute($node as node(), $model as map(*), $key as xs:string, $name as xs:string) {
    element { node-name($node) } {
        attribute { $name } { $model($key) },
        $node/@*,
        templates:process($node/node(), $model)
    }
};

(:~
 : Insert pagination elements in a list element.
 : 
 : @param $node  the parent node where to insert the pagination link
 : @param $model the current model
 : @return a set of pagination links in list elements
 :)
declare
    %templates:wrap
function helpers:pagination($node as node(), $model as map(*)) {
    let $page   := $model('pagination')('page')
    let $npages := $model('pagination')('npages')
    
    let $parameters := string-join(
        for $n in request:get-parameter-names() 
        where $n != 'page' 
        return for $p in request:get-parameter($n, "")
            return string-join(($n, encode-for-uri($p)), "="), "&amp;")
    
    return (
        if ($page > 1) then 
            <li><a href="{ concat("?", string-join(( $parameters, "page=" || $page - 1 ), "&amp;")) }">Previous</a></li>
        else 
            (),
        <li>Page { $page } / { $npages }</li>,
        if ($page < $npages) then 
            <li><a href="{ concat("?", string-join(( $parameters, "page=" || $page + 1 ), "&amp;")) }">Next</a></li>
        else 
            ()
    )
};

(:~
 : Return a list of <option> elements for an HTML dropdown list.
 :
 : The option values and texts are retrieved from the the model entry for the
 : given key. The entry value can be:
 :  - a map, the value attributes are taken from the map keys and the texts
 :    from the model values
 :  - a sequence, the value attributes and the texts are sequence items.
 :
 : @param $node
 : @param $model
 : @param $key the identifier in the model for the contents of the options
 : @return a sequence of <option> elements
 :)
declare function helpers:select-options($node as node(), $model as map(*), $key as xs:string) as node()* {
    let $options := $model($key)
    return if ($options instance of map(*)) then
        for $key in map:keys($options)
        return <option value="{ $key }">{ map:get($options, $key) }</option>
    else
        for $value in $options
        return <option value="{ $value }">{ $value }</option>
};

(:~
 : Process input and select form controls, setting their value/selection to
 : values found in the model - if present.
 :
 : @node
 : 'templates' has a similar function (templates:form-control) that:
 :  - search for values in the request parameters.
 :  - does not template process the children of the node
 :
 : @param $node
 : @param $model
 : @return the processed node
 :)
declare function helpers:form-control($node as node(), $model as map(*)) as node()* {
    (: template process the children :)
    let $children := templates:process($node/node(), $model)

    let $control := local-name($node)
    return
    switch ($control)
        case "input" return
            let $type := $node/@type
            let $name := $node/@name
            (: try to get value from the model (instead of request parameters) :)
            let $value := map:get($model, $name)
            return
                if (exists($value)) then
                    switch ($type)
                        case "checkbox" case "radio" return
                            element { node-name($node) } {
                                $node/@* except $node/@checked,
                                if ($node/@value = $value) then
                                    attribute checked { "checked" }
                                else
                                    (),
                                $children
                            }
                        default return
                            element { node-name($node) } {
                                $node/@* except $node/@value,
                                attribute value { $value },
                                $children
                            }
                else
                    $node
        case "select" return
            (: try to get value from the model (instead of request parameters) :)
            let $value := map:get($model, $node/@name/string())
            return
                element { node-name($node) } {
                    $node/@*,
                    for $node in $children
                    return if ($node[local-name(.) = "option"] and ($node[@value = $value] or $node/string() = $value)) then
                            (: add the checked attribute to this element :)
                            element { node-name($node) } {
                                $node/@*,
                                attribute selected { "selected" },
                                $node/node()
                            }
                        else
                            $node
                    }
        default return
            element { node-name($node) } {
                $node/@*,
                $children
            }
};
