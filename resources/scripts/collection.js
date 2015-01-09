$(function () {
    function setupPage() {
        // setup SAMP for sending OIFITS
        $('tr .dropdown').sampify(
            'table.load.fits',
            // prepare parameters for the 'table.load.fits'
            function () {
                // set SAMP parameter to URL of the relevant OIFITS file
                return { "url": $(this).siblings('a').attr('href') };
            });

        // change pointer over granule rows
        $('table .granule').addClass('pointer');
    }

    setupPage();

    // make the rows clickable to open granule details page
    $('table .granule')
        .click(function (e) {
            if (e.target instanceof HTMLInputElement ||
                e.target instanceof HTMLAnchorElement) {
                return;
            }
            var id = $(e.target).parents('tr').data('id');
            if (id) window.open('show.html?id=' + id);
        });

    // AJAX pagination of granules
    $("#granules" ).on( "click", ".pager a", function(e) {
        e.preventDefault();

        var query = $(this).attr('href').split('?')[1];
        
        $('#granules .pager li').addClass('disabled');

        // replace results
        $('#granules')
            .find('> div').fadeTo('fast', 0.5).end()
            .load('_collection-granules.html' + '?' + query, setupPage);
    });
});
