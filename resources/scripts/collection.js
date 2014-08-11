$(function () {
    // setup SAMP for sending OIFITS
    $('tr .dropdown').sampify(
        'table.load.fits',
        // prepare parameters for the 'table.load.fits'
        function () {
            // set SAMP parameter to URL of the relevant OIFITS file
            return { "url": $(this).siblings('a').attr('href') };
        });
});
