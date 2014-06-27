$(function () {
    $.fn.serializeXML = function(doc, root) {
        this.each(function () {
            var name = $(this).attr('name');
            if (name) {
                var e = doc.createElement(name);
                e.textContent = $(this).val();
                root.appendChild(e);
            }
        });
    };

    $('form').submit(function (e) {
        var s = new XMLSerializer();

        var $buttons = $('.btn', this);
        // disable form buttons while the data is uploaded
        $buttons
            .attr('disabled', 'disabled')
            .filter(':submit').append('<img src="resources/images/spinner.gif"/>');

        // Turn form into XML collection
        var collection = (new DOMParser()).parseFromString('<collection/>', 'text/xml');
        $('fieldset:first :input').not($('#articles :input')).serializeXML(collection, collection.documentElement);
        $('#articles li').each(function () {
            var article = collection.createElement('article');
            $(':input', this).serializeXML(collection, article);
            collection.documentElement.appendChild(article);
        });

        $.ajax('/exist/restxq/oidb/collection/' + encodeURIComponent(id), { data: s.serializeToString(collection), contentType: 'application/xml', type: 'PUT' });

        // data from collection to add to each granule
        var id       = $('fieldset:first input[name="id"]').val();
        var $article = $('fieldset:first #articles > li:first');
        var creator  = $('input[name="author"]:first', $article).val();
        var bibcode  = $('input[name="bibcode"]:first', $article).val();
        var keywords = $('input[name="keyword"]', $article).map(function () { return $(this).val() }).toArray().join(';');
        var pubdate  = $('input[name="pubdate"]', $article).val();
        var uploads  = $('tr.granule').map(function () {
            var $granule = $(this);
            var granule = (new DOMParser()).parseFromString('<granule/>', 'text/xml');
            
            function add(name, value) {
                var e = granule.createElement(name);
                e.textContent = value;
                granule.documentElement.appendChild(e);
            }
            add('obs_creator_name', creator);
            add('obs_release_date', pubdate);
            add('calib_level',      '3');
            add('obs_collection',   id);
            add('bib_reference',    bibcode);

            $(':input', this).serializeXML(granule, granule.documentElement);

            return $.ajax('modules/upload-granule.xql', { data: s.serializeToString(granule), contentType: 'application/xml', type: 'POST' })
                .done(function () {
                    // will not be selected for upload next time
                    $granule.removeClass('granule');
                });
        });

        $.when.apply($, uploads)
            .done(function(x) {
                // all granule successfully uploaded, redirect
                document.location = "submit.html";
            })
            .fail(function (x) {
                // had some failures, let user have another chance
                $buttons.removeAttr('disabled').children('img').remove();
            });

        e.preventDefault();
    });
});
