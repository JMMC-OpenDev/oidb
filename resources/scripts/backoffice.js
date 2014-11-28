$(function () {
    // hijack the notification area of the page and insert an error message
    function alertDanger(message) {
        $('[data-template="backoffice:action"]')
            .empty()
            .html('\
            <div class="alert alert-danger fade in">\
                <button aria-hidden="true" data-dismiss="alert" class="close" type="button">×</button>\
                <strong>Action failed ! </strong>\
            ' + message + '\
            </div>');
    }

    // upload the observation log file for CHARA with HTML5 File API and then
    // do server side data extraction
    $('#chara form').submit(function (e) {
        var $form = $(this);

        var $file = $('input:file', $form);
        var $spinner = $('<img>', { 'src': 'resources/images/spinner.gif' });

        // prevent further form submission until file is uploaded
        e.preventDefault();

        // disable form and add spinner for feedback while the file uploads
        // $(':input', $form).prop('disabled', true);
        $file.after($spinner);

        // plug FileReader with jQuery Deferred
        var read = $.Deferred();
        var reader = new FileReader();
        reader.onerror = reader.onabort = function () {
            read.reject();
        };
        reader.onloadend = function () {
            read.resolve(reader.result);
        };
        // start reading the content of the file
        reader.readAsBinaryString($file.get(0).files[0]);

        read
            .fail(function () {
                alertDanger('Failed to upload the observation log file. See log for details.');
                $spinner.remove();
                $(':input', $form).prop('disabled', false);
            })
            .pipe(function (data) {
                return $.ajax('/exist/rest/db/apps/oidb-data/tmp/upload-chara.dat', {
                    type: 'PUT',
                    contentType: 'text/csv',
                    data: data,
                    processData: false,
                });
            })
            .done(function () {
                // FIXME nasty, better to do a submit but does not work: create an empty POST
                window.location = '?do=chara-update';
            });
            
    });
});

