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
