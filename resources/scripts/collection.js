$(function () {
    // make the rows clickable to open granule details page
    $('table .granule')
        .addClass('pointer')
        .click(function (e) {
            if (e.target instanceof HTMLInputElement ||
                e.target instanceof HTMLAnchorElement) {
                return;
            }
            var id = $(e.target).parents('tr').data('id');
            if (id) window.open('show.html?id=' + id);
        });

    // setup SAMP for sending OIFITS
    $('tr .dropdown').sampify(
        'table.load.fits',
        // prepare parameters for the 'table.load.fits'
        function () {
            // set SAMP parameter to URL of the relevant OIFITS file
            return { "url": $(this).siblings('a').attr('href') };
        });
});
