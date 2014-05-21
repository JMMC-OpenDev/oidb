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

    // Populate the application list for the given mtype and show the modal
    function showApplicationsModal(mtype) {
        var $modal = $('#apps-modal');
        // from VO Application Registry (http://voar.jmmc.fr)
        if ($.fn.appendAppList) {
            var $ul = $('.voar ul', $modal);
            $ul.empty().appendAppList({ 'mtype': mtype });
        } else {
            $('.voar', $modal).hide();
        }
        $modal.modal('show');
    }

    // Add and remove links to relevant SAMP clients in the dropdown menu
    $.fn.sampify = function(mtype, params) {
        this
        .bind('show.bs.dropdown', function (e) {
            var $dropdown = $(this);

            // the divider introduce SAMP links
            var $divider = $('<li class="divider" role="presentation"/>');
            $dropdown.dropdownAppend($divider);

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
                            $divider.after(
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
                    $dropdown.dropdownAppend(
                        dropdownMenuitem('Unregister from SAMP Hub', 'remove-sign', '#')
                            .click(function (e) { conn.close(); resetSAMPPrivateKey(); e.preventDefault(); }));
                });
            },
            function (error) {
                // add status entry, no connection
                $dropdown.dropdownAppend(
                    dropdownMenuitem('No SAMP connection', 'info-sign', '#')
                        .click(function (e) { showApplicationsModal(mtype); e.preventDefault(); }));
            });
        })
        .bind('hidden.bs.dropdown', function (e) {
            var $divider = $('ul li.divider:last', e.currentTarget);
            // remove every SAMP entries (that is anything that follows the divider)
            $divider.nextAll('li').remove();
            // and the divider
            $divider.remove();
        });
        
        return this;
    };

    // Process data rows
    var $tr = $('table tbody tr');
    $tr.find('.dropdown')
        .one('show.bs.dropdown', function (e) {
            var $dropdown = $(this);
            var data = $dropdown.parents('tr').first().data();
            if (data.id)
                // create link to details pages
                $dropdown.dropdownAppend(dropdownMenuitem('Details', 'zoom-in', './show.html?id=' + data.id));
            if (data.target_name)
                // create links to SIMBAD
                $dropdown.dropdownAppend(dropdownMenuitem('View in SIMBAD', 'globe', 'http://simbad.u-strasbg.fr/simbad/sim-id?Ident=' + encodeURIComponent(data.target_name)));
            if (data.bib_reference)
                // create links to ADS
                $dropdown.dropdownAppend(dropdownMenuitem('Paper at ADS', 'book', 'http://cdsads.u-strasbg.fr/cgi-bin/nph-bib_query?' + encodeURIComponent(data.bib_reference)));
        });
    $tr.filter('[data-access_url]').find('.dropdown')
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
    var curl_url = window.location.protocol + '//' + window.location.host + window.location.pathname.match(/.*\// ) + 'modules/curl.xql' + query_string;
    $('table thead .dropdown')
        // install non SAMP links
        .one('show.bs.dropdown', function (e) {
            console.log(this);
    
            $(e.currentTarget)
                 // create links for VOTable and OIFitsExplorer collection downloads
                .dropdownAppend(dropdownMenuitem('Download VOTable', 'download', votable_url))
                .dropdownAppend(dropdownMenuitem('Download OIFitsExplorer collection', 'download', oixp_url))
                .dropdownAppend(dropdownMenuitem('Download all files with curl', 'download', curl_url));
        })
        // prepare for SAMP table.load.votable links
        .sampify(
             'table.load.votable',
             // prepare parameter for the 'table.load.votable'
             { 'url': votable_url });
});
