$(function () {
    $('.input-group.date').datepicker({
        autoclose: true,
        format: 'yyyy-mm-dd'
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
});