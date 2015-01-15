$(function () {
    var calibLevel = $(':input[name="calib_level"]').val();
    var staging = $(':input[name="staging"]').val();

    function addNewArticleButton($fieldset) {
        function acceptBibcode(bibcode) {
            return (
                // TODO placeholder for proper bibcode validator
                bibcode.length == 19 &&
                // avoid duplicated articles
                $(':input[name="bibcode"][value="' + bibcode + '"]', $fieldset).size() === 0
            );
        }

        // add a button to open a dialog for adding new article
        $('> div', $fieldset).append($('\
            <div class="pull-right">\
                <a href="#" class="btn active btn-primary" role="button" data-toggle="modal" data-target="#articleModal" data-loading-text="...">\
                    <span class="glyphicon glyphicon-plus"/>&#160;Add article\
                </a>\
            </div>\
        '));

        var $modal = $('#articleModal');
        // connect to the validate button of the dialog
        $('.modal-footer button:last', $modal).click(function (e) {
            var $btn = $(this).button('loading');

            var $bibcode = $('input[name="bibcode"]', $modal);
            var bibcode = $.trim($bibcode.val());
            if (acceptBibcode(bibcode)) {
                // search for article with bibcode
                $.get('_article-form.html', { 'bibcode': bibcode })
                    .done(function (data) {
                        $(data)
                            .hide()
                            .appendTo($('#articles', $fieldset))
                            .slideDown('slow', function () {
                                // close modal when finished
                                $modal.modal('hide');
                            });
                    });
            } else {
                // incorrect bibcode, decorate field and let user try again
                $bibcode.parents('.form-group').addClass('has-error');
                $btn.button('reset');
            }
        });
        // modal clean up when hiding
        $modal.on('hidden.bs.modal', function (e) {
            $('.form-group', $modal).removeClass('has-error');
            $(':input', $modal).val("");
            $('button', $modal).button('reset');
        });
    }

    function setupCollectionFieldset($fieldset) {
        var $article_fs = $('#articles', $fieldset).parents('.form-group').first();
        var $keywords_fs = $('select[name="keywords"]', $fieldset).parents('.form-group').first();

        // collection of data not published
        if (calibLevel != 3) {
            // connect input for keywords with tagsinput and typeahead
            $('select', $keywords_fs).tagsinput({
                maxTags: 6,
                typeahead: {
                    source: function(query) {
                        return $.get('restxq/oidb/keyword', { 'q': query }, 'json');
                    },
                    items: 'all'
                }
            });

            // disable the field for linked articles
            $article_fs.hide();
        } else {
            // disable the field for keywords (use article keywords instead)
            $keywords_fs.hide();

            // add button to add new article from bibcode
            addNewArticleButton($article_fs);
        }
    };

    function uploadFiles(files) {
        var upload = $.Deferred();

        var uploads = $.map(files, function (file) {
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

            return deferred
                // start uploading when file is read
                .pipe(function (data) {
                    return $.ajax('restxq/oidb/oifits?staging=' + staging + '&filename=' + encodeURIComponent(file.name), {
                        type: 'POST',
                        data: data,
                        contentType: 'application/octet-stream',
                        processData: false,
                    })
                // report progress to parent
                .done(function (data) {
                    upload.notify(data);
                });
            });
        });
        // trigger callbacks when upload completes
        $.when.apply($, uploads).done(function () { upload.resolve() });

        return upload;
    }

    // parse a report from an upload and add entries to the log
    function uploadReport(report, $log, prefix) {
        for (var i = 0; i < report.childNodes.length; i++) {
            var node = report.childNodes[i];
            if (!node.nodeType || node.nodeType !==1) {
                continue;
            }

            var name  = node.getAttribute('name');
            var path  = (prefix) ? prefix + '/' + name : name;
            var $li = $('<li/>', { 'class': 'list-group-item'});

            switch (node.tagName) {
                case "file":
                    $li.text(name + ': Successfully uploaded.').addClass('list-group-item-success').data('path', path);
                    break;
                case "warning":
                    $li.text(name + ': ' + node.textContent).addClass('list-group-item-warning');
                    break;
                case "error":
                    $li.text(name + ': ' + node.textContent).addClass('list-group-item-error');
                    break;
                case "zip":
                    var $ul = $('<ul/>');
                    uploadReport(node, $ul, path);
                    $li.text(name).append($ul);
                    break;
            }

            $li.appendTo($log);
        }
    }

    function addOIFITS(oifits) {
        var $oifits = $(oifits);
        $oifits.insertBefore('#oifits table tfoot');

        // initialize selectors on new granules
        $('[data-role="targetselector"]', $oifits).targetselector();
        $('[data-role="instrumentselector"]', $oifits).instrumentselector();
        $('[data-role="modeselector"]', $oifits).each(function () {
            // connect to its respective instrument selector
            var $row = $(this).closest('tr');
            var $insname = $(':input[name="instrument_name"]', $row);
            $(this).modeselector($insname);
        });

        $('[data-toggle="checkreport"]').checkreport();

        $('tr .dropdown', $oifits).sampify(
            'table.load.fits',
            // prepare parameters for the 'table.load.fits'
            function () {
                // set SAMP parameter to URL of the relevant OIFITS file
                return { "url": $(this).siblings('a').attr('href') };
            });
    }

    function processURL(url) {
        return $.get('_oifits-form.html', { 'url': url }).done(addOIFITS);
    }

    function processUpload(path) {
        return $.get('_oifits-form.html', { 'staging': staging, 'path': path }).done(addOIFITS);
    }

    function setupOIFITSModal() {
        var $modal = $('#oifitsModal');
        var $button = $('.modal-footer button:last', $modal);

        $(':radio', $modal).change(function (e) {
            var $radio = $(this);
            
            // activate the controls for this radio
            $radio.parents('.radio').find('.form-group :input').prop('disabled', false);
            // deactivate the controls for the other
            $(':radio', $modal).not($radio).parents('.radio').find('.form-group :input').prop('disabled', true);
        });

        $(':input[name="files"]', $modal).change(function () {
            var $file = $(this);

            $button.button('loading');

            // setup a log area replacing the file selector
            $file.hide();
            var $log = $('<ul/>', { 'class': 'list-group' })
                .css({ 'overflow-y': 'scroll', 'max-height': '150px' })
                .hide()
                .insertAfter($file)
                .slideDown();
            $modal.on('hidden.bs.modal', function (e) { $log.remove(); $file.show(); });

            uploadFiles($file.get(0).files)
                .progress(function (data) {
                    // update the upload report with status of the latest upload
                    uploadReport(data.documentElement, $log);
                })
                .done(function () {
                    $button.button('reset');
                });
        });

        $button.click(function (e) {
            $(this).button('loading');

            e.preventDefault();

            var oifits = [];

            // get data from urls
            var urls = $(':input[name="urls"]', $modal).val();
            urls = (urls == '') ? [] : urls.split('\n');
            urls
                // filter out url for files that have already been processed or duplicates
                .filter(function (url, index) {
                    return (
                        $('#oifits table tbody').find('tr:first a[href="' + url + '"]').size() == 0 &&
                        urls.indexOf(url) == index
                        );
                })
                .forEach(function (url) {
                    url = $.trim(url);
                    if (url != '') {
                        oifits.push(processURL(url));
                    }
                });

            // get data from uploads
            var uploads = [];
            // pick the paths from the upload report
            $(':input[name="files"] ~ ul', $modal).find('li').each(function (index, element) {
                var path = $(element).data('path');
                if (path) { uploads.push(path); }
            });
            uploads
                .forEach(function (upload) {
                    oifits.push(processUpload(upload));
                });

            // wait until all oifits have been processed and discard dialog
            $.when.apply($, oifits).always(function () { 
                $modal.modal('hide');
            });
        });

        // initialization
        $modal.on('show.bs.modal', function () {
            $(':radio', $modal).first().prop("checked", true).change();
        });
        // modal clean up when hiding
        $modal.on('hidden.bs.modal', function (e) {
            $(':input', $modal).val("");
            $('button', $modal).button('reset');
        });
    }

    $('#create-collection-btn').click(function (e) {
        var $btn = $(this);
        $btn.button('loading');
        $.get('_collection-form.html')
            .done(function (data) {
                var $collection = $(data);
                setupCollectionFieldset($collection);
                $collection.hide().replaceAll($btn.closest('.row')).slideDown('slow');
                $btn.button('reset').remove();
            });
        e.preventDefault();
    });

    setupOIFITSModal();




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

    // Turn fields from the form into a collection XML document
    function serializeCollection($collection) {
        var s = new XMLSerializer();

        // Turn form into XML collection
        var collection = (new DOMParser()).parseFromString('<collection/>', 'text/xml');
        $(':input', $collection)
            .filter('[name="id"]').each(function (index, element) {
                var id = $(element).val();
                collection.documentElement.setAttribute("id", id); 
            }).end()
            .not('#articles :input, [name="id"]').serializeXML(collection, collection.documentElement);
        $('#articles > li', $collection).each(function () {
            var article = collection.createElement('article');
            $(':input', this).serializeXML(collection, article);
            collection.documentElement.appendChild(article);
        });

        return s.serializeToString(collection);
    }

    // Upload a collection XML to the REST endpoint of OiDB
    function saveCollection(collection, id) {
        // save the collection, return the Deferred object of the operation
        if (id === undefined || id === '') {
            // let service create the id for the collection
            return $.ajax('restxq/oidb/collection', { data: collection, contentType: 'application/xml', type: 'POST' })
                .then(function (data, textStatus, xhr) {
                    // pick the collection id from the Location header returned above
                    var id = xhr.getResponseHeader('Location');
                    // ... and update collection form input
                    $('#collection :input[name="id"]').val(id);
                });
        } else {
            return $.ajax('restxq/oidb/collection/' + encodeURIComponent(id), { data: collection, contentType: 'application/xml', type: 'PUT' });
        }
    }

    // Turn granule fields of the form into XML granules and attach each one
    // to an optional collection
    function serializeGranules($granules, collection) {
        var s = new XMLSerializer();

        var data = {};
        // pick info for granules from collection
        if(typeof collection !== "undefined") {
            // FIXME using jQuery on XML, use low level DOM functions instead
            var $collection = $(collection);
            data.obs_collection = $collection.attr('id');

            // data from collection to add to each granule
            var $article = $('article', $collection);
            if ($article.size() !== 0) {
                // may have more than one article attached
                $article = $article.first();
                data.obs_creator_name = $('author', $article).text();
                data.datapi           = $('author', $article).text();
                data.bib_reference    = $('bibcode', $article).text();
                data.obs_release_date = $('pubdate', $article).text();
            }
        }

        // granule calibration level
        data.calib_level = $('input[name="calib_level"]').val();
        // TODO curation info if L < 3
        //
        // TODO handle case with empty datapi (on server side using authenticated user ?)

        var granules = (new DOMParser()).parseFromString('<granules/>', 'text/xml');
        $granules.each(function (index, element) {
            var $granule = $(element);
            // a new, empty XML granule
            var granule = granules.createElement('granule');

            // first common columns
            for (var key in data) {
                var e = granules.createElement(key);
                e.textContent = data[key];
                granule.appendChild(e);
            }

            // granule specific columns
            $(':input', this).prop('disabled', true).serializeXML(granules, granule);

            // add the granule to the list
            granules.documentElement.appendChild(granule);
        });

        return s.serializeToString(granules);
    }

    // Upload a set of XML granules to the REST endpoint of OiDB
    function saveGranules(granules) {
        // save the collection, return the Deferred object of the operation
        return $.ajax('restxq/oidb/granule', { data: granules, contentType: 'application/xml', type: 'POST' });
    }

    $('form').submit(function (e) {
        e.preventDefault();

        if ($('#oifits tr.granule').size() == 0) {
            return;
        }

        var $buttons = $('.btn', this);
        // disable form buttons while the data is uploaded
        $buttons
            .attr('disabled', 'disabled')
            .filter(':submit').append('<img src="resources/images/spinner.gif"/>');

        var $collection_fs = $('#collection');
        // freeze the collection form
        $(':input', $collection_fs).prop('disabled', true);
        $('.tag span[data-role="remove"]', $collection_fs).remove();

        var collection;
        if ($('#collection').size() !== 0) {
            collection = serializeCollection($collection_fs);
        }

        var $granules = $('#oifits tr.granule');
        var granules = serializeGranules($granules, collection);
        
        var save;
        if (collection === undefined) {
            save = saveGranules(granules);
        } else {
            var id = $('#collection :input[name="id"]').val();
            // chain saving the collection and saving the granules
            save = saveCollection(collection, id).pipe(function () {
                // FIXME avoid serializing collection again
                var granules = serializeGranules($granules, serializeCollection($collection_fs));
                return saveGranules(granules);
            });
        }
        save
            // update the status of the granule fields
            .done(function (data) {
                var status = [].slice.call(data.documentElement.childNodes)
                    .filter(function (node) { return node.nodeType && node.nodeType === 1; });

                // at the moment upload is all or nothing
                // i.e. if here, alreay great success!
                $granules.each(function (index, element) {
                    var $granule = $(element);

                    // find the id of the uploaded granule
                    if (!(index < status.length && status[index].tagName == 'id')) {
                        // failed to upload the granule
                        // FIXME display error
                        return;
                    }

                    // will not be selected for upload next time
                    $granule.removeClass('granule');
                    $granule.find('[data-role="targetselector"]').targetselector('destroy');
                    $granule.find('[data-role="instrumentselector"]').instrumentselector('destroy');
                    $granule.find('[data-role="modeselector"]').modeselector('destroy');
                    
                    // turn row into clickable links to granule details
                    var id = parseInt(status[index].textContent, 10);
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
            })
            .done(function(x) {
                // all granule successfully uploaded, reuse the submit button
                $buttons.filter(':submit')
                    .children('img').remove().end()
                    .removeAttr('disabled')
                    .text('Done')
                    .click(function (e) { e.preventDefault(); document.location = "submit.html"; });
            })
            .fail(function (x) {
                // had some failures, let user have another chance
                $buttons.removeAttr('disabled').children('img').remove();
                // re-enable collection form
                $('#collection :input').prop('disabled', false);
                // re-enable inputs of granules
                $('#collection :input').prop('disabled', false);
            });
    });
});
