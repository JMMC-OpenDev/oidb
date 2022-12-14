xquery version "3.0";

(:~
 : This module provides a set of helper functions for HTML templating
 : that are not part of the upstream templates module.
 :
 : It also extends eXist-db model for templating by supporting hierarchical
 : keys and composite model (XQuery maps with possibly XML element as values).
 :)
module namespace helpers="http://apps.jmmc.fr/exist/apps/oidb/templates-helpers";

import module namespace templates="http://exist-db.org/xquery/html-templating";
import module namespace lib="http://exist-db.org/xquery/html-templating/lib";

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
 : Render a partial with additional data from model entry.
 :
 : If the key refers to a model entry containing a sequence, the partial is
 : repeated once for each item of the sequence.
 :
 : @param $node    the current node
 : @param $model   the current model
 : @param $partial the path to the partial to render
 : @param $key     the key to search in model for partial data
 : @param $as      the name of the model entry to hold data within the partial
 : @return a sequence of nodes as result of each partial templating
 :)
declare function helpers:render($node as node(), $model as map(*), $partial as xs:string, $key as xs:string, $as as xs:string?) as node()* {
    let $as := if ($as) then $as else helpers:key-prefix-from-partial($partial)
    (: adapted from templates:include() to save cycles :)
    let $partial := doc(concat(
        if (starts-with($partial, "/")) then
            (: search document relative to app root :)
            templates:get-app-root($model)
        else
            (: locate template relative to HTML file :)
            templates:get-root($model),
        "/", $partial))
    (: repeat for each item of value :)
    for $item in helpers:get($model, $key)
    return templates:process($partial/node(), map:merge(( $model, map:entry($as, $item) )))
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
            templates:process($node/node(), map:merge(($model, map:entry($to, $item))))
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
            (: pick all elements or attribute with name equal to local-key as value :)
            ( $model/*[name()=$local-key], $model/@*[name()=$local-key] )
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
 : @return null if no key is found or a string with value of the key in the model / string separeted by ccomma if multiple values are found
 :)
declare %private function helpers:model-value($model as map(*), $key as xs:string) as xs:string? {
    let $v := helpers:get($model, $key)
    return
        if( exists($v) ) then string-join(for $e in $v return xs:string($e), ", ") else ()
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
 : Return the content of the given key in the model as element.
 :
 : @param $node  a placeholder for text
 : @param $model the current model
 : @param $key   the key to search in the model
 : @return the content for key in model or nothing
 :)
declare function helpers:model-content($node as node(), $model as map(*), $key as xs:string) as item()* {
    helpers:get($model, $key)
};



(:~
 : Return the subcontent of the given key in the model as element.
 :
 : @param $node  a placeholder for text
 : @param $model the current model
 : @param $key   the key to search in the model
 : @return the content for key in model or nothing
 :)
declare function helpers:model-subcontent($node as node(), $model as map(*), $key as xs:string) as item()* {
    helpers:get($model, $key)/text()|helpers:get($model, $key)/*
};


(:~
 : Return the content of the given key in the model as a xml comment.
 :
 : @param $node  a placeholder for text
 : @param $model the current model
 : @param $key   the key to search in the model
 : @return the content for key in model or nothing in comment
 :)
declare function helpers:model-comment($node as node(), $model as map(*), $key as xs:string) as node()? {
    let $content := helpers:get($model, $key)
    return comment {$content}
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
 : The option values and texts are retrieved from the model entry for the
 : given key. The entry value can be:
 :  - a map, the value attributes are taken from the map keys and the texts
 :    from the model values
 :  - a sequence, the value attributes and the texts are sequence items.
 :
 : For map entry value and sorted=no, the default key order is taken from the list
 : retrieved from the model with "-default-keys-order" suffix
 :
 : @param $node
 : @param $model
 : @param $key the identifier in the model for the contents of the options
 : @param $sorted optional parameter to define order-by rule : (no, descending), default is ascending
 : @return a sequence of <option> elements
 :)
declare
%templates:default("sorted", "ascending")
function helpers:select-options($node as node(), $model as map(*), $key as xs:string, $sorted as xs:string?) as node()* {
    let $options := $model($key)
    let $ret := if ($options instance of map(*)) then
        (: let $log := util:log("info", "searching for " || $key||"-default-keys-order :" || string-join($model($key||"-default-keys-order"), ", ") ) :)
        let $map-default-keys-order := $model($key||"-default-keys-order")
        return
            for $key at $pos in map:keys($options)
            order by
                if (exists($map-default-keys-order) ) then index-of($map-default-keys-order, $key) else
                if ($sorted="no") then
                    $pos
                else upper-case($key) ascending
            let $option := map:get($options, $key)
            return
                if ($option instance of map(*)) then
                    <optgroup label="{$key}">{helpers:select-options($node,map{$key:$option}, $key, $sorted)}</optgroup>
                else
                    <option value="{ $key }">{ $option }</option>
    else
        for $value at $pos in $options
        order by if ($sorted="no") then $pos else upper-case($value) ascending
        return <option value="{ $value }">{ $value }</option>
    return if($sorted="descending") then reverse($ret) else $ret
};

(:~
 : Process input and select form controls, setting their value/selection to
 : values found in the model or request parameters - if present.
 :
 : @note
 : 'templates' has a similar function (templates:form-control) that:
 :  - search for values in the request parameters.
 :  - does not template process the children of the node
 :
 : @param $node
 : @param $model
 : @return the processed node
 :)
declare function helpers:form-control($node as node(), $model as map(*)) as node()* {
    helpers:form-control($node, $model, ())
};

declare %private function helpers:form-control($node as node(), $model as map(*), $value as xs:string?) as node()* {
    (: template process the children :)
    let $children := templates:process($node/node(), $model)

    let $type := $node/@type
    let $name := $node/@name
    (: try to get value from the model (instead of request parameters) :)
    let $value := if($value) then $value else if($name) then map:get($model, $name) else ()

    let $control := local-name($node)
    return
    switch ($control)
        case "input" return
            (: look for request params of the given name to let decide which checked attribute to set below :)
            let $params-values := request:get-parameter($name, ())
            return
                if (exists($value)) then
                    switch ($type)
                        case "checkbox" case "radio" return
                            element { node-name($node) } {
                                (:if($name="category") then (
                                util:log("info","helpers:form-controls for "||$name|| " in " || string-join(map:keys($model), ", ")),
                                util:log("info","helpers:form-controls node: "|| serialize($node)),
                                util:log("info","helpers:form-controls value "||string-join($value,", ")),
                                util:log("info","helpers:form-controls params-values "||string-join($params-values,"/"))) else ()
                                ,:)
                                if ( exists($params-values) or $node/@value) then $node/@* except $node/@checked else $node/@*,
                                if ( exists($node/@value) ) then () else attribute value { $value },
                                if ($node/@value = $value ) then
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
            element { node-name($node) } {
                $node/@*,
                for $node in $children
                    return if ( not( $node/local-name(.) = ("option", "optgroup") ) ) then $node else
                    helpers:form-control($node, $model, $value)
                }
        case "optgroup" return
            element { node-name($node) } {
                $node/@*,
                for $node in $children
                    return if ( not( $node/local-name(.) = ("option", "optgroup") ) ) then $node else
                    helpers:form-control($node, $model, $value)
                }
        case "option" return
            if (($node[@value = $value] or $node/string() = $value) and string-length(string-join($value))>0 ) then
                (: add the checked attribute to this element :)
                element { node-name($node) } {
                    $node/@*,
                    attribute selected { "selected" },
                    $node/node()
                }
            else
                $node
        case "textarea" return
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

(:~
 : Templatize a node if a request attribute is not set.
 :
 : @note
 : This function is the mirror of templates:if-attribute-set().
 :
 : @param $node
 : @param $model
 : @param $attribute the request attribute to check
 : @return the processed node if the attribute is not set or value is a falsy
 :)
declare function helpers:unless-attribute-set($node as node(), $model as map(*), $attribute as xs:string) {
    let $isSet :=
        (exists($attribute) and request:get-attribute($attribute))
    return
        if ($isSet) then
            ()
        else
            templates:process($node/node(), $model)
};
