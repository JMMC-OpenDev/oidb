xquery version "3.0";

(:~
 : This module provides a set of helper functions for HTML templating
 : that are not part of the upstream templates module.
 : 
 : It also extends eXist-db model for templating by supporting hierarchical
 : keys and composite model (XQuery maps with possibly XML element as values).
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
    if (exists(helpers:get($model, $key))) then
        templates:process($node/node(), $model)
    else
        ()
};

(:~
 : Evaluate and output the block if the model does not have a given property.
 : 
 : @param $node
 : @param $model current model
 : @param $key   key to search in the model
 : @return the processed block if the model does not have a value for this key, nothing otherwise.
 :)
declare
    %templates:wrap
function helpers:unless-model-key($node as node(), $model as map(*), $key as xs:string) {
    if (exists(helpers:get($model, $key))) then
        ()
    else
        templates:process($node/node(), $model)
};

(:~
 : Derive a key prefix from a partial path.
 : 
 : @param $partial the partial path
 : @return a key prefix
 :)
declare %private function helpers:key-prefix-from-partial($partial as xs:string) as xs:string {
    substring-before(substring-after(tokenize($partial, '/')[last()], '_'), '.')
};

(:~
 : Iterate over values for a key in model and repeatedly process nested contents.
 : 
 : @param $node  the template node to repeat
 : @param $model the current model
 : @param $from  the key in model for entry with values to iterate over
 : @param $to    the name of the new entry in each iteration
 : @return a sequence of nodes, one for each value
 :)
declare function helpers:each($node as node(), $model as map(*), $from as xs:string, $to as xs:string) as node()* {
    for $item in helpers:get($model, $from)
    return
        element { node-name($node) } {
            $node/@*,
            templates:process($node/node(), map:new(($model, map:entry($to, $item))))
        }
};

(:~
 : Return the value associated with the key in an extended model.
 : 
 : @param $model the extended model
 : @param $key   the key to search for
 : @return the value of the key in the model
 :)
declare function helpers:get($model as item()*, $key as xs:string) as item()* {
    (: split complex key :)
    let $prefix := substring-before($key, '.')
    let $local-key := if($prefix) then $prefix else $key
    (: search for value of entry with local prefix :)
    let $value :=
        if ($model instance of map(*)) then
            (: simple case: get entry for local-key in map :)
            map:get($model, $local-key)
        else if ($model instance of element()) then
            (: pick all elements with name equal to local-key as value :)
            $model/*[name()=$local-key]
        else
            (: bad model :)
            ()
    return if (exists($value) and $prefix) then
        (: keep going down in the model for subkeys :)
        helpers:get($value, substring-after($key, '.'))
    else if ($prefix and empty($value)) then
        (: complex key with no value in model :)
        ()
    else
        (: value found or no value for simple key :)
        $value
};

(:~
 : Helper function for getting value in a model as a string.
 : 
 : @param $model the current model
 : @param $key   the key to search for in the model
 : @return a string with value of the key in the model
 :)
declare %private function helpers:model-value($model as map(*), $key as xs:string) as xs:string? {
    xs:string(helpers:get($model, $key))
};

(:~
 : Return the value of the given key in the model as text.
 : 
 : @param $node  a placeholder for text
 : @param $model the current model
 : @param $key   the key to search in the model
 : @return the value for key in model as string or nothing
 :)
declare function helpers:model-value($node as node(), $model as map(*), $key as xs:string) as xs:string? {
    helpers:model-value($model, $key)
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
        attribute { $name } { helpers:model-value($model, $key) },
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
declare function helpers:pagination($node as node(), $model as map(*)) as node()* {
    let $page   := $model('pagination')('page')
    let $npages := $model('pagination')('npages')
    
    let $parameters := string-join(
        for $n in request:get-parameter-names() 
        where $n != 'page' 
        return for $p in request:get-parameter($n, "")
            return string-join(($n, encode-for-uri($p)), "="), "&amp;")
    
    return (
        if ($page > 1) then 
            (
            <li><a href="{ concat("?", string-join(( $parameters, "page=1" ), "&amp;")) }">First</a></li>,
            <li><a href="{ concat("?", string-join(( $parameters, "page=" || $page - 1 ), "&amp;")) }">Previous</a></li>
            )
        else 
            (),
        <li>Page { $page } / { $npages }</li>,
        if ($page < $npages) then 
            (
            <li><a href="{ concat("?", string-join(( $parameters, "page=" || $page + 1 ), "&amp;")) }">Next</a></li>,
            <li><a href="{ concat("?", string-join(( $parameters, "page=" || $npages ), "&amp;")) }">Last</a></li>
            )
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
        case "textarea" return
            (: try to get value from the model (instead of request parameters) :)
            let $value := map:get($model, $node/@name/string())
            return
                element { node-name($node) } {
                    $node/@*,
                    if (exists($value)) then $value else $node/text()
                }
        default return
            element { node-name($node) } {
                $node/@*,
                $children
            }
};
