xquery version "3.1";

import module namespace config="http://apps.jmmc.fr/exist/apps/oidb/config" at "modules/config.xqm";

let $doc := doc($config:app-root||"/tests.xml")
let $date := current-dateTime()

let $test := <test><name>read-write-db</name>
{ 
  try {
    let $insert := if($doc//last) then () else update insert element last {"hello"} into $doc/*
      let $op := update replace $doc//last/text() with $date
      return 
      <ok/>
  } catch * {
    <error>{$err:description}</error>
  } 
}
</test>

let $tests := <tests>{$test}</tests>
let $code := if ($tests//error) then 500 else 200
return 
(response:set-status-code($code),$tests)
