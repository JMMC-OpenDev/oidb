$(function () {
    function serializeComment($form) {
        var s = new XMLSerializer();

        // Turn form into XML comment
        var comment = (new DOMParser()).parseFromString('<comment/>', 'text/xml');

        // Search for parent comment id
        var $parent = $form.parents('li').first();
        if ($parent.length != 0) {
            var parent = $parent.attr('id');
            comment.documentElement.setAttribute("parent", parent);
        }

        // FIXME avoid picking the id from the query string
        var matchGranuleId = RegExp('[?&]id=([^&]*)').exec(window.location.search);
        var granuleId = matchGranuleId && parseInt(matchGranuleId[1], 10);
        comment.documentElement.setAttribute("granule-id", granuleId);

        var text = comment.createElement('text');
        text.textContent = $(':input[name="message"]', $form).val();
        comment.documentElement.appendChild(text);

        return s.serializeToString(comment);
    }

    function saveComment(comment) {
        // save the comment, return the Deferred object of the operation
        return $.ajax('restxq/oidb/comment', { data: comment, contentType: 'application/xml', type: 'POST', dataType: 'text' });
    }

    // request templatized comment partial
    function loadComment(id) {
        return $.get('_comment.html', { id: id });
    }

    // the form to post a new comment or a reply
    var $commentForm = $('#comment-form').hide();

    // hide the form on startup, connect action
    $('form', $commentForm).submit(function (e) {
        e.preventDefault();
        $commentForm.hide();
                

        var $form = $(this);
        var comment = serializeComment($form);
        saveComment(comment)
            .pipe(function (data) {
                return loadComment(data);
            })
            // insert the new comment into comment tree
            .done(function (data) {
                var $comment = $(data);
                var $replyTo = $form.parents('.media-body').first();

                var $thread;
                if ($replyTo.length == 0) {
                    // toplevel comment
                    $replyTo = $('#comments ul.media-list').first();
                    $thread = $('<ul/>', { 'class': 'media-list' }).appendTo($replyTo);
                } else {
                    // new comment is a reply
                    $thread = $replyTo.find('> ul.media-list');
                    if ($thread.length == 0) {
                        // no reply yet, create thread
                        $thread = $('<ul/>', { 'class': 'media-list' }).appendTo($replyTo);
                    }
                }

                $(data).appendTo($thread);

                $commentForm
                    .hide()
                    // reset the comment form
                    .find(':input').val("").end()
                    // reset the button that triggered the display of the form
                    .prev('a.btn').show();

                $('#comments a.btn').removeClass('disabled');
            });
    });

    // connect the reply buttons to display the comment form
    $("#comments").on('click', 'a.btn', function (e) {
        e.preventDefault();
        $c_area = $(this);
        $c_button = $('#comments a.btn');
        $c_form = $commentForm;
        // assert we are logged in
        $.ajax('login').done(
            function (data, textStatus, jqXHR) {
                if ( jqXHR.status != 401) { 
                    $c_button.addClass('disabled');
                    $c_form.insertAfter($c_area).show();
                }else{
                    alert("hey!!");
                }
            }
        );
        
    });
   
    //+ Jonas Raoni Soares Silva
    //@ http://jsfromhell.com/string/rot13 [rev. #1]
    String.prototype.rot13 = function(){
        return this.replace(/[a-zA-Z]/g, function(c){
            return String.fromCharCode((c <= "Z" ? 90 : 122) >= (c = c.charCodeAt(0) + 13) ? c : c - 26);
        });
    };
    
    // connect the cont-act links
    $("a[data-contarr]").on('click', function (e){
        var array = eval($(this).data("contarr"))
        var str = array[0].join("")+array[1]+"@"+array[2].reverse().join(".");
        location.href=str.rot13();
        return false;
    });
});
