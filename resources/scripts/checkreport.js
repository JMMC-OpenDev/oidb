(function ($) {
    "use strict";

    // A helper to customize Bootstrap popover for OIFitsExplorer reports
    $.fn.extend({
       checkreport: function (options) {
        var defaults = {
            title: 'OIFitsExplorer Parser Report',
            // rebuild content each time from original report
            // FIXME may instead prepare content once and reuse
            content: function() {
                var report = $(this).data('report');
                var content = '<ul class="list-unstyled">';
                $.each(report.split("\n"), function () {
                    var level = this.trim().split(/\b\s+/)[0];
                    var klass = "";
                    // colorize the log messages
                    switch (level) {
                        case 'INFO':    klass = 'text-info';    break;
                        case 'WARNING': klass = 'text-warning'; break;
                        case 'SEVERE':  klass = 'text-danger';  break;
                        default:        klass = 'text-muted';
                    }
                    content += '<li class="' + klass + '">' + this + '</li>';
                });
                content += '</li>';
                return content;
            },
            html: true,
            trigger: 'hover'
        };
        options = $.extend({}, defaults, options);
        this
            // conflicts with XQuery templating if present, unused on client
            .removeAttr('data-template')
            .popover(options);
       }
   });
})(window.jQuery);