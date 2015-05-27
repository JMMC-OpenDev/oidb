$(function () {
    
    $("button[data-colref]").click(function(e) {
        e.preventDefault();
        var id= $(this).attr("data-colref");
        var answer = confirm('Are you sure you want to delete the "'+id+'" collection ?');
        if (answer)
        {
            deleteCollection(id, $(this).parents("a"));
        }
        else
        {
          console.log('cancel');
        }
    });
    
    function deleteCollection(id, $blockToRemove) {
        $.ajax(
            'restxq/oidb/collection/'+encodeURIComponent(id), { type: 'DELETE' }
        ).done(function() {
            $blockToRemove.remove();
        }).fail(function( jqXHR, textStatus, errorThrown ) {
            alert( "Request failed: " + textStatus + " ( " + errorThrown + " )");
        });
    }

                  
});