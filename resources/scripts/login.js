$(function () {
    // prepare a modal dialog for login
    function setupLoginModal(modal) {
        var $modal = $(modal);

        $modal
            .appendTo('#content')
            // connect the form 'log in' button
            .find('form').submit(function (e) {
                var $form = $(this);

                e.preventDefault();

                // try authenticate with username and password from form
                $.ajax('login', { data: $form.serialize() })
                    .done(function () {
                        // successfully logged in
                        $modal.modal('hide');
                    })
                    .fail(function () {
                        // unable to log in with given credentials
                        var $groups = $('.input-group', $form);
                        $groups.toggleClass('has-error');
                        $('<div class="alert alert-danger" role="alert"/>')
                            .text('Wrong username and/or password.')
                            .prependTo($form)
                            .delay(5000).slideUp('fast', function() {
                                $(this).remove();
                                $groups.toggleClass('has-error');
                            });
                    });
            });
    }

    $( document ).ajaxError(function (event, jqXHR, ajaxSettings, thrownError) {
        // only interested in authentication errors
        if (jqXHR.status != 401) {
            return;
        }

        // setup the dialog: load from partial or reuse previous dialog
        var login = $('#loginModal');
        if (login.size() === 0) {
            login = $.ajax('_login-modal.html').done(setupLoginModal);
        }

        // display the login dialog
        $.when(login).then(function () { $('#loginModal').modal('show'); });
    });
});