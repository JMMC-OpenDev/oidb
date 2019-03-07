$(function () {
    var $form = $('form[name="metadata"]');

    // add an alert to the metadata form that is automatically dismissed
    function addAlert(level, message) {
        $('<div class="alert" role="alert"/>')
            .addClass('alert-' + level)
            .append(message)
            .insertAfter($form);
    }

    // the handler for the form submitting from an XML granule file
    $form.submit(function (e) {
        e.preventDefault();

        var $file = $("input:file", $form);

        var file = $file.get(0).files[0];
        // plug FileReader with jQuery Deferred
        var deferred = $.Deferred();
        var reader = new FileReader();
        reader.onerror = reader.onabort = function () {
            deferred.reject();
        };
        reader.onloadend = function () {
            deferred.resolve(reader.result);
        };
        // start reading the content of the file
        reader.readAsArrayBuffer(file);

        deferred
            .pipe(function (data) {
                return $.ajax('restxq/oidb/granule', {
                    type: 'POST',
                    data: data,
                    contentType: 'application/xml',
                    processData: false,
                });
            })
            .done(function (data) {
                // great success: simple message
                var count = $('id', data).size();
                addAlert('success', '' + count + ' granule(s) saved.');
                $file.val('');
            })
            .fail(function(jqXHR, textStatus) {
                var message;
                // pick error message from response if any, otherwise XHR description
                if (jqXHR.responseXML) {
                    message = jqXHR.responseXML.getElementsByTagName('error')[0].textContent;
                } else {
                    message = textStatus;
                }
                addAlert('danger', message);
            });
    });
});
