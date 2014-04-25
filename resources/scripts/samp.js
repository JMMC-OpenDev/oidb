// SAMP

function getCookie(name) {
    var cookies = document.cookie ? document.cookie.split('; ') : [];
    for(c in cookies) {
        var cookie = cookies[c].trim();
        if(cookie.trim().indexOf(name + "=") == 0) {
            return cookie.substring(name.length + 1);
        }
    }
    return null;
}

function setSessionCookie(name, value) {
    document.cookie = name + '=' + value + ';';
}

function deleteSessionCookie(name) {
    document.cookie = name + '=;';
}

$(function () {
    // Add an item to selected dropdowns
    // arg can be a function that is evaluated on each dropdown
    $.fn.dropdownAppend = function(arg) {
        return this.each(function () {
            var item = $.type(arg) == "function" ? arg.apply(this) : arg;
            $(this).find('ul.dropdown-menu:first').append(item);
        });
    };

    // Add a divider to selected dropdowns
    $.fn.dropdownAppendDivider = function () {
        return this.dropdownAppend('<li class="divider" role="presentation"/>');
    };

    // Build a dropdown item
    function dropdownMenuitem(text, icon, href) {
        return $('<li/>')
            .append(
                $('<a/>', { href: href })
                    .append($('<span/>', { class: "glyphicon glyphicon-" + icon }))
                    .append('&nbsp;').append(text));
    }

    var ct = new samp.ClientTracker();
    var metadata = {
        "samp.name": "OiDB",
        "samp.description": "description",
        "samp.icon.url": "http://localhost/" + "clientIcon.gif"
    }; 
    var connector = new samp.Connector("Name", metadata, ct, ct.calculateSubscriptions());

    // Functions to manage the session cookie for the SAMP private key of
    // the Hub connection
    function getSAMPPrivateKey() {
        return getCookie('samp.private-key');
    }

    function saveSAMPPrivateKey(key) {
        setSessionCookie('samp.private-key', key);
    }

    function resetSAMPPrivateKey() {
        deleteSessionCookie('samp.private-key');
    }

    // Try restoring SAMP connection with previously saved key
    // If there is no key or if the hub does not recognize the key, a new
    // connection will be started on demand instead.
    var key = getSAMPPrivateKey();
    if(key) {
        connector.setConnection(new samp.Connection({ 'samp.private-key': key }));
    }

    // Add and remove links to relevant SAMP clients in the dropdown menu
    $.fn.sampify = function(mtype, params) {
        this
        .bind('show.bs.dropdown', function (e) {
            // the list that makes the dropdown menu
            var $ul = $('ul', e.currentTarget);

            var $samp = dropdownMenuitem('No SAMP connection', 'info-sign', '#');
            $(this).dropdownAppend($samp);
            var $action = $('a', $samp);

            connector.runWithConnection(function (conn) {
                // Persist the SAMP connection
                saveSAMPPrivateKey(conn.regInfo['samp.private-key']);

                conn.getSubscribedClients([mtype], function (res) {
                    var parameters = jQuery.isFunction(params) ? params.call(e.currentTarget) : params;
                    var sendMessage = function (id) {
                        var msg = new samp.Message(mtype, parameters);
                        conn.notify([id, msg]);
                    };
                    // add an entry to the dropdown menu for the application
                    var addLink = function (id) {
                        return function (metadata) {
                            var name = metadata['samp.name'];
                            $('li.divider', $ul).after(
                                dropdownMenuitem('Send to ' + name, 'share', '#')
                                    .click(function () { sendMessage(id); }));
                        };
                    };

                    for (var id in res) {
                        var metadata = ct.metas[id];
                        if (metadata) {
                            addLink(id)(metadata);
                        } else {
                            // no metadata for this application, ask the hub
                            conn.getMetadata([id], addLink(id));
                        }
                    }

                    // change action to close connection
                    // Note: dropdown discarded on click, no need to delete elements
                    $action
                        .html('<span class="glyphicon glyphicon-remove-sign"/>&#160;Unregister from SAMP Hub')
                        .click(function (e) { conn.close(); resetSAMPPrivateKey(); e.preventDefault(); });
                });
            });
        })
        .bind('hidden.bs.dropdown', function (e) {
            // the list that make the dropdown menu
            var $ul = $('ul', e.currentTarget);
            // remove every SAMP entries (that is anything that follows the divider)
            $('li.divider ~ li', $ul).remove();
        });
        
        return this;
    };

    // Process data rows
    var $tr = $('table tbody tr');
    // create links to details pages when row id are known
    $tr.filter('[data-id]').find('.dropdown').dropdownAppend(function () {
        var id = $(this).parents('tr').first().data('id');
        return dropdownMenuitem('Details', 'zoom-in', './show.html?id=' + id);
    });
    // create links to SIMBAD when target names are known
    $tr.filter('[data-target_name]').find('.dropdown').dropdownAppend(function() {
        var targetname = $(this).parents('tr').first().data('target_name');
        return dropdownMenuitem('View in SIMBAD', 'globe', 'http://simbad.u-strasbg.fr/simbad/sim-id?Ident=' + encodeURIComponent(targetname));
    });
    // create links to ADS when bibliographic reference is known
    $tr.filter('[data-bib_reference]').find('.dropdown').dropdownAppend(function() {
        var bibreference = $(this).parents('tr').first().data('bib_reference');
        return dropdownMenuitem('Paper at ADS', 'book', 'http://cdsads.u-strasbg.fr/cgi-bin/nph-bib_query?' + encodeURIComponent(bibreference));
    });
    $tr.filter('[data-access_url]').find('.dropdown')
        // add a divider before SAMP links
        .dropdownAppendDivider()
        // prepare for SAMP table.load.fits links
        .sampify(
            'table.load.fits',
            // prepare parameters for the 'table.load.fits'
            function () {
                // find the access_url for the row
                var access_url = $(this).parents('tr').first().data('access_url');
                return { "url": access_url };
            });

    // TODO trim page=, perpage=, ...
    var query_string = window.location.search;
    var votable_url = window.location.protocol + '//' + window.location.host + window.location.pathname.match(/.*\// ) + 'modules/votable.xql' + query_string;
    var oixp_url = window.location.protocol + '//' + window.location.host + window.location.pathname.match(/.*\// ) + 'modules/oiexplorer.xql' + query_string;
    $('table thead .dropdown')
         // create links for VOTable and OIFitsExplorer collection downloads
        .dropdownAppend(dropdownMenuitem('Download VOTable', 'download', votable_url))
        .dropdownAppend(dropdownMenuitem('Download OIFitsExplorer collection', 'download', oixp_url))
        .dropdownAppendDivider()
        // prepare for SAMP table.load.votable links
        .sampify(
             'table.load.votable',
             // prepare parameter for the 'table.load.votable'
             { 'url': votable_url });
});
