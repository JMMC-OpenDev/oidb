$(function () {
    //
    //  Collection management
    //
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

    
    //
    //  User management
    //
    $('#link-user-modal').on('show.bs.modal', function (event) {
        var $button = $(event.relatedTarget);
        var user = $button.closest("li" ).children("a").text();
        var $modal = $(this);
        $modal.find('#link-user-modalLabel').text('Link ' + user);
        $modal.find('input').val(user);
    });
    
    $('#link-user-modal-save-btn').click(function (event) {
        var $button = $(this);
        var $modal = $("#link-user-modal");
        var aliasName = $modal.find("input").val();
        var selectedName = $modal.find("select").val();
        
        $.ajax('restxq/oidb/user/'+encodeURIComponent(selectedName)+"/addlink/"+encodeURIComponent(aliasName),
            { type: 'PUT' , data :'<a/>', contentType: 'application/xml', async:false}
        ).done(function( msg ) {
            $modal.modal("hide");
            location.reload();
        }).fail(function( jqXHR, textStatus, errorThrown ) {
            alert( "Request failed: " + textStatus + " ( " + errorThrown + " )");
        });

    });
    
    $('#add-user-modal').on('show.bs.modal', function (event) {
        var $button = $(event.relatedTarget);
        var user = $button.closest("li" ).children("a").text();
        var $modal = $(this);
        $modal.find('#add-user-modalLabel').text('Add datapi in the oidb user list ' + user);
        $modal.find('#add-user-modal-datapi').val(user);
        var firstname = user.split(" ",1)[0];
        var lastname = user.slice(firstname.length)
        $modal.find('#add-user-modal-firstname').val(firstname);
        $modal.find('#add-user-modal-lastname').val(lastname);
    });

    $('#add-user-modal-save-btn').click(function (event) {
        var $button = $(this);
        var $modal = $("#add-user-modal");
        var aliasName = $modal.find("#add-user-modal-datapi").val();
        var firstname = $modal.find('#add-user-modal-firstname').val();
        var lastname =$modal.find('#add-user-modal-lastname').val();
        var xml = '<person><firstname>'+firstname+'</firstname><lastname>'+lastname+'</lastname></person>'
        $.ajax('restxq/oidb/user/'+encodeURIComponent(aliasName),
            { type: 'POST' , data : xml, contentType: 'application/xml', async:false}
        ).done(function( msg ) {
            $modal.modal("hide");
            location.reload();
        }).fail(function( jqXHR, textStatus, errorThrown ) {
            alert( "Request failed: " + textStatus + " ( " + errorThrown + " )");
        });

    });
    
});