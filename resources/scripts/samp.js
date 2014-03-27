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
    var d = new Date();
    document.cookie = name + '=' + value + ';';
}

function deleteSessionCookie(name) {
    document.cookie = name + '=;';
}

$(function () {
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

            var $action = $('<li><a href="#"/></li>').appendTo($ul);
            $('a', $action).html('<span class="glyphicon glyphicon-info-sign"/>&#160;No SAMP connection</a></li>');

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
                            $('li.divider', $ul).after($('<li/>').append(
                                $('<a/>', { href: '#'})
                                    .append('<span class="glyphicon glyphicon-share"/> Send to ' + name)
                                    .click(function () { sendMessage(id); })));
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
                    $('a', $action)
                        .html('<span class="glyphicon glyphicon-remove-sign"/>&#160;Unregister from SAMP Hub')
                        .click(function (e) { conn.close(); resetSAMPPrivateKey(); e.preventDefault() });
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

    // set of SAMP links for the current row
    $('table tbody .dropdown').sampify(
        'table.load.fits',
        // prepare parameters for the 'table.load.fits'
        function () {
            // find the access_url for the row, looking for the cell in the table FIXME
            var access_url = $('a', $(this).parents('tr').children('td:eq(2)')).attr('href');
            return { "url": access_url };
        });

    // TODO trim page=, perpage=, ...
    var query_string = window.location.search;
    var votable_url = window.location.protocol + '//' + window.location.host + window.location.pathname.match(/.*\// ) + 'modules/votable.xql' + query_string;
    var oixp_url = window.location.protocol + '//' + window.location.host + window.location.pathname.match(/.*\// ) + 'modules/oiexplorer.xql' + query_string;
    $('table thead th:first-child .dropdown').sampify(
         'table.load.votable',
         // prepare parameter for the 'table.load.votable'
         { 'url': votable_url })
         // set urls on direct links for VOTable and OIFitsExplorer collection
         .find('.dropdown-menu a')
            .first().attr('href', votable_url).end()
            .eq(1).attr('href', oixp_url);
});
