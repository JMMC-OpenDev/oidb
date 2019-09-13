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
        // add-article-button class is set to remote it on first article addition
        $('> div', $fieldset).append($('\
            <div class="pull-right add-article-button">\
                <input value="" placeholder="bibcode" name="bibcode" class="readonly" required="required" role="button" data-toggle="modal" data-target="#articleModal" data-loading-text="..."/>\
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
                        // prevent multiple bibcodes
                        $('.add-article-button', $fieldset).remove();
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
        var $keywords_fs = $('select[name="keyword"]', $fieldset).parents('.form-group').first();

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
            $keywords_fs.remove();

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
        
        $('.oifits-quality-level-selector').change(function() {
        //$("#selectBox").val("3");
        var oifitsdefaultvalue = this.value;
        $(this).parents("tbody").find( ".quality-level-selector" ).val(this.value);
        console.log($(this).parents("tbody").find( ".quality-level-selector" ));
        });

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
        // handle event for file deletion
        $('.remove-granule').click(function () { 
            var oifitstbody = $(this).parents("tbody");
            // $.ajax('restxq/oidb/oifits', { data: { 'staging':'todo' , 'path':'todo'}, type:'DELETE' }).done(
                // function() {
                    oifitstbody.remove();
                // }
            // );
        });
    }

    function processURL(url) {
        return $.get('_oifits-form.html', { 'url': url, 'calib_level': calibLevel }).done(addOIFITS);
    }

    function processUpload(path) {
        return $.get('_oifits-form.html', { 'staging': staging, 'path': path, 'calib_level': calibLevel }).done(addOIFITS);
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
        $.get('_collection-form.html', { calib_level : RegExp('[\?&]calib_level=([^&#]*)').exec(window.location.href)[1]})
            .done(function (data) {
                var $collection = $(data);
                setupCollectionFieldset($collection);
                $collection.hide().replaceAll($btn.closest('.row')).slideDown('slow');
                $btn.button('reset').remove();
            });
        e.preventDefault();
    })
    
    $('#append-to-collection-btn').click(function (e) {
        var $btn = $(this);
        var $form_div = $("#collection")
        $btn.button('loading');
        var colid = $btn.next(":input").val()
        
         $.get( '_collection-form.html?id='+encodeURIComponent(colid) )
            .done(function (data) {
                var $collection = $(data);
                setupCollectionFieldset($collection);
                $collection.hide().replaceAll($btn.closest('.row')).slideDown('slow');
                $btn.button('reset').remove();
                $form_div.find(":input").prop("readonly", true);
                $form_div.find(":input").prop("disabled", true);
                // prevent multiple bibcodes
                 $('.add-article-button').remove();
            });
        e.preventDefault();
    })

    setupOIFITSModal();


    $.fn.serializeXML = function(doc, root) {
        this.each(function () {
            var $input = $(this)
            var name = $input.attr('name');
            var val = $input.val()
            var values = $.isArray(val) ? val : [val] // this special hack is for handling select cases with multiple options
            if (name){
                $.each(values, function( index, value ) {
                    console.log("append element '"+name+"' with "+value); 
                    var e = doc.createElement(name);
                    e.textContent = value;
                    root.appendChild(e);
                });
            }
        });
    };

    // Turn fields from the form into a collection XML document
    function serializeCollection($collection) {
        // Turn form into XML collection
        var collection = (new DOMParser()).parseFromString('<collection/>', 'text/xml');
        $(':input', $collection).not(':radio:not(:checked)')
            .filter('[name="id"]').each(function (index, element) {
                var id = $(element).val();
                collection.documentElement.setAttribute("id", id); 
            }).end()
            .not('#articles :input, [name="id"]')
            .serializeXML(collection, collection.documentElement);
        $('#articles > li', $collection).each(function () {
            var article = collection.createElement('article');
            $(':input', this).serializeXML(collection, article);
            collection.documentElement.appendChild(article);
        });

        return collection;
    }

    // Upload a collection XML to the REST endpoint of OiDB
    function saveCollection(collection) {
        var id = collection.documentElement.getAttribute('id');
        var data = new XMLSerializer().serializeToString(collection);

        // save the collection, return the Deferred object of the operation
        if (id === null || id === '') {
            // let service create the id for the collection
            return $.ajax('restxq/oidb/collection', { data: data, contentType: 'application/xml', type: 'POST' })
                .done(function (data, textStatus, xhr) {
                    // pick the collection id from the Location header returned above
                    var id = xhr.getResponseHeader('Location');
                    // ... then update the collection
                    collection.documentElement.setAttribute('id', id);
                    // ... and update collection form input
                    $('#collection :input[name="id"]').val(id);
                });
        } else {
            return $.ajax('restxq/oidb/collection/' + encodeURIComponent(id), { data: data, contentType: 'application/xml', type: 'PUT' });
        }
    }

    // Turn granule fields of the form into XML granules and attach each one
    // to an optional collection
    function serializeGranules($granules, collection) {
        var data = {};
        
        // pick info for granules from collection
        if(typeof collection !== "undefined") {
            // FIXME using jQuery on XML, use low level DOM functions instead
            var $collection = $('collection', collection);
            
            // data from collection to add to each granule
            data.obs_collection = $collection.attr('id');
            data.keywords = $('keyword', $collection).map(function(){return $(this).text()}).get().join(" ; ");
            
            var $article = $('article', $collection);
            if ($article.size() !== 0) {
                // may have more than one article attached (... in the future : button is by now remove after first successfull article setup)
                $article = $article.first();
                data.bib_reference    = $('bibcode', $article).text();
                data.obs_release_date = $('pubdate', $article).text();
            }
        }

        // granule calibration level
        data.calib_level = $('input[name="calib_level"]').val();
        // datapi = obs_creator_name
        data.datapi      = $('input[name="datapi"]').val();
        data.obs_creator_name = data.datapi
        // TODO curation info if L < 3

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

			// columns inherited from the oifits file
            var p = $(this).parent("tbody").find('input[name="progid"]');
            $(p, this).prop('disabled', true).serializeXML(granules, granule);

            // granule specific columns
            $(':input', this).prop('disabled', true).serializeXML(granules, granule);

            // add the granule to the list
            granules.documentElement.appendChild(granule);
        });

        return granules;
    }

    // Upload a set of XML granules to the REST endpoint of OiDB
    function saveGranules(granules) {
        var data = new XMLSerializer().serializeToString(granules);

        // save the granule, return the Deferred object of the operation
        return $.ajax('restxq/oidb/granule', { data: data, contentType: 'application/xml', type: 'POST' });
    }

    $('form').submit(function (e) {
        e.preventDefault();

        var $collection_fs = $('#collection');
        var collection = serializeCollection($collection_fs);
        var $granules = $('#oifits tr.granule');
        
        // perform some checkup before submit
        $error_list = $("#errorModalList").empty();
        if ($('#oifits tr.granule').size() == 0) {
            $error_list.append($("<li>You must add one or more OIFits file(s) in step 1 section</li>"));
        }
        if ($collection_fs.length == 0) {
            $error_list.append($("<li>You must create or select a collection in step 2 section</li>"));
        }else{
            if ( ! ( $(':input[name="name"]',$collection_fs).val() && $(':input[name="title"]',$collection_fs).val() ) ) {
                $error_list.append($("<li>You must create a new collection with appropriate <b>name</b> and <b>title</b> of your collection in step 2 section</li><li>If present, you can also select an existing collection and click <b>Append to</b>.</li>"));
            }
        }
        if( $error_list.has( "li" ).length ){
            $("#errorModal").modal();
            return;
        }
        

        var $buttons = $('.btn', this);
        // disable form buttons while the data is uploaded
        $buttons
            .attr('disabled', 'disabled')
            .filter(':submit').append('<img src="resources/images/spinner.gif"/>');

        // freeze the collection form
        $(':input', $collection_fs).prop('disabled', true);
        $('.tag span[data-role="remove"]', $collection_fs).remove();


        $.when(1)
            // save the collection if any
            .pipe(function () {
                return saveCollection(collection);
            })
            // save all granules
            .pipe(function () {
                var granules = serializeGranules($granules, collection);
                return saveGranules(granules);
            })
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
                
                $('.oifits-quality-level-selector').prop('disabled', true);

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
                console.warn("Error occured : " + x.responseText)
                // had some failures, let user have another chance
                $buttons.removeAttr('disabled').children('img').remove();
                // re-enable collection form
                $('#collection :input').prop('disabled', false);
                // re-enable inputs of granules
                $('#collection :input').prop('disabled', false);
            });
    });
    
    $('#oifits')
        .find('tr .dropdown').one('click', function (e) {
            $(this).sampify(
                'table.load.fits',
                // prepare parameters for the 'table.load.fits'
                function () {
                    // set SAMP parameter to URL of the relevant OIFITS file
                    return { "url": $(this).siblings('a').attr('href') };
                });
        }).end()
        .find('tr [data-toggle="checkreport"]').checkreport();
});
