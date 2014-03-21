// SAMP

$(function () {
    var ct = new samp.ClientTracker();
    var metadata = {
        "samp.name": "OiDB",
        "samp.description": "description",
        "samp.icon.url": "http://localhost/" + "clientIcon.gif"
    }; 
    var connector = new samp.Connector("Name", metadata, ct, ct.calculateSubscriptions());

    // Add and remove links to relevant SAMP clients in the dropdown menu for
    // each row of the result table.
    $('table .dropdown')
        .bind('show.bs.dropdown', function (e) {
            // find the access_url for the row, looking for the cell in the table FIXME
            var access_url = $('a', $(e.currentTarget).parents('tr').children('td:eq(2)')).attr('href');
            // the list that makes the dropdown menu
            var $ul = $('ul', e.currentTarget);
    
            connector.runWithConnection(function (conn) {
                conn.getSubscribedClients(["table.load.fits"], function (res) {
                    // send a table.load.fits message to the hub at conn
                    var sendMessage = function (id) {
                        var msg = new samp.Message("table.load.fits", { "url": access_url});
                        conn.notify([id, msg]);
                    };
                    // add an entry to the dropdown menu for the application
                    var addLink = function (id) {
                        return function (metadata) {
                            var name = metadata['samp.name'];
                
                            $('<li/>').append(
                                $('<a/>', { href: '#'})
                                    .append('<span class="glyphicon glyphicon-share"/> Send to ' + name)
                                    .click(function () { sendMessage(id); })).appendTo($ul);
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
                });
            });
        })
        .bind('hidden.bs.dropdown', function (e) {
            // the list that make the dropdown menu
            var $ul = $('ul', e.currentTarget);
            // remove every SAMP entries (that is anything that follows the divider)
            $('li.divider ~ li', $ul).remove();
        });

    $(window).unload(function () {
        // sever link with SAMP Hub if any
        connector.unregister();
    });
});
