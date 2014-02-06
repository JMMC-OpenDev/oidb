// SAMP broadcasts

/*
 */
function _makeSAMPSuccessHandler(elt, access_url) {
	// returns the callback for a successful hub connection
	return function(conn) {
		conn.declareMetadata([{
			"samp.description": "samp.description",
			"samp.icon.url":    "samp.icon.url"
		}]);

		// set the button up so clicks send again without reconnection.
        $('.sendViaSAMP').unbind("click");
		$('.sendViaSAMP').click(function(e) {
            /* find the access_url from a previous cell */
            /* FIXME: problem if not access_url cell */
            var access_url = $(elt).parents('td').siblings(':eq(2) a').attr('href');
            sendSAMP(conn, access_url);
		});

		// make sure we unregister when the user leaves the page
		$(window).unload(function() {
			conn.unregister();
		});

		// send the stuff once (since the connection has been established
		// in response to a click alread)
        sendSAMP(conn, access_url);
	};
}

/*
 * Open a connection to a SAMP hub and if it succeeds, sends the SAMP message
 * for to the element.
 */
function connectAndSendSAMP(elt) {
    var access_url = $('a', $(elt).parents('tr').children('td:eq(2)')).attr('href');
	samp.register('OiDB',
		_makeSAMPSuccessHandler(elt, access_url),
		function(err) {
			alert("Could not connect to SAMP hub: " + err);
		}
	);
}

/*
 * Send a 'table.load.fits' message to SAMP hub over given connection.
 */
function sendSAMP(conn, access_url) {
	var msg = new samp.Message("table.load.fits", { "url": access_url });
	conn.notifyAll([msg]);
}

$(document).ready(function() {
    var $table = $("table");
    var $tr    = $('tbody tr', $table);

    $('td:eq(0) ul', $tr).append(
        $('<li/>', { class: 'sendviaSAMP' })
            .append($('<a/>', { href: '#' })
                .append('<span class="glyphicon glyphicon-share"/> SAMP broadcast')
                /* connect with SAMP and send broadcast */
                .click(function (e) { connectAndSendSAMP(e.currentTarget); })));
});
