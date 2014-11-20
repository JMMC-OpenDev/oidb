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

    // Turn fields from the form into a collection XML document and upload it
    // to the REST endpoint of OiDB.
    function saveCollection() {
        var s = new XMLSerializer();

        // Turn form into XML collection
        var collection = (new DOMParser()).parseFromString('<collection/>', 'text/xml');
        $('fieldset:first :input').not($('#articles :input')).serializeXML(collection, collection.documentElement);
        $('#articles > li').each(function () {
            var article = collection.createElement('article');
            $(':input', this).serializeXML(collection, article);
            collection.documentElement.appendChild(article);
        });

        var id = $('fieldset:first input[name="name"]').val();
        // save the collection, return the Deferred object of the operation
        return $.ajax('restxq/oidb/collection/' + encodeURIComponent(id), { data: s.serializeToString(collection), contentType: 'application/xml', type: 'PUT' });
    }

    // Turn granule fields of the form into granule and attach them to the
    // collection before uploading.
    function saveGranules() {
        var s = new XMLSerializer();

        var $collection = $('fieldset:first');
        var collection_id = $('input[name="name"]', $collection).val();

        // data from collection to add to each granule
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
            add('obs_collection',   collection_id);
            add('bib_reference',    bibcode);

            $(':input', this).prop('disabled', true).serializeXML(granule, granule.documentElement);

            return $.ajax('modules/upload-granules.xql', { data: s.serializeToString(granule), contentType: 'application/xml', type: 'POST' })
                .done(function (data) {
                    // will not be selected for upload next time
                    $granule.removeClass('granule');
                    $granule.find('[data-role="targetselector"]').targetselector('destroy');
                    $granule.find('[data-role="instrumentselector"]').instrumentselector('destroy');
                    $granule.find('[data-role="modeselector"]').modeselector('destroy');
                    
                    // turn row into clickable links to granule details
                    var id = parseInt($('id', data).text(), 10);
                    $granule
                        .addClass('pointer')
                        .click(function (e) {
                            if (e.target instanceof HTMLInputElement ||
                                e.target instanceof HTMLAnchorElement) {
                                return;
                            }
                            window.open('show.html?id=' + id);
                        });
                });
        });

        // return a Deferred object to wait until all uploads finish
        return $.when.apply($, uploads);
    }

    $('form').submit(function (e) {
        var $buttons = $('.btn', this);
        // disable form buttons while the data is uploaded
        $buttons
            .attr('disabled', 'disabled')
            .filter(':submit').append('<img src="resources/images/spinner.gif"/>');

        saveCollection()
            .pipe(saveGranules)
            .done(function(x) {
                // all granule successfully uploaded, reuse the submit button
                $buttons.filter(':submit')
                    .children('img').remove().end()
                    .removeAttr('disabled')
                    .text('Done')
                    .click(function () { document.location = "submit.html"; });
            })
            .fail(function (x) {
                // had some failures, let user have another chance
                $buttons.removeAttr('disabled').children('img').remove();
                // re-enable inputs of granules
                $('tr.granule :input').prop('disabled', false);
            });

        e.preventDefault();
    });

    $('[data-toggle="checkreport"]').checkreport();

    $('tr .dropdown').sampify(
        'table.load.fits',
        // prepare parameters for the 'table.load.fits'
        function () {
            // set SAMP parameter to URL of the relevant OIFITS file
            return { "url": $(this).siblings('a').attr('href') };
        });
});
