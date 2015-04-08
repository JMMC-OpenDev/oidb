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
        if (jqXHR.status != 401 || ajaxSettings.suppressErrors) { 
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

    // connect to navigation bar sign in entry
    $('#login a').click(function (e) {
        e.preventDefault();

        // setup the dialog: load from partial
        var login = $('#loginModal');
        if (login.size() === 0) {
            login = $.ajax('_login-modal.html').done(setupLoginModal);
        }

        // display the login dialog
        $.when(login).done(function () {
            $('#loginModal')
                .modal('show')
                // check status on dialog close
                .one('hidden.bs.modal', function (e) {
                    $.get('login', { suppressErrors: true })
                        .done(function (data) {
                            // successfully logged in: update navigation header
                            $('nav').load('templates/page.html nav > *');
                        });
                });
        });
    });
});