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
        
        addOption: function(text, data, parent) {
            parent = $(parent || this.$select);
            // add an option
            $('<option/>', { text: text }).data(data).appendTo(parent);
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
                var klass = ($(this).find(':selected').index(self.$select.find('option')) == 0) ? 'has-warning' : 'has-success';
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
                    $input.val(value[$input.attr('name')]).change();
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

        purge: function() {
            // remove all but first option from internal <select/>
            this.$select.children('option')
                // force select the first (default) option
                .eq(1).prop('selected', true).end()
                // remove all options but first
                .not(':first').remove().end();
            this.$select.change();
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
        this.fetchTargets().done(function (data) {
            var $optgroup = $('<optgroup/>', { label: 'Simbad objects in vicinity'}).appendTo(self.$select);
            $.each(data, function (idx, target) {
                var text = target.target_name + ' - ' + target.ra_hms + ' ' + target.dec_dms;
                // register target description
                self.addOption(text, target, $optgroup);
            });
        });
    }
    TargetSelector.prototype = new Selector();
    // overwrite build function to avoid color highlighting (origin data are considered more reliable)
    TargetSelector.prototype.build = function(options) {
            var self = this;

            // when selecting an option, update the form inputs
            self.$select.change(function () {
                var data = $(this).find(':selected').data();
                // set value of hidden form fields with selected data
                self.val(data);
            });
            
            // run validation on current choice
            self.$select.change();
        };
    TargetSelector.prototype.constructor = TargetSelector;
    TargetSelector.prototype.targetCache = {};
    TargetSelector.prototype.fetchTargets = function () {
        // translate single XML target element into JavaScript object
        function transformTarget(idx, target) {
            var ret = {};
            $(target).children().each(function () {
                var text = $(this).text();
                switch (this.nodeName) {
                    // convert from node names to column names
                    case "name": ret.target_name = text; break;
                    case "ra":   ret.s_ra        = text; break;
                    case "dec":  ret.s_dec       = text; break;
                    default:     ret[this.nodeName] = text;
                }
            });
            return ret;
        }

        var text = this.text();
        if (!(text in this.targetCache)) {
            var value = this.val();
            // caching results of the query
            this.targetCache[text] = $
                .get('modules/target.xql', { name: value.target_name, ra: value.s_ra, dec: value.s_dec })
                .pipe(function (data) {
                    // transform XML document to JavaScript array
                    return $('target', data).map(transformTarget).toArray();
                });
        }
        return this.targetCache[text];
    };

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
        this.fetchInstruments().done(function (data) {
            var $optgroup = $('<optgroup/>', { label: 'Facilities and instruments'}).appendTo(self.$select);
            $.each(data, function (idx, instrument) {
                var text = instrument.facility_name + ' - ' + instrument.instrument_name;
                // register instrument description
                self.addOption(text, instrument, $optgroup);
            });
            
            // try to autoselect valid facility/instrument pair
            var val = self.val(); // the initial value
            // canonicalize the current facility and instrument names
            var facility_name = val.facility_name.match(/[A-Z]*/i).shift();
            var instrument_name = val.instrument_name.match(/[A-Z]*/i).shift();
            // (skip over option from file, pick suggested instead)
            $('option:gt(0)', self.$select)
                .filter(function () {
                    var data = $(this).data();
                    return data.instrument_name == instrument_name &&
                        data.facility_name == facility_name;
                })
                .prop('selected', true)
                .change();
        });
    }
    InstrumentSelector.prototype = new Selector();
    InstrumentSelector.prototype.constructor = InstrumentSelector;
    InstrumentSelector.prototype.instrumentCache = {};
    InstrumentSelector.prototype.fetchInstruments = function () {
        // translate single XML instrument element into JavaScript object
        function transformInstrument(idx, instrument) {
            var $instrument = $(instrument);
            var ret = {};
            ret.instrument_name = $instrument.attr('name');
            ret.facility_name   = $instrument.attr('facility');
            return ret;
        }

        var text = this.text();
        if (!(text in this.instrumentCache)) {
            var value = this.val();
            // caching results of the query
            this.instrumentCache[text] = $
                .get('restxq/oidb/instrument', this.val())
                .pipe(function (data) {
                    return $('instrument', data).map(transformInstrument).toArray();
                });
        }
        return this.instrumentCache[text];
    };

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

    // A plugin to insert a control for selecting instrument mode in the
    // granule table. It connects to the instrument selector and updates the
    // options on instrument changes.
    function ModeSelector(target, trigger) {
        var self = this;
        Selector.apply(self, [ target ]);

        self.$source = $(trigger);
        self.$source.change(function (e) {
            // remove suggestion for last choice of instrument name
            self.purge();
            // replace with mode for current instrument
            self.fetchModes().done(function (modes) {
                $.each(modes, function () {
                    var text = this.instrument_mode + ' (' + this.wlmin.toFixed(2) + '-' + this.wlmax.toFixed(2) + 'µm)';
                    self.addOption(text, this);
                });
            });
        });
    }
    ModeSelector.prototype = new Selector();
    ModeSelector.prototype.constructor = ModeSelector;
    ModeSelector.prototype.modeCache = {};
    ModeSelector.prototype.fetchModes = function () {
        var insname = this.$source.val();
        if (!(insname in this.modeCache)) {
            // caching results of the query
            this.modeCache[insname] = $
                .get('restxq/oidb/instrument/' + encodeURIComponent(insname) + '/mode', {})
                .pipe(function (data) {
                    return $.map(data, function (m) {
                        return {
                            'instrument_mode': m.name,
                            'wlmin':           parseFloat(m.waveLengthMin),
                            'wlmax':           parseFloat(m.waveLengthMax)
                        };
                    });
                });
        }
        return this.modeCache[insname];
    };

    // register mode selector as jQuery plugin
    $.fn.modeselector = function(arg1, arg2) {
        var results = [];
        
        this.each(function() {
            var modeselector = $(this).data('modeselector');
            
            if (!modeselector) {
                // new selector
                modeselector = new ModeSelector(this, arg1);
                $(this).data('modeselector', modeselector);
                results.push(modeselector);
            } else {
                // invoke function on existing mode selector
                var retVal = modeselector[arg1](arg2);
                if (retVal !== undefined)
                    results.push(retVal);
            }
        });
        
        return results;
    };
    $.fn.modeselector.Constructor = ModeSelector;

    $(function() {
        $('[data-role="targetselector"]').targetselector();
        $('[data-role="instrumentselector"]').instrumentselector();

        $('[data-role="modeselector"]').each(function () {
            // connect to its respective instrument selector
            var $row = $(this).closest('tr');
            var $insname = $(':input[name="instrument_name"]', $row);

            $(this).modeselector($insname);
        });
    });
})(window.jQuery);
