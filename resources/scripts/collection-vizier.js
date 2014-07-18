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


(function ($) {
    "use strict";

    // A base object for inserting a drop-down list of options for multiple,
    // hidden input fields.
    function Selector(element, options) {
        this.$element = $(element);
        
        // new element for displaying choices
        this.$select = $('<select>', { class: 'form-control' }).prependTo(this.$element);

        // save initial description as first select option
        var textNodes = this.$element.contents().filter(function() {
            return this.nodeType === 3; //Node.TEXT_NODE
        });
        var text = $.trim(textNodes.text());
        textNodes.remove();
        this.addOption(text, this.val());
        
        this.build(options);
    }
    Selector.prototype = {
        constructor: Selector,
        
        addOption: function(text, data) {
            // add an option to the select
            $('<option/>', { text: text }).data(data).appendTo(this.$select);
        },

        build: function(options) {
            var self = this;

            // when selecting an option, update the form inputs
            self.$select.change(function () {
                var data = $(this).find(':selected').data();
                // set value of hidden form fields with selected data
                self.val(data);
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
            // replace the select form element with the selected option text
            this.$select.replaceWith(this.text());
        },

        val: function(value) {
            var $inputs = $(':input:hidden', this.$element);
            if (!arguments.length) {
                // get the current value of the input fields
                var value = {};
                $inputs.each(function () {
                    var $input = $(this);
                    value[$input.attr('name')] = $input.val();
                });
                return value;
            } else {
                // set the current value of the input fields
                $inputs.each(function () {
                    var $input = $(this);
                    $input.val(value[$input.attr('name')]);
                });
            }
        },
        
        text: function() {
            // return the text of the selected option
            return this.$select.find(':selected').text();
        },
        
        select: function() {
            // return the internal <select/> element 
            return this.$select;
        },
    };

    // A plugin to insert a composite control for selecting target in the
    // granule table. It requests target resolution with Simbad through OiDB 
    // from the initial values of the granule and then update that granule
    // definition on selection changes.
    function TargetSelector() {
        var self = this;
        Selector.apply(self, arguments);
        
        // search for candidates given initial values
        var value = this.val();
        // TODO save results from granule to granule
        $.get(
            'modules/target.xql', 
            { name: value.target_name, ra: value.s_ra, dec: value.s_dec },
            function (data) {
                $('target', data).each(function () {
                    var target = {};
                    $(this).children().each(function () {
                        var text = $(this).text();
                        switch (this.nodeName) {
                            // convert from node names to column names
                            case "name": target.target_name = text; break;
                            case "ra":   target.s_ra        = text; break;
                            case "dec":  target.s_dec       = text; break;
                            default:     target[this.nodeName] = text;
                        }
                    });
                    var text = target.target_name + ' - ' + target.ra_hms + ' ' + target.dec_dms;
                    // register target description
                    self.addOption(text, target);
                });
            }
        );
    }
    TargetSelector.prototype = new Selector();
    TargetSelector.prototype.constructor = TargetSelector;

    // register target selector as jQuery plugin
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
        
        return results;
    };
    $.fn.targetselector.Constructor = TargetSelector;
    
    // A plugin to insert a composite control for selecting instrument in the
    // granule table. It queries OiDB to build an option list of instruments
    // and facilities.The definition of the granule is updated on selection of
    // an entry.
    function InstrumentSelector() {
        var self = this;
        Selector.apply(self, arguments);
        
        // search for candidates given initial values
        var value = this.val();
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
                    var text = instrument.facility + ' - ' + instrument.name;
                    self.addOption(text, instrument);
                });
            }
        );
    }
    InstrumentSelector.prototype = new Selector();
    InstrumentSelector.prototype.constructor = InstrumentSelector;

    // register instrument selector as jQuery plugin
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
        
        return results;
    };
    $.fn.instrumentselector.Constructor = InstrumentSelector;

    $(function() {
        $('[data-role="targetselector"]').targetselector();
        $('[data-role="instrumentselector"]').instrumentselector();
    });
})(window.jQuery);
