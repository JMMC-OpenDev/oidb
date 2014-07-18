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
                    $granule.find('[data-role="instrumentselector"]').instrumentselector('destroy');
                    $granule.find(':input[name="instrument_mode"]').replaceWith(function () { return $(':selected', this).text(); });
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

    // Drop-down list of instrument:
    // event handler for updating the list of mode on changes to the instrument
    $(':input[name="instrument_name"]').change(function (e) {
        var $insname = $(this);
        var $granule = $insname.parents('.granule').first();
        var $insmode = $(':input[name="instrument_mode"]', $granule);

        // TODO filter out possible value from oifits
        // remove all <option> but first (unknown)
        $insmode.children('option:gt(0)').remove();
        // TODO save results from request to request
        $.get(
            '/exist/restxq/oidb/instrument/' + encodeURIComponent($insname.val()) + '/mode',
            {},
            function (data) {
		// parse the XML returned for mode names
                $('mode', data).each(function () {
                    var mode = this.textContent;
                    $insmode.append($('<option>', { value: mode, text: mode}));
                });
            });
    });
    // instrument mode validation: warning if no mode selected, success otherwise
    $(':input[name="instrument_mode"]').change(function () {
        var klass = ($(this).find(':selected').index() == 0) ? 'has-warning' : 'has-success';
        $(this).parent().removeClass('has-warning has-success').addClass(klass);
    }).change();
});


// A plugin to insert a composite control for selecting target in the granule
// table. It requests target resolution with Simbad through OiDB from the 
// initial values of the granule and then update that granule definition on 
// selection changes.
(function ($) {
    "use strict";

    function TargetSelector(element, options) {
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
            // add an option to the select
            $('<option/>', { text: text }).data(target).appendTo(this.$select);
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
                var target = $(this).find(':selected').data();

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


// A plugin to insert a composite control for selecting instrument in the granule
// table. It queries OiDB to build an option list of instruments and facilities.
// The definition of the granule is updated on selection of an entry.
// TODO rewrite and merge with target selector
(function ($) {
    "use strict";

    function InstrumentSelector(element, options) {
        // all instrument candidates for this selector
        this.instruments = [];

        this.$element = $(element);
        this.$input_facname = $(':input[name="facility_name"]', this.$element);
        this.$input_insname = $(':input[name="instrument_name"]', this.$element);

        // new element for selecting instrument
        this.$select = $('<select>', { class: 'form-control' }).prependTo(this.$element);

        var textNodes = this.$element.contents().filter(function() {
            return this.nodeType === 3; //Node.TEXT_NODE
        });
        // get the current instrument description
        var text = $.trim(textNodes.text());
        this.addInstrument(text, { facility: this.$input_facname.val(), name: this.$input_insname.val() });
        // remove it from container
        textNodes.remove();
        
        this.build(options);
    }

    InstrumentSelector.prototype = {
        constructor: InstrumentSelector,
        
        addInstrument: function(text, instrument) {
            // associate instrument string with instrument description for selector
            this.instruments[text] = instrument;
            // add an option to the select
            $('<option/>', { text: text }).appendTo(this.$select);
        },

        instrumentText: function(instrument) {
            // format an instrument description (then used as text of the select option)
            return instrument.facility + ' - ' + instrument.name;
        },

        build: function(options) {
            var self = this;
            // search for candidates given initial values
            // TODO save results from granule to granule
            $.get(
                '/exist/restxq/oidb/instrument', 
                {},
                function (data) {
                    $('instrument', data).each(function () {
                        // simple conversion of instrument from XML to JSON
                        var instrument = {};
                        $(this.attributes).each(function () { instrument[this.name] = this.value; });
                        // register instrument description
                        self.addInstrument(self.instrumentText(instrument), instrument);
                    });
                }
            );

            // when selecting an instrument, update the form for the granule
            self.$select.change(function () {
                var key = $(this).find(':selected').text();
                var instrument = self.instruments[key];

                // set value of hidden form fields with instrument data
                self.$input_facname.val(instrument.facility).change();
                self.$input_insname.val(instrument.name).change();
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
            // replace the select form element with the instrument description
            this.$select.replaceWith(text);
        },
    };

    // register plugin
    $.fn.instrumentselector = function(arg1, arg2) {
        var results = [];
        
        this.each(function() {
            var instrumentselector = $(this).data('instrumentselector');
            
            if (!instrumentselector) {
                // new selector
                instrumentselector = new InstrumentSelector(this, arg1);
                $(this).data('instrumentselector', instrumentselector);
                results.push(instrumentselector);
            } else {
                // invoke function on existing instrument selector
                var retVal = instrumentselector[arg1](arg2);
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

    $.fn.instrumentselector.Constructor = InstrumentSelector;

    $(function() {
        $('[data-role="instrumentselector"]').instrumentselector();
    });
})(window.jQuery);
