$(function () {
    var $commentForm = $('#comment-form');

    // hide the form on startup
    $commentForm.hide();

    $('a.add-comment')
        .click(function (e) {
            var $button = $(this);
            var $comment = $button.parents('li').first();
            var id = $comment.attr('id');

            // enable and show all comment buttons...
            $('a.add-comment').removeClass('disabled').show();
            // ... but the one clicked
            $button.addClass('disabled').hide();

            $commentForm
                // remove from previous location
                .hide().detach()
                // add to current comment
                .appendTo($(this).parent())
                // update the parent comment id
                .find(':input[name="parent"]').val(id).end()
                // show the form at its new location
                .show();

            $('html, body').animate({
                scrollTop: $commentForm.offset().top
            }, 2000);

            e.preventDefault();
        });
});
