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
                    $granule.find('[data-role="targetselector"]').targetselector('destroy');
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


// A plugin to insert a composite control for selecting target in the granule
// table. It requests target resolution with Simbad through OiDB from the 
// initial values of the granule and then update that granule definition on 
// selection changes.
(function ($) {
    "use strict";

    function TargetSelector(element, options) {
        // all target candidates for this selector
        this.targets = [];

        this.$element = $(element);
        this.$input_name = $(':input[name="target_name"]', this.$element);
        this.$input_ra   = $(':input[name="s_ra"]', this.$element);
        this.$input_dec  = $(':input[name="s_dec"]', this.$element);
        
        // new element for selecting target
        this.$select     = $('<select>', { class: 'form-control' }).prependTo(this.$element);

        var textNodes = this.$element.contents().filter(function() {
            return this.nodeType === 3; //Node.TEXT_NODE
        });
        // get the current target description
        var text = $.trim(textNodes.text());
        this.addTarget(text, { name: this.$input_name.val(), ra: this.$input_ra.val(), dec: this.$input_dec.val() });
        // remove it from container
        textNodes.remove();
        
        this.build(options);
    }

    TargetSelector.prototype = {
        constructor: TargetSelector,
        
        addTarget: function(text, target) {
            // associate target string with target description for selector
            this.targets[text] = target;
            // add an option to the select
            $('<option/>', { text: text }).appendTo(this.$select);
        },

        targetText: function(target) {
            // format a target description (then used as text of the select option)
            return target.name + ' - ' + target.ra_hms + ' ' + target.dec_dms;
        },

        build: function(options) {
            var self = this;
            // search for candidates given initial values
            // TODO save resolution results from granule to granule
            $.get(
                'modules/target.xql', 
                { name: self.$input_name.val(), ra: self.$input_ra.val(), dec: self.$input_dec.val()},
                function (data) {
                    $('target', data).each(function () {
                        // simple conversion of target from XML to JSON
                        var target = {};
                        $(this).children().each(function () { target[this.nodeName] = $(this).text(); });
                        // register target description
                        self.addTarget(self.targetText(target), target);
                    });
                }
            );

            // when selecting a target, update the form for the granule
            self.$select.change(function () {
                var key = $(this).find(':selected').text();
                var target = self.targets[key];

                // set value of hidden form fields with target data
                self.$input_name.val(target.name);
                self.$input_ra.val(target.ra);
                self.$input_dec.val(target.dec);
            });
            
            self.$select.change(function () {
                // set validation state depending on the selected item: anything but first option is ok
                var klass = ($(this).find(':selected').index() == 0) ? 'has-warning' : 'has-success';
                self.$element.removeClass('has-warning has-success').addClass(klass);
            });
            // run validation on current choice
            self.$select.change();
        },

        destroy: function() {
            // preserve current text of selector
            var text = this.$select.find(':selected').text();
            // replace the select form element with the target description
            this.$select.replaceWith(text);
        },
    };

    // register plugin
    $.fn.targetselector = function(arg1, arg2) {
        var results = [];
        
        this.each(function() {
            var targetselector = $(this).data('targetselector');
            
            if (!targetselector) {
                // new selector
                targetselector = new TargetSelector(this, arg1);
                $(this).data('targetselector', targetselector);
                results.push(targetselector);
            } else {
                // invoke function on existing target selector
                var retVal = targetselector[arg1](arg2);
                if (retVal !== undefined)
                    results.push(retVal);
            }
        });

        if (typeof arg1 == 'string') {
            return results.length > 1 ? results : results[0];
        } else {
            return results;
        }
    };

    $.fn.targetselector.Constructor = TargetSelector;

    $(function() {
        $('[data-role="targetselector"]').targetselector();
    });
})(window.jQuery);
