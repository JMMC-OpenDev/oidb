$(function () {
    $('.input-group.date')
        .datepicker({
            autoclose: true,
            format: 'yyyy-mm-dd'
        })
        // put limits on datepickers of filter for observation dates
        .on('changeDate clearDate', function(e) {
            var $this = $(this);
            // find the other datepicker in the row
            var $other = $this.parents('.form-group').find('.input-group.date').not($this);

            // select method to apply to other datepicker
            var name  = $this.find(':input').attr('name');
            var method = (name == 'date_start') ? 'setStartDate' : 'setEndDate';
            
            $other.datepicker(method, (e.date) ? e.date : false);
        });

    // the panel with filters fields
    var $filters = $('#filters');

    function toggleChevron(e) {
        $(e.target)
            .prev('.panel-heading')
            .find("i.indicator")
            .toggleClass('glyphicon-chevron-down glyphicon-chevron-up');
    }
    // connect the icon in heading with the state of the panel
    $filters.on('hidden.bs.collapse shown.bs.collapse', toggleChevron);

    // collapse filters if not on the first page of the search
    // (i.e. the filters have already been set)
    var page = new RegExp('[?&]page=([^&#]*)').exec(window.location.href);
    if (page && page[1] != 1) {
        $filters.collapse('hide');
    }

    // polish multiselect elements
    $('.multiple').multiselect({
            includeSelectAllOption: true,
            nonSelectedText: "any value",
            allSelectedText: "any value"
            
        }).attr("size","3");
});