xquery version "3.0";

(:~
 : This module provides helpers to pass temporary messages between actions
 : through the session.
 :)
module namespace flash="http://apps.jmmc.fr/exist/apps/oidb/flash";

(:~
 : Add a notice message with the specified importance level to the flash.
 : 
 : @param $level the level of the message ('info', 'warning', 'error')
 : @param $msg   the message to add
 : @return empty
 :)
declare %private function flash:message($level as xs:string, $msg as item()*) {
    if (session:exists()) then
        session:set-attribute('flash', element { $level } { $msg })
    else
        util:log($level, $msg/string())
};

(:~
 : Add an info message to the flash.
 : 
 : @param $msg the message to add
 : @return empty
 :)
declare function flash:info($msg as item()*) {
    flash:message('info', $msg)
};

(:~
 : Add a warning notice to the flash.
 : 
 : @param $msg the message to add
 : @return empty
 :)
declare function flash:warning($msg as item()*) {
    flash:message('warning', $msg)
};

(:~
 : Add an error notice to the flash.
 : 
 : @param $msg the message to add
 : @return empty
 :)
declare function flash:error($msg as item()*) {
    flash:message('error', $msg)
};

(:~
 : Return the Bootstrap class name for the given flash message level.
 : 
 : See http://getbootstrap.com/components/#alerts.
 : 
 : @param $level message level (error, warning, info)
 : @return a Bootstrap contextual class for an alert
 :)
declare %private function flash:flash-contextual-class($level as xs:string) as xs:string {
    switch ($level)
        case 'error'   return 'alert-danger'
        case 'warning' return 'alert-warning'
        case 'info'    return 'alert-info'
        default        return 'alert-info'
};

(:~
 : Templatize any flash messages from the current session.
 : 
 : Flash messages are retrieved from the session attribute named 'flash'.
 : 
 : @param $node  the current node to use as template
 : @param $model
 : @return a templatized node for each flash message.
 :)
declare function flash:flash($node as node(), $model as map(*)) as node()* {
    for $flash in ( session:get-attribute('flash'), session:remove-attribute('flash') )
    let $level := $flash/name()
    (: reuse current node as template for flash :)
    return element { $node/name() } {
        $node/@* except $node/@class,
        (: set contextual class from flash level :)
        attribute { 'class' } { string-join(( $node/@class, flash:flash-contextual-class($level) ), ' ') },
        $node/*,
        (: copy HTML content from flash :)
        $flash/node()
    }
};
